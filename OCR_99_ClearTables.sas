/*==============================================================
  FILE: OCR_99_ClearTables.sas
  PURPOSE: Remove all rows for a specific CycleID so that
           OCR_00_Backfill.sas can be re-run cleanly for that
           cycle. Does NOT drop or recreate any tables.

  USAGE: Set &target_cycle. below and run.

  WARNING: This permanently deletes rows. Only run this if you
           are certain the cycle data needs to be replaced.
==============================================================*/

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
  Set the cycle you want to clear.
--------------------------------------------------------------*/
%let target_cycle = 202603;   /* <-- change this if needed */

/*--------------------------------------------------------------
  Preview what will be deleted before committing.
--------------------------------------------------------------*/
proc sql;
  title "OCR_Cycle_Control rows to be deleted for CycleID=&target_cycle.";
  select * from STI_WER.OCR_Cycle_Control
  where CycleID = "&target_cycle.";

  title "OCR_Weekly_Tracker rows to be deleted for CycleID=&target_cycle.";
  select * from STI_WER.OCR_Weekly_Tracker
  where CycleID = "&target_cycle.";

  title "OCR_Run_Log rows to be deleted for CycleID=&target_cycle.";
  select * from STI_WER.OCR_Run_Log
  where CycleID = "&target_cycle.";
  title;
quit;

/*--------------------------------------------------------------
  Delete. OCR_Weekly_Tracker first (FK child), then
  OCR_Cycle_Control (FK parent), then the log rows.
--------------------------------------------------------------*/
proc sql noprint;
  delete from STI_WER.OCR_Weekly_Tracker
  where CycleID = "&target_cycle.";
  %let tracker_deleted = &sqlobs.;

  delete from STI_WER.OCR_Cycle_Control
  where CycleID = "&target_cycle.";
  %let control_deleted = &sqlobs.;

  delete from STI_WER.OCR_Run_Log
  where CycleID = "&target_cycle.";
  %let log_deleted = &sqlobs.;
quit;

%put NOTE: OCR_Weekly_Tracker  -- &tracker_deleted. row(s) deleted for CycleID=&target_cycle..;
%put NOTE: OCR_Cycle_Control   -- &control_deleted. row(s) deleted for CycleID=&target_cycle..;
%put NOTE: OCR_Run_Log         -- &log_deleted. row(s) deleted for CycleID=&target_cycle..;
%put NOTE: Tables cleared. OCR_00_Backfill.sas can now be re-run for CycleID=&target_cycle..;
