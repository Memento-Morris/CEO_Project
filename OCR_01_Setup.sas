/*==============================================================
  FILE: OCR_01_Setup.sas
  PURPOSE: One-time setup — creates all OCR tables in SQL Server
           if they do not already exist.
           Safe to re-run — all DDL is guarded with IF NOT EXISTS.

  TABLES CREATED:
    OCR_Cycle_Control   — one row per cycle; tracks active cycle
                          so no hardcoding is ever needed in
                          downstream jobs.
    OCR_Weekly_Tracker  — one row per week per cycle; full history
                          kept forever, nothing is deleted.
    OCR_Run_Log         — audit log for every job step.

  RUN: Once, manually, before any other files are executed.

  CHANGES: No bugs found in this file. No changes.
==============================================================*/

/*--------------------------------------------------------------
  1. Libname
--------------------------------------------------------------*/
%include "/data/fnbins/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Automation/STI_CA_2/Libnames.sas";

%macro logging(libname, database, schema, server);
LIBNAME &libname odbc noprompt="
  Driver=MSSQL;
  AnsiNPW=1;
  AuthenticationMethod=10;
  ApplicationUsingThreads=1;
  BulkLoadOptions=2;
  Database=&database;
  FetchTWFSasTime=1;
  HostName=&server;
  PortNumber=1433;
  UID=&User.;
  PWD=&FNB_Login."
Schema=&schema;
%mend;

%logging(STI_WER, FNB_STI_Analytics, Claims, LFE-RBPREATLDB1);

/*--------------------------------------------------------------
  2. Pass-through DDL — sent directly to SQL Server.
     Each statement is guarded so this file is safe to re-run.
--------------------------------------------------------------*/
proc sql;
  connect to odbc as sqlsvr (
    noprompt="Driver=MSSQL;
              AnsiNPW=1;
              AuthenticationMethod=10;
              Database=FNB_STI_Analytics;
              HostName=LFE-RBPREATLDB1;
              PortNumber=1433;
              UID=&User.;
              PWD=&FNB_Login."
  );

  /*------------------------------------------------------------
    2a. OCR_Cycle_Control
        One row per cycle. The Baseline job inserts a row here
        on the 16th; the Weekly job reads from here to know the
        active CycleID — no hardcoding required anywhere.

        Columns:
          CycleID        YYYYMM — primary key, matches tracker.
          BaselineDate   The date the baseline was captured.
          BaselineClaims Snapshot claim count at baseline.
          BaselineOCR    Snapshot OCR amount at baseline.
          Status         ACTIVE | CLOSED
                           ACTIVE  = cycle is in progress.
                           CLOSED  = all weeks complete (set
                                     manually or by a future
                                     close-off job).
          CreatedAt      Timestamp the row was first created.
          UpdatedAt      Timestamp of the last status change.
  ------------------------------------------------------------*/
  execute (
    IF NOT EXISTS (
      SELECT 1
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = 'Claims'
        AND TABLE_NAME   = 'OCR_Cycle_Control'
    )
    BEGIN
      CREATE TABLE FNB_STI_Analytics.Claims.OCR_Cycle_Control (
          CycleID        VARCHAR(6)    NOT NULL,  /* YYYYMM            */
          BaselineDate   DATE          NOT NULL,  /* Date of baseline  */
          BaselineClaims INT           NOT NULL,  /* Claim count       */
          BaselineOCR    DECIMAL(18,2) NOT NULL,  /* OCR amount        */
          Status         VARCHAR(10)   NOT NULL   /* ACTIVE | CLOSED   */
                           DEFAULT 'ACTIVE',
          CreatedAt      DATETIME2     NOT NULL
                           DEFAULT GETDATE(),
          UpdatedAt      DATETIME2     NOT NULL
                           DEFAULT GETDATE(),
          CONSTRAINT PK_OCR_Cycle_Control PRIMARY KEY (CycleID)
      )
    END
  ) by sqlsvr;

  /*------------------------------------------------------------
    2b. OCR_Weekly_Tracker
        One row per week per cycle. Rows are NEVER deleted —
        the full history of every cycle is preserved here.
        CycleID is a foreign key to OCR_Cycle_Control.
  ------------------------------------------------------------*/
  execute (
    IF NOT EXISTS (
      SELECT 1
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = 'Claims'
        AND TABLE_NAME   = 'OCR_Weekly_Tracker'
    )
    BEGIN
      CREATE TABLE FNB_STI_Analytics.Claims.OCR_Weekly_Tracker (
          TrackerID             INT IDENTITY(1,1) PRIMARY KEY,
          CycleID               VARCHAR(6)     NOT NULL,  /* FK to OCR_Cycle_Control */
          WeekSequence          INT            NOT NULL,  /* 0=Baseline, 1,2,3...    */
          WeekLabel             VARCHAR(20)    NOT NULL,  /* 'Baseline','Week 1'...  */
          RunDate               DATE           NOT NULL,  /* Date this row was run   */
          Baseline_Claims       INT            NOT NULL,
          Open_Claims           INT            NOT NULL,
          Current_OCR_Amt       DECIMAL(18,2)  NOT NULL,
          Cumul_Closed          INT            NOT NULL,
          Closed_This_Week      INT            NOT NULL,
          OCR_Reduced_This_Week DECIMAL(18,2)  NOT NULL,
          Pct_Claims_Closed     DECIMAL(10,6)  NOT NULL,
          CONSTRAINT UQ_OCR_Tracker_CycleWeek
            UNIQUE (CycleID, WeekSequence)
      )
    END
  ) by sqlsvr;

  /*------------------------------------------------------------
    2c. Migrate any legacy rows that predate OCR_Cycle_Control.
        Backfill CycleID from RunDate and WeekSequence from
        WeekLabel where they are NULL (old schema rows only).
        Safe to re-run — WHERE CycleID IS NULL means it only
        touches rows not yet migrated.
  ------------------------------------------------------------*/
  execute (
    UPDATE FNB_STI_Analytics.Claims.OCR_Weekly_Tracker
    SET
      CycleID      = FORMAT(RunDate, 'yyyyMM'),
      WeekSequence = CASE WeekLabel
                       WHEN 'Baseline' THEN 0
                       WHEN 'Week 1'   THEN 1
                       WHEN 'Week 2'   THEN 2
                       WHEN 'Week 3'   THEN 3
                       WHEN 'Week 4'   THEN 4
                       WHEN 'Week 5'   THEN 5
                       ELSE NULL
                     END
    WHERE CycleID IS NULL
  ) by sqlsvr;

  /*------------------------------------------------------------
    2d. Backfill OCR_Cycle_Control from any legacy tracker rows
        that have no corresponding control record yet.
        Groups the tracker by CycleID to derive the baseline row
        and inserts a CLOSED record for each historical cycle.
  ------------------------------------------------------------*/
  execute (
    INSERT INTO FNB_STI_Analytics.Claims.OCR_Cycle_Control
        (CycleID, BaselineDate, BaselineClaims, BaselineOCR, Status)
    SELECT
        t.CycleID,
        t.RunDate          AS BaselineDate,
        t.Baseline_Claims  AS BaselineClaims,
        t.Current_OCR_Amt  AS BaselineOCR,
        'CLOSED'           AS Status
    FROM FNB_STI_Analytics.Claims.OCR_Weekly_Tracker t
    WHERE t.WeekSequence = 0          /* Baseline rows only */
      AND NOT EXISTS (
        SELECT 1
        FROM FNB_STI_Analytics.Claims.OCR_Cycle_Control c
        WHERE c.CycleID = t.CycleID
      )
  ) by sqlsvr;

  /*------------------------------------------------------------
    2e. OCR_Run_Log — audit trail for every job step.
  ------------------------------------------------------------*/
  execute (
    IF NOT EXISTS (
      SELECT 1
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = 'Claims'
        AND TABLE_NAME   = 'OCR_Run_Log'
    )
    BEGIN
      CREATE TABLE FNB_STI_Analytics.Claims.OCR_Run_Log (
          LogID            INT IDENTITY(1,1) PRIMARY KEY,
          RunDate          DATETIME2   DEFAULT GETDATE() NOT NULL,
          WeekNum          INT,
          CycleID          VARCHAR(6),
          ProcessStep      VARCHAR(50)  NOT NULL,
          Status           VARCHAR(20)  NOT NULL,
          RecordsProcessed INT,
          MetricValue      DECIMAL(18,2),
          ErrorMessage     VARCHAR(1000),
          AdditionalInfo   VARCHAR(500)
      )
    END
  ) by sqlsvr;

  disconnect from sqlsvr;
quit;

%put NOTE: Setup complete. OCR_Cycle_Control, OCR_Weekly_Tracker, and OCR_Run_Log are ready.;
