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
  2. Safety check — abort if March/April 2026 rows already exist
--------------------------------------------------------------*/
proc sql noprint;
  select count(*)
  into :existing_rows trimmed
  from STI_WER.OCR_Weekly_Tracker
  where RunDate between '16Mar2026'd and '06Apr2026'd;
quit;

%if &existing_rows. > 0 %then %do;
  %put ERROR: &existing_rows. row(s) already exist in OCR_Weekly_Tracker for the back-fill date range (16 Mar – 06 Apr 2026).;
  %put ERROR: Back-fill aborted. Delete existing rows first if you want to re-run.;
  %abort cancel;
%end;

%put NOTE: No existing rows found for the back-fill range. Proceeding.;

/*--------------------------------------------------------------
  3. Pre-resolve all values into simple macro variables
     so that no macro functions sit inside quoted SQL strings.
--------------------------------------------------------------*/

/* Numeric values as plain strings */
%let r_baseline_claims  = &bf_baseline_claims.;
%let r_baseline_ocr     = &bf_baseline_ocr.;
%let r_w1_open          = &bf_week1_open.;
%let r_w1_ocr           = &bf_week1_ocr.;
%let r_w1_cumcl         = &bf_week1_cumul_closed.;
%let r_w1_clwk          = &bf_week1_closed_this_week.;
%let r_w1_ocrred        = &bf_week1_ocr_reduced.;
%let r_w1_pct           = &bf_week1_pct_closed.;
%let r_w2_open          = &bf_week2_open.;
%let r_w2_ocr           = &bf_week2_ocr.;
%let r_w2_cumcl         = &bf_week2_cumul_closed.;
%let r_w2_clwk          = &bf_week2_closed_this_week.;
%let r_w2_ocrred        = &bf_week2_ocr_reduced.;
%let r_w2_pct           = &bf_week2_pct_closed.;
%let r_w3_open          = &bf_week3_open.;
%let r_w3_ocr           = &bf_week3_ocr.;
%let r_w3_cumcl         = &bf_week3_cumul_closed.;
%let r_w3_clwk          = &bf_week3_closed_this_week.;
%let r_w3_ocrred        = &bf_week3_ocr_reduced.;
%let r_w3_pct           = &bf_week3_pct_closed.;

/* Dates already YYYYMMDD — just alias for clarity */
%let r_d0 = &bf_baseline_date.;
%let r_d1 = &bf_week1_date.;
%let r_d2 = &bf_week2_date.;
%let r_d3 = &bf_week3_date.;

/*--------------------------------------------------------------
  4. Insert all four rows in one pass
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

  /* --- Baseline row --- */
  execute (
    INSERT INTO FNB_STI_Analytics.Claims.OCR_Weekly_Tracker
      (WeekLabel, RunDate, Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    VALUES (
      'Baseline',
      CONVERT(DATE, '&r_d0.', 112),
      &r_baseline_claims.,
      &r_baseline_claims.,
      &r_baseline_ocr.,
      0, 0, 0, 0.0
    )
  ) by sqlsvr;

  /* --- Week 1 row --- */
  execute (
    INSERT INTO FNB_STI_Analytics.Claims.OCR_Weekly_Tracker
      (WeekLabel, RunDate, Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    VALUES (
      'Week 1',
      CONVERT(DATE, '&r_d1.', 112),
      &r_baseline_claims.,
      &r_w1_open.,
      &r_w1_ocr.,
      &r_w1_cumcl.,
      &r_w1_clwk.,
      &r_w1_ocrred.,
      &r_w1_pct.
    )
  ) by sqlsvr;

  /* --- Week 2 row --- */
  execute (
    INSERT INTO FNB_STI_Analytics.Claims.OCR_Weekly_Tracker
      (WeekLabel, RunDate, Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    VALUES (
      'Week 2',
      CONVERT(DATE, '&r_d2.', 112),
      &r_baseline_claims.,
      &r_w2_open.,
      &r_w2_ocr.,
      &r_w2_cumcl.,
      &r_w2_clwk.,
      &r_w2_ocrred.,
      &r_w2_pct.
    )
  ) by sqlsvr;

  /* --- Week 3 row --- */
  execute (
    INSERT INTO FNB_STI_Analytics.Claims.OCR_Weekly_Tracker
      (WeekLabel, RunDate, Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    VALUES (
      'Week 3',
      CONVERT(DATE, '&r_d3.', 112),
      &r_baseline_claims.,
      &r_w3_open.,
      &r_w3_ocr.,
      &r_w3_cumcl.,
      &r_w3_clwk.,
      &r_w3_ocrred.,
      &r_w3_pct.
    )
  ) by sqlsvr;

  disconnect from sqlsvr;
quit;

%put NOTE: Back-fill complete. Baseline + Week 1 + Week 2 + Week 3 inserted (16 Mar – 06 Apr 2026).;

/*--------------------------------------------------------------
  4. Verification — print what was inserted
--------------------------------------------------------------*/
proc sql;
  title "OCR_Weekly_Tracker — March/April 2026 Back-fill Verification";
  select WeekLabel,
         RunDate        format=date9.,
         Baseline_Claims,
         Open_Claims,
         Current_OCR_Amt       format=comma18.2,
         Cumul_Closed,
         Closed_This_Week,
         OCR_Reduced_This_Week format=comma18.2,
         Pct_Claims_Closed     format=percent8.2
  from STI_WER.OCR_Weekly_Tracker
  where RunDate between '16Mar2026'd and '06Apr2026'd
  order by RunDate;
  title;
quit;
