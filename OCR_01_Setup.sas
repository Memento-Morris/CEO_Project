/*==============================================================
  FILE: OCR_01_Setup.sas
  PURPOSE: One-time setup — creates the OCR_Weekly_Tracker
           table in SQL Server if it does not already exist.
  RUN: Once, manually, before any other files are executed.
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
  2. Create tracker table (only runs if it doesn't exist)
     Uses pass-through SQL so SAS sends DDL directly to
     SQL Server without trying to interpret it itself.
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
          WeekLabel             VARCHAR(20)    NOT NULL,  /* 'Baseline', 'Week 1', ... */
          RunDate               DATE           NOT NULL,
          Baseline_Claims       INT,                      /* total flagged on the 16th */
          Open_Claims           INT,                      /* still open this week */
          Current_OCR_Amt       DECIMAL(18,2), /* SUM of Current_Estimate_OCR */
          Cumul_Closed          INT,                      /* baseline - open */
          Closed_This_Week      INT,                      /* prev_open - open */
          OCR_Reduced_This_Week DECIMAL(18,2), /* prev_OCR  - current_OCR */
          Pct_Claims_Closed     DECIMAL(10,6)             /* cumul_closed / baseline */
      )
    END
  ) by sqlsvr;

  disconnect from sqlsvr;
quit;

%put NOTE: Setup complete. OCR_Weekly_Tracker is ready in Claims schema.;
