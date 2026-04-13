/*==============================================================
  FILE: OCR_01_Setup.sas
  PURPOSE: One-time setup — creates all OCR tables in SQL Server
           if they do not already exist. Covers both Motor and
           Non-Motor trackers.
           Safe to re-run — all DDL is guarded with IF NOT EXISTS.

  TABLES CREATED:
    OCR_Cycle_Control   — Motor: one row per cycle.
    OCR_Weekly_Tracker  — Motor: one row per week per cycle.
    NM_Cycle_Control    — Non-Motor: one row per cycle.
    NM_Weekly_Tracker   — Non-Motor: one row per week per cycle.
    OCR_Run_Log         — Shared audit log for all job steps.

  RUN: Once, manually, before any other files are executed.
==============================================================*/

/*--------------------------------------------------------------
  Libname
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
  Pass-through DDL — sent directly to SQL Server.
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
    MOTOR: OCR_Cycle_Control
  ------------------------------------------------------------*/
  execute (
    IF NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = 'Claims' AND TABLE_NAME = 'OCR_Cycle_Control'
    )
    BEGIN
      CREATE TABLE FNB_STI_Analytics.Claims.OCR_Cycle_Control (
          CycleID        VARCHAR(6)    NOT NULL,
          BaselineDate   DATE          NOT NULL,
          BaselineClaims INT           NOT NULL,
          BaselineOCR    DECIMAL(18,2) NOT NULL,
          Status         VARCHAR(10)   NOT NULL DEFAULT 'ACTIVE',
          CreatedAt      DATETIME2     NOT NULL DEFAULT GETDATE(),
          UpdatedAt      DATETIME2     NOT NULL DEFAULT GETDATE(),
          CONSTRAINT PK_OCR_Cycle_Control PRIMARY KEY (CycleID)
      )
    END
  ) by sqlsvr;

  /*------------------------------------------------------------
    MOTOR: OCR_Weekly_Tracker
  ------------------------------------------------------------*/
  execute (
    IF NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = 'Claims' AND TABLE_NAME = 'OCR_Weekly_Tracker'
    )
    BEGIN
      CREATE TABLE FNB_STI_Analytics.Claims.OCR_Weekly_Tracker (
          TrackerID             INT IDENTITY(1,1) PRIMARY KEY,
          CycleID               VARCHAR(6)     NOT NULL,
          WeekSequence          INT            NOT NULL,
          WeekLabel             VARCHAR(20)    NOT NULL,
          RunDate               DATE           NOT NULL,
          Baseline_Claims       INT            NOT NULL,
          Open_Claims           INT            NOT NULL,
          Current_OCR_Amt       DECIMAL(18,2)  NOT NULL,
          Cumul_Closed          INT            NOT NULL,
          Closed_This_Week      INT            NOT NULL,
          OCR_Reduced_This_Week DECIMAL(18,2)  NOT NULL,
          Pct_Claims_Closed     DECIMAL(10,6)  NOT NULL,
          CONSTRAINT UQ_OCR_Tracker_CycleWeek UNIQUE (CycleID, WeekSequence)
      )
    END
  ) by sqlsvr;

  /*------------------------------------------------------------
    MOTOR: Migrate any legacy tracker rows (backfill CycleID /
    WeekSequence where NULL from old schema).
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
    MOTOR: Backfill OCR_Cycle_Control from legacy tracker rows.
  ------------------------------------------------------------*/
  execute (
    INSERT INTO FNB_STI_Analytics.Claims.OCR_Cycle_Control
        (CycleID, BaselineDate, BaselineClaims, BaselineOCR, Status)
    SELECT t.CycleID, t.RunDate, t.Baseline_Claims, t.Current_OCR_Amt, 'CLOSED'
    FROM FNB_STI_Analytics.Claims.OCR_Weekly_Tracker t
    WHERE t.WeekSequence = 0
      AND NOT EXISTS (
        SELECT 1 FROM FNB_STI_Analytics.Claims.OCR_Cycle_Control c
        WHERE c.CycleID = t.CycleID
      )
  ) by sqlsvr;

  /*------------------------------------------------------------
    NON-MOTOR: NM_Cycle_Control
    Identical structure to OCR_Cycle_Control — kept separate so
    Motor and Non-Motor cycle histories never intermingle.
  ------------------------------------------------------------*/
  execute (
    IF NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = 'Claims' AND TABLE_NAME = 'NM_Cycle_Control'
    )
    BEGIN
      CREATE TABLE FNB_STI_Analytics.Claims.NM_Cycle_Control (
          CycleID        VARCHAR(6)    NOT NULL,
          BaselineDate   DATE          NOT NULL,
          BaselineClaims INT           NOT NULL,
          BaselineOCR    DECIMAL(18,2) NOT NULL,
          Status         VARCHAR(10)   NOT NULL DEFAULT 'ACTIVE',
          CreatedAt      DATETIME2     NOT NULL DEFAULT GETDATE(),
          UpdatedAt      DATETIME2     NOT NULL DEFAULT GETDATE(),
          CONSTRAINT PK_NM_Cycle_Control PRIMARY KEY (CycleID)
      )
    END
  ) by sqlsvr;

  /*------------------------------------------------------------
    NON-MOTOR: NM_Weekly_Tracker
    Identical structure to OCR_Weekly_Tracker — separate table,
    separate history.
  ------------------------------------------------------------*/
  execute (
    IF NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = 'Claims' AND TABLE_NAME = 'NM_Weekly_Tracker'
    )
    BEGIN
      CREATE TABLE FNB_STI_Analytics.Claims.NM_Weekly_Tracker (
          TrackerID             INT IDENTITY(1,1) PRIMARY KEY,
          CycleID               VARCHAR(6)     NOT NULL,
          WeekSequence          INT            NOT NULL,
          WeekLabel             VARCHAR(20)    NOT NULL,
          RunDate               DATE           NOT NULL,
          Baseline_Claims       INT            NOT NULL,
          Open_Claims           INT            NOT NULL,
          Current_OCR_Amt       DECIMAL(18,2)  NOT NULL,
          Cumul_Closed          INT            NOT NULL,
          Closed_This_Week      INT            NOT NULL,
          OCR_Reduced_This_Week DECIMAL(18,2)  NOT NULL,
          Pct_Claims_Closed     DECIMAL(10,6)  NOT NULL,
          CONSTRAINT UQ_NM_Tracker_CycleWeek UNIQUE (CycleID, WeekSequence)
      )
    END
  ) by sqlsvr;

  /*------------------------------------------------------------
    SHARED: OCR_Run_Log — audit trail for all job steps
    (Motor and Non-Motor both write here via %ocr_log).
  ------------------------------------------------------------*/
  execute (
    IF NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_SCHEMA = 'Claims' AND TABLE_NAME = 'OCR_Run_Log'
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

%put NOTE: Setup complete. Motor tables (OCR_Cycle_Control, OCR_Weekly_Tracker),;
%put NOTE: Non-Motor tables (NM_Cycle_Control, NM_Weekly_Tracker), and OCR_Run_Log are ready.;
