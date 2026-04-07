/*==============================================================
  FILE: OCR_00_Backfill_FIXED.sas
  PURPOSE: One-time back-fill — inserts the Baseline + 3 weekly
           rows into OCR_Weekly_Tracker for the March 2026 cycle.
  RUN: Once only, manually, BEFORE the next OCR_03_Weekly.sas run.
  AFTER RUNNING: Verify with the check query at the bottom.

  UPDATED: Now populates CycleID (202603) and WeekSequence
           (0=Baseline, 1/2/3=weekly) on all inserted rows,
           consistent with the new OCR_03_Weekly.sas logic.
==============================================================*/

/*--------------------------------------------------------------
  !! FILL IN YOUR VALUES HERE BEFORE RUNNING !!
--------------------------------------------------------------*/

/* --- CYCLE --- */
%let cycle_id            = 202603;         /* YYYYMM — March 2026 cycle */

/* --- BASELINE (March 16, 2026) --- */
%let bf_baseline_date    = 20260316;       /* YYYYMMDD — do not change  */
%let bf_baseline_claims  = 678;
%let bf_baseline_ocr     = 3388533;

/* --- WEEK 1 --- */
%let bf_week1_date       = 20260323;       /* replace if actual run date differs */
%let bf_week1_open       = 397;
%let bf_week1_ocr        = 2013784;

/* --- WEEK 2 --- */
%let bf_week2_date       = 20260330;       /* replace if actual run date differs */
%let bf_week2_open       = 249;
%let bf_week2_ocr        = 1590398;

/* --- WEEK 3 --- */
%let bf_week3_date       = 20260406;       /* replace if actual run date differs */
%let bf_week3_open       = 197;
%let bf_week3_ocr        = 1256864;

/*--------------------------------------------------------------
  Derived metrics — calculated automatically, do not edit
--------------------------------------------------------------*/

/* Week 1 derived */
%let bf_week1_cumul_closed     = %sysevalf(&bf_baseline_claims. - &bf_week1_open.);
%let bf_week1_closed_this_week = %sysevalf(&bf_baseline_claims. - &bf_week1_open.);  /* vs baseline */
%let bf_week1_ocr_reduced      = %sysevalf(&bf_baseline_ocr.    - &bf_week1_ocr.);
%let bf_week1_pct_closed       = %sysevalf(&bf_week1_cumul_closed. / &bf_baseline_claims.);

/* Week 2 derived */
%let bf_week2_cumul_closed     = %sysevalf(&bf_baseline_claims. - &bf_week2_open.);
%let bf_week2_closed_this_week = %sysevalf(&bf_week1_open.      - &bf_week2_open.);
%let bf_week2_ocr_reduced      = %sysevalf(&bf_week1_ocr.       - &bf_week2_ocr.);
%let bf_week2_pct_closed       = %sysevalf(&bf_week2_cumul_closed. / &bf_baseline_claims.);

/* Week 3 derived */
%let bf_week3_cumul_closed     = %sysevalf(&bf_baseline_claims. - &bf_week3_open.);
%let bf_week3_closed_this_week = %sysevalf(&bf_week2_open.      - &bf_week3_open.);
%let bf_week3_ocr_reduced      = %sysevalf(&bf_week2_ocr.       - &bf_week3_ocr.);
%let bf_week3_pct_closed       = %sysevalf(&bf_week3_cumul_closed. / &bf_baseline_claims.);

/*--------------------------------------------------------------
  1. Libnames
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
  2. Wrap all logic in a macro so %abort cancel is valid.
     (%abort cancel is illegal in open code.)
--------------------------------------------------------------*/
%macro run_backfill;

  /*------------------------------------------------------------
    2a. Safety check — abort if rows already exist for this cycle
  ------------------------------------------------------------*/
  proc sql noprint;
    select count(*)
    into :existing_rows trimmed
    from STI_WER.OCR_Weekly_Tracker
    where CycleID = "&cycle_id.";
  quit;

  %if &existing_rows. > 0 %then %do;
    %put ERROR: &existing_rows. row(s) already exist for CycleID=&cycle_id..;
    %put ERROR: Back-fill aborted. Delete existing rows first if you want to re-run.;
    %abort cancel;
  %end;

  %put NOTE: No existing rows found for CycleID=&cycle_id.. Proceeding.;

  /*------------------------------------------------------------
    2b. Convert YYYYMMDD strings to SAS date integers.
        %sysfunc(inputn(..., yymmdd8.)) reads an 8-digit YYYYMMDD
        number and returns the SAS date integer for that date.
        The ODBC driver translates SAS date integers to SQL Server
        DATE values natively — no quoted date strings in the SQL,
        which avoids the 262-char quote-tracking bug.
  ------------------------------------------------------------*/
  %let sas_d0 = %sysfunc(inputn(&bf_baseline_date., yymmdd8.));
  %let sas_d1 = %sysfunc(inputn(&bf_week1_date.,    yymmdd8.));
  %let sas_d2 = %sysfunc(inputn(&bf_week2_date.,    yymmdd8.));
  %let sas_d3 = %sysfunc(inputn(&bf_week3_date.,    yymmdd8.));

  /*------------------------------------------------------------
    2c. Insert via STI_WER libref — no CONNECT/EXECUTE needed.
        All four rows include CycleID and WeekSequence so the
        new weekly logic can query by cycle rather than by month.
  ------------------------------------------------------------*/
  proc sql noprint;

    /* Baseline — WeekSequence = 0 */
    insert into STI_WER.OCR_Weekly_Tracker
      (WeekLabel, RunDate, CycleID, WeekSequence,
       Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    values (
      'Baseline',
      &sas_d0.,
      "&cycle_id.",
      0,
      &bf_baseline_claims.,
      &bf_baseline_claims.,
      &bf_baseline_ocr.,
      0, 0, 0, 0.0
    );

    /* Week 1 — WeekSequence = 1 */
    insert into STI_WER.OCR_Weekly_Tracker
      (WeekLabel, RunDate, CycleID, WeekSequence,
       Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    values (
      'Week 1',
      &sas_d1.,
      "&cycle_id.",
      1,
      &bf_baseline_claims.,
      &bf_week1_open.,
      &bf_week1_ocr.,
      &bf_week1_cumul_closed.,
      &bf_week1_closed_this_week.,
      &bf_week1_ocr_reduced.,
      &bf_week1_pct_closed.
    );

    /* Week 2 — WeekSequence = 2 */
    insert into STI_WER.OCR_Weekly_Tracker
      (WeekLabel, RunDate, CycleID, WeekSequence,
       Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    values (
      'Week 2',
      &sas_d2.,
      "&cycle_id.",
      2,
      &bf_baseline_claims.,
      &bf_week2_open.,
      &bf_week2_ocr.,
      &bf_week2_cumul_closed.,
      &bf_week2_closed_this_week.,
      &bf_week2_ocr_reduced.,
      &bf_week2_pct_closed.
    );

    /* Week 3 — WeekSequence = 3 */
    insert into STI_WER.OCR_Weekly_Tracker
      (WeekLabel, RunDate, CycleID, WeekSequence,
       Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    values (
      'Week 3',
      &sas_d3.,
      "&cycle_id.",
      3,
      &bf_baseline_claims.,
      &bf_week3_open.,
      &bf_week3_ocr.,
      &bf_week3_cumul_closed.,
      &bf_week3_closed_this_week.,
      &bf_week3_ocr_reduced.,
      &bf_week3_pct_closed.
    );

  quit;

  /*------------------------------------------------------------
    2d. Abort on insert failure.
        PROC SQL (libref INSERT) sets &sqlrc. on failure.
  ------------------------------------------------------------*/
  %if &sqlrc. ne 0 %then %do;
    %put ERROR: One or more INSERT statements failed. SQLRC=&sqlrc..;
    %abort cancel;
  %end;

  %put NOTE: Back-fill complete. Baseline + Week 1 + Week 2 + Week 3 inserted for CycleID=&cycle_id..;

  /*------------------------------------------------------------
    3. Verification — print what was inserted
  ------------------------------------------------------------*/
  proc sql;
    title "OCR_Weekly_Tracker - CycleID &cycle_id. Back-fill Verification";
    select WeekLabel,
           WeekSequence,
           RunDate                format=date9.,
           CycleID,
           Baseline_Claims,
           Open_Claims,
           Current_OCR_Amt        format=comma18.2,
           Cumul_Closed,
           Closed_This_Week,
           OCR_Reduced_This_Week  format=comma18.2,
           Pct_Claims_Closed      format=percent8.2
    from STI_WER.OCR_Weekly_Tracker
    where CycleID = "&cycle_id."
    order by WeekSequence;
    title;
  quit;

%mend run_backfill;

%run_backfill;
