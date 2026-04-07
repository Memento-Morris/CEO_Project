/*==============================================================
  FILE: OCR_00_Backfill.sas
  PURPOSE: One-time back-fill — inserts the Baseline + 3 weekly
           rows into OCR_Weekly_Tracker for the March 2026 cycle.
  RUN: Once only, manually, BEFORE the next OCR_03_Weekly.sas run.
  AFTER RUNNING: Verify with the check query at the bottom.
==============================================================*/

/*--------------------------------------------------------------
  !! FILL IN YOUR VALUES HERE BEFORE RUNNING !!
--------------------------------------------------------------*/

/* --- BASELINE (March 16, 2026) --- */
%let bf_baseline_date    = 20260316;    /* do not change — YYYYMMDD, no hyphens */
%let bf_baseline_claims  = 678;
%let bf_baseline_ocr     = 3388533;

/* --- WEEK 1 --- */
%let bf_week1_date       = 20260323;    /* replace if actual run date differs — YYYYMMDD */
%let bf_week1_open       = 397;
%let bf_week1_ocr        = 2013784;

/* --- WEEK 2 --- */
%let bf_week2_date       = 20260330;    /* replace if actual run date differs — YYYYMMDD */
%let bf_week2_open       = 249;
%let bf_week2_ocr        = 1590398;

/* --- WEEK 3 --- */
%let bf_week3_date       = 20260406;    /* replace if actual run date differs — YYYYMMDD */
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
     (%abort cancel is illegal in open code — this was the
      second bug in the previous version.)
--------------------------------------------------------------*/
%macro run_backfill;

  /*------------------------------------------------------------
    2a. Safety check — abort if rows already exist
  ------------------------------------------------------------*/
  proc sql noprint;
    select count(*)
    into :existing_rows trimmed
    from STI_WER.OCR_Weekly_Tracker
    where RunDate between '16Mar2026'd and '06Apr2026'd;
  quit;

  %if &existing_rows. > 0 %then %do;
    %put ERROR: &existing_rows. row(s) already exist for 16 Mar - 06 Apr 2026.;
    %put ERROR: Back-fill aborted. Delete existing rows first if you want to re-run.;
    %abort cancel;
  %end;

  %put NOTE: No existing rows found for the back-fill range. Proceeding.;

  /*------------------------------------------------------------
    2b. Convert YYYYMMDD strings to SAS date integers.

        FIX for the 262-char / date conversion error:
        The root cause was using EXECUTE...BY SQLSVR with
        CONVERT(DATE, '&var.', 112) inside a long EXECUTE block.
        The EXECUTE block's SQL is passed as one giant quoted
        string; when it exceeded 262 chars, SAS's quote-tracking
        broke, corrupting the date literal before SQL Server
        ever saw it.

        Solution: use PROC SQL INSERT INTO via the STI_WER libref
        instead of EXECUTE...BY. Date values are passed as SAS
        date integers (numeric), which the ODBC driver translates
        natively — no quoted date strings in the SQL at all.

        %sysfunc(inputn(..., yymmdd8.)) reads an 8-digit YYYYMMDD
        number and returns the SAS date integer for that date.
  ------------------------------------------------------------*/
  %let sas_d0 = %sysfunc(inputn(&bf_baseline_date., yymmdd8.));
  %let sas_d1 = %sysfunc(inputn(&bf_week1_date.,    yymmdd8.));
  %let sas_d2 = %sysfunc(inputn(&bf_week2_date.,    yymmdd8.));
  %let sas_d3 = %sysfunc(inputn(&bf_week3_date.,    yymmdd8.));

  /*------------------------------------------------------------
    2c. Insert via STI_WER libref — no CONNECT/EXECUTE needed.
        PROC SQL translates the SAS date integers to SQL Server
        DATE values through the ODBC driver automatically.
  ------------------------------------------------------------*/
  proc sql noprint;

    /* Baseline */
    insert into STI_WER.OCR_Weekly_Tracker
      (WeekLabel, RunDate, Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    values (
      'Baseline',
      &sas_d0.,
      &bf_baseline_claims.,
      &bf_baseline_claims.,
      &bf_baseline_ocr.,
      0, 0, 0, 0.0
    );

    /* Week 1 */
    insert into STI_WER.OCR_Weekly_Tracker
      (WeekLabel, RunDate, Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    values (
      'Week 1',
      &sas_d1.,
      &bf_baseline_claims.,
      &bf_week1_open.,
      &bf_week1_ocr.,
      &bf_week1_cumul_closed.,
      &bf_week1_closed_this_week.,
      &bf_week1_ocr_reduced.,
      &bf_week1_pct_closed.
    );

    /* Week 2 */
    insert into STI_WER.OCR_Weekly_Tracker
      (WeekLabel, RunDate, Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    values (
      'Week 2',
      &sas_d2.,
      &bf_baseline_claims.,
      &bf_week2_open.,
      &bf_week2_ocr.,
      &bf_week2_cumul_closed.,
      &bf_week2_closed_this_week.,
      &bf_week2_ocr_reduced.,
      &bf_week2_pct_closed.
    );

    /* Week 3 */
    insert into STI_WER.OCR_Weekly_Tracker
      (WeekLabel, RunDate, Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    values (
      'Week 3',
      &sas_d3.,
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
    2d. PROC SQL (libref INSERT) sets &sqlrc. on failure.
        Note: EXECUTE...BY sets &sqlxrc. — different variable.
  ------------------------------------------------------------*/
  %if &sqlrc. ne 0 %then %do;
    %put ERROR: One or more INSERT statements failed. SQLRC=&sqlrc.;
    %abort cancel;
  %end;

  %put NOTE: Back-fill complete. Baseline + Week 1 + Week 2 + Week 3 inserted (16 Mar - 06 Apr 2026).;

  /*------------------------------------------------------------
    3. Verification — print what was inserted
  ------------------------------------------------------------*/
  proc sql;
    title "OCR_Weekly_Tracker - March/April 2026 Back-fill Verification";
    select WeekLabel,
           RunDate                format=date9.,
           Baseline_Claims,
           Open_Claims,
           Current_OCR_Amt        format=comma18.2,
           Cumul_Closed,
           Closed_This_Week,
           OCR_Reduced_This_Week  format=comma18.2,
           Pct_Claims_Closed      format=percent8.2
    from STI_WER.OCR_Weekly_Tracker
    where RunDate between '16Mar2026'd and '06Apr2026'd
    order by RunDate;
    title;
  quit;

%mend run_backfill;

%run_backfill;
