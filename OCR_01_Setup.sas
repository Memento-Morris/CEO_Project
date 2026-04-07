/*==============================================================
  FILE: OCR_01_Setup.sas
  PURPOSE: One-time setup — creates the OCR_Weekly_Tracker
           table and OCR_Run_Log table in SQL Server if they
           do not already exist. Also adds CycleID and
           WeekSequence columns to OCR_Weekly_Tracker if they
           are missing (safe to re-run).
  RUN: Once, manually, before any other files are executed.
       Safe to re-run — all DDL is guarded with IF NOT EXISTS.
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
  2. Pass-through block — all DDL sent directly to SQL Server.
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
    2a. Create OCR_Weekly_Tracker (original columns only).
        CycleID and WeekSequence are added separately below
        so this block stays short and avoids the 262-char
        quoted-string limit inside EXECUTE.
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
          WeekLabel             VARCHAR(20)    NOT NULL,
          RunDate               DATE           NOT NULL,
          CycleID               VARCHAR(6)     NULL,       /* YYYYMM — e.g. 202603 */
          WeekSequence          INT            NULL,       /* 0=Baseline, 1,2,3...  */
          Baseline_Claims       INT,
          Open_Claims           INT,
          Current_OCR_Amt       DECIMAL(18,2),
          Cumul_Closed          INT,
          Closed_This_Week      INT,
          OCR_Reduced_This_Week DECIMAL(18,2),
          Pct_Claims_Closed     DECIMAL(10,6)
      )
    END
  ) by sqlsvr;

  /*------------------------------------------------------------
    2b. Add CycleID column if table already existed without it.
  ------------------------------------------------------------*/
  execute (
    IF NOT EXISTS (
      SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = 'Claims'
        AND TABLE_NAME   = 'OCR_Weekly_Tracker'
        AND COLUMN_NAME  = 'CycleID'
    )
    BEGIN
      ALTER TABLE FNB_STI_Analytics.Claims.OCR_Weekly_Tracker
        ADD CycleID VARCHAR(6) NULL
    END
  ) by sqlsvr;

  /*------------------------------------------------------------
    2c. Add WeekSequence column if table already existed without it.
  ------------------------------------------------------------*/
  execute (
    IF NOT EXISTS (
      SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = 'Claims'
        AND TABLE_NAME   = 'OCR_Weekly_Tracker'
        AND COLUMN_NAME  = 'WeekSequence'
    )
    BEGIN
      ALTER TABLE FNB_STI_Analytics.Claims.OCR_Weekly_Tracker
        ADD WeekSequence INT NULL
    END
  ) by sqlsvr;

  /*------------------------------------------------------------
    2d. Backfill CycleID and WeekSequence on any existing rows
        that predate this schema change. Derives CycleID from
        RunDate and WeekSequence from WeekLabel.
        Safe to re-run — WHERE CycleID IS NULL means it only
        touches rows not yet backfilled.
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
    2e. Create OCR_Run_Log audit table.
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
          RunDate          DATETIME2 DEFAULT GETDATE() NOT NULL,
          WeekNum          INT,            /* Week being processed            */
          CycleID          VARCHAR(6),     /* YYYYMM — matches tracker        */
          ProcessStep      VARCHAR(50)  NOT NULL, /* START/EXTRACT/INSERT/EMAIL/END */
          Status           VARCHAR(20)  NOT NULL, /* STARTED/SUCCESS/WARNING/FAILED */
          RecordsProcessed INT,            /* Row counts                      */
          MetricValue      DECIMAL(18,2),  /* OCR amount, claim counts        */
          ErrorMessage     VARCHAR(1000),  /* Error text if applicable        */
          AdditionalInfo   VARCHAR(500)    /* Free-text context               */
      )
    END
  ) by sqlsvr;

  disconnect from sqlsvr;
quit;

%put NOTE: Setup complete. OCR_Weekly_Tracker and OCR_Run_Log are ready in Claims schema.;
