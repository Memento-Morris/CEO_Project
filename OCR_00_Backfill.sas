1                                                          The SAS System                             20:33 Saturday, April 11, 2026

NOTE: Writing HTML5(EGHTML) Body file: EGHTML
f8884560
dna-r3saspwrk05
NOTE: Libref WH_MINT was successfully assigned as follows: /*==============================================================
  FILE: OCR_00_Backfill.sas
  PURPOSE: Insert historical cycle data that predates the
           automated baseline/weekly jobs, or re-insert a
           cycle that was missed.

  USAGE: Supply the cycle data in the %ocr_backfill() macro
         call at the bottom of the file. The macro validates,
         opens the cycle in OCR_Cycle_Control, and inserts all
         rows into OCR_Weekly_Tracker.

  DESIGN PRINCIPLES:
    - No hardcoding at the file level. All values are passed as
      macro parameters at the point of call.
    - Only actual input values (dates, claims, OCR amounts) are
      required. All derived metrics are computed automatically.
    - The control table (OCR_Cycle_Control) is always updated so
      the cycle record is consistent with live cycles.
    - Aborts if the CycleID already exists in OCR_Cycle_Control
      to prevent overwriting live data.
    - Does not delete any existing data. The UNIQUE constraint on
      (CycleID, WeekSequence) provides the database-level guard.

  CHANGES:
    Bug 2 fixed -- division by zero guard added to all pct_closed
                   calculations.
    Bug 3 fixed -- date informat changed from yymmdd8. to
                   yymmddN8. to correctly parse packed YYYYMMDD
                   strings without delimiters.
    Bug 5 fixed -- paired validation added: if weekN_open is
                   supplied without weekN_date the macro now
                   aborts with a clear message instead of
                   silently using an uninitialised date variable.
    Bug 7 fixed -- nested block comment in example call replaced
                   with a line-style comment. A nested /* inside
                   a /* block terminates the outer comment early
                   in SAS, exposing the closing ); as live code
                   and causing ERROR 180-322. Also added explicit
                   validation that inputn() produced a non-missing
                   SAS date before any INSERT is attempted, so a
                   bad date string aborts with a clear message
                   rather than a NULL constraint violation from
                   SQL Server.

  EXAMPLE CALL (add weeks as needed up to the last run):
    %ocr_backfill(
      cycle_id         = 202603,

      baseline_date    = 20260316,
      baseline_claims  = 678,
      baseline_ocr     = 3388533,

      week1_date       = 20260323,
      week1_open       = 397,
      week1_ocr        = 2013784,

      week2_date       = 20260330,
      week2_open       = 249,
      week2_ocr        = 1590398,

      week3_date       = 20260406,
      week3_open       = 197,
      week3_ocr        = 1256864,

      *-- cycle_status: CLOSED if cycle is done, ACTIVE if still running
      cycle_status     = CLOSED
    );
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

/*==============================================================
  2. Backfill macro definition.

  Required parameters (always):
    cycle_id        YYYYMM  e.g. 202603
    baseline_date   YYYYMMDD
    baseline_claims Integer claim count
    baseline_ocr    Numeric OCR amount

  Optional weekly parameters (pass as many weeks as ran):
    week1_date / week1_open / week1_ocr
    week2_date / week2_open / week2_ocr
    week3_date / week3_open / week3_ocr
    week4_date / week4_open / week4_ocr
    week5_date / week5_open / week5_ocr

  Optional control parameter:
    cycle_status    ACTIVE (default) or CLOSED
==============================================================*/
%macro ocr_backfill(
  cycle_id         =,
  baseline_date    =,
  baseline_claims  =,
  baseline_ocr     =,
  week1_date=, week1_open=, week1_ocr=,
  week2_date=, week2_open=, week2_ocr=,
  week3_date=, week3_open=, week3_ocr=,
  week4_date=, week4_open=, week4_ocr=,
  week5_date=, week5_open=, week5_ocr=,
  cycle_status     = ACTIVE
);

  /*------------------------------------------------------------
    2a. Validate required parameters.
  ------------------------------------------------------------*/
  %if %length(&cycle_id.)        = 0 or
      %length(&baseline_date.)   = 0 or
      %length(&baseline_claims.) = 0 or
      %length(&baseline_ocr.)    = 0 %then %do;
    %put ERROR: cycle_id, baseline_date, baseline_claims, baseline_ocr are all required.;
    %abort cancel;
  %end;

  /*------------------------------------------------------------
    Bug 5 fix: validate that date is always supplied alongside
    open/ocr for each week. Silently missing dates previously
    caused an uninitialised &sas_dN. variable to be inserted.
  ------------------------------------------------------------*/
  %macro _check_week_params(n);
    %if %length(&&week&n._open.) > 0 and %length(&&week&n._date.) = 0 %then %do;
      %put ERROR: week&n._open supplied but week&n._date is missing. All three week&n. parameters (date, open, ocr) are required together.;
      %abort cancel;
    %end;
    %if %length(&&week&n._open.) = 0 and %length(&&week&n._date.) > 0 %then %do;
      %put ERROR: week&n._date supplied but week&n._open is missing. All three week&n. parameters (date, open, ocr) are required together.;
      %abort cancel;
    %end;
    %if %length(&&week&n._open.) > 0 and %length(&&week&n._ocr.) = 0 %then %do;
      %put ERROR: week&n._open supplied but week&n._ocr is missing. All three week&n. parameters (date, open, ocr) are required together.;
      %abort cancel;
    %end;
  %mend _check_week_params;

  %_check_week_params(1);
  %_check_week_params(2);
  %_check_week_params(3);
  %_check_week_params(4);
  %_check_week_params(5);

  /*------------------------------------------------------------
    2b. Safety check -- abort if this cycle already exists in
        OCR_Cycle_Control (protects live data from accidental
        overwrite).
  ------------------------------------------------------------*/
  proc sql noprint;
    select count(*)
    into :cycle_exists trimmed
    from STI_WER.OCR_Cycle_Control
    where CycleID = "&cycle_id.";
  quit;

  %if &cycle_exists. > 0 %then %do;
    %put ERROR: CycleID=&cycle_id. already exists in OCR_Cycle_Control.;
    %put ERROR: Backfill aborted. If this cycle needs to be corrected, adjust;
    %put ERROR: the existing rows directly rather than re-running the backfill.;
    %put ERROR: Use OCR_99_ClearTables.sas to remove the existing rows first.;
    %abort cancel;
  %end;

  %put NOTE: No existing record for CycleID=&cycle_id.. Proceeding.;

  /*------------------------------------------------------------
    Bug 3 + Bug 7 + Bug 8 fix: convert all YYYYMMDD strings to
    SAS date integers inside a DATA step rather than with
    %sysfunc(inputn()). inputn() in macro context fails when the
    parameter value carries a leading space (e.g. from writing
    "week1_date = 20260316" with a space after the equals sign),
    because the space is part of the resolved macro value and
    yymmddN8. then sees " 2026..." instead of "20260316",
    returning missing (.). A DATA step INPUT statement strips
    leading spaces automatically and is not affected by macro
    resolution timing. Each converted value is written back into
    a macro variable for use in the INSERT statements below.
    An explicit missing-value check after the DATA step provides
    a clear abort message if any date string is genuinely bad.
  ------------------------------------------------------------*/
  data _null_;
    /* baseline is always required */
    d0 = input(strip("&baseline_date."), yymmddN8.);
    call symputx('sas_d0', d0, 'L');

    /* optional weekly dates -- only convert if supplied */
    %if %length(&week1_date.) > 0 %then %do;
      d1 = input(strip("&week1_date."), yymmddN8.);
      call symputx('sas_d1', d1, 'L');
    %end;
    %if %length(&week2_date.) > 0 %then %do;
      d2 = input(strip("&week2_date."), yymmddN8.);
      call symputx('sas_d2', d2, 'L');
    %end;
    %if %length(&week3_date.) > 0 %then %do;
      d3 = input(strip("&week3_date."), yymmddN8.);
      call symputx('sas_d3', d3, 'L');
    %end;
    %if %length(&week4_date.) > 0 %then %do;
      d4 = input(strip("&week4_date."), yymmddN8.);
      call symputx('sas_d4', d4, 'L');
    %end;
    %if %length(&week5_date.) > 0 %then %do;
      d5 = input(strip("&week5_date."), yymmddN8.);
      call symputx('sas_d5', d5, 'L');
    %end;
  run;

  /* Validate baseline date converted successfully */
  %if &sas_d0. = . %then %do;
    %put ERROR: baseline_date=&baseline_date. could not be parsed as YYYYMMDD.;
    %put ERROR: Supply an 8-digit packed date string with no separators, e.g. 20260316.;
    %abort cancel;
  %end;

  %put NOTE: baseline_date &baseline_date. -> SAS date &sas_d0. (%sysfunc(putn(&sas_d0., date9.))).;

  /* Validate each supplied weekly date */
  %if %length(&week1_date.) > 0 and &sas_d1. = . %then %do;
    %put ERROR: week1_date=&week1_date. could not be parsed as YYYYMMDD.;
    %abort cancel;
  %end;
  %if %length(&week2_date.) > 0 and &sas_d2. = . %then %do;
    %put ERROR: week2_date=&week2_date. could not be parsed as YYYYMMDD.;
    %abort cancel;
  %end;
  %if %length(&week3_date.) > 0 and &sas_d3. = . %then %do;
    %put ERROR: week3_date=&week3_date. could not be parsed as YYYYMMDD.;
    %abort cancel;
  %end;
  %if %length(&week4_date.) > 0 and &sas_d4. = . %then %do;
    %put ERROR: week4_date=&week4_date. could not be parsed as YYYYMMDD.;
    %abort cancel;
  %end;
  %if %length(&week5_date.) > 0 and &sas_d5. = . %then %do;
    %put ERROR: week5_date=&week5_date. could not be parsed as YYYYMMDD.;
    %abort cancel;
  %end;

  /*------------------------------------------------------------
    Bug 2 fix: division by zero guard added to all pct_closed
    calculations. If baseline_claims = 0, pct_closed = 0.
  ------------------------------------------------------------*/

  /* Week 1 vs Baseline */
  %if %length(&week1_open.) > 0 %then %do;
    %let w1_cumul_closed     = %sysevalf(&baseline_claims. - &week1_open.);
    %let w1_closed_this_week = %sysevalf(&baseline_claims. - &week1_open.);
    %let w1_ocr_reduced      = %sysevalf(&baseline_ocr.    - &week1_ocr.);
    %if &baseline_claims. > 0 %then
      %let w1_pct_closed = %sysevalf(&w1_cumul_closed. / &baseline_claims.);
    %else
      %let w1_pct_closed = 0;
  %end;

  /* Week 2 vs Week 1 */
  %if %length(&week2_open.) > 0 %then %do;
    %let w2_cumul_closed     = %sysevalf(&baseline_claims. - &week2_open.);
    %let w2_closed_this_week = %sysevalf(&week1_open.      - &week2_open.);
    %let w2_ocr_reduced      = %sysevalf(&week1_ocr.       - &week2_ocr.);
    %if &baseline_claims. > 0 %then
      %let w2_pct_closed = %sysevalf(&w2_cumul_closed. / &baseline_claims.);
    %else
      %let w2_pct_closed = 0;
  %end;

  /* Week 3 vs Week 2 */
  %if %length(&week3_open.) > 0 %then %do;
    %let w3_cumul_closed     = %sysevalf(&baseline_claims. - &week3_open.);
    %let w3_closed_this_week = %sysevalf(&week2_open.      - &week3_open.);
    %let w3_ocr_reduced      = %sysevalf(&week2_ocr.       - &week3_ocr.);
    %if &baseline_claims. > 0 %then
      %let w3_pct_closed = %sysevalf(&w3_cumul_closed. / &baseline_claims.);
    %else
      %let w3_pct_closed = 0;
  %end;

  /* Week 4 vs Week 3 */
  %if %length(&week4_open.) > 0 %then %do;
    %let w4_cumul_closed     = %sysevalf(&baseline_claims. - &week4_open.);
    %let w4_closed_this_week = %sysevalf(&week3_open.      - &week4_open.);
    %let w4_ocr_reduced      = %sysevalf(&week3_ocr.       - &week4_ocr.);
    %if &baseline_claims. > 0 %then
      %let w4_pct_closed = %sysevalf(&w4_cumul_closed. / &baseline_claims.);
    %else
      %let w4_pct_closed = 0;
  %end;

  /* Week 5 vs Week 4 */
  %if %length(&week5_open.) > 0 %then %do;
    %let w5_cumul_closed     = %sysevalf(&baseline_claims. - &week5_open.);
    %let w5_closed_this_week = %sysevalf(&week4_open.      - &week5_open.);
    %let w5_ocr_reduced      = %sysevalf(&week4_ocr.       - &week5_ocr.);
    %if &baseline_claims. > 0 %then
      %let w5_pct_closed = %sysevalf(&w5_cumul_closed. / &baseline_claims.);
    %else
      %let w5_pct_closed = 0;
  %end;

  /*------------------------------------------------------------
    2e. Open cycle in OCR_Cycle_Control.
  ------------------------------------------------------------*/
  proc sql noprint;
    insert into STI_WER.OCR_Cycle_Control
      (CycleID, BaselineDate, BaselineClaims, BaselineOCR, Status)
    values (
      "&cycle_id.",
      &sas_d0.,
      &baseline_claims.,
      &baseline_ocr.,
      "&cycle_status."
    );
  quit;

  %if &sqlrc. ne 0 %then %do;
    %put ERROR: INSERT into OCR_Cycle_Control failed. SQLRC=&sqlrc..;
    %abort cancel;
  %end;

  %put NOTE: CycleID=&cycle_id. registered in OCR_Cycle_Control (Status=&cycle_status.).;

  /*------------------------------------------------------------
    2f. Insert Baseline row (WeekSequence=0).
  ------------------------------------------------------------*/
  proc sql noprint;
    insert into STI_WER.OCR_Weekly_Tracker
      (CycleID, WeekSequence, WeekLabel, RunDate,
       Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    values (
      "&cycle_id.", 0, 'Baseline', &sas_d0.,
      &baseline_claims., &baseline_claims.,
      &baseline_ocr., 0, 0, 0, 0.0
    );
  quit;

  %put NOTE: Baseline row inserted (WeekSequence=0) for CycleID=&cycle_id..;

  /*------------------------------------------------------------
    2g. Insert weekly rows for each week supplied.
        Each block is conditional on whether that week's
        parameters were passed in.
  ------------------------------------------------------------*/

  %if %length(&week1_open.) > 0 %then %do;
    proc sql noprint;
      insert into STI_WER.OCR_Weekly_Tracker
        (CycleID, WeekSequence, WeekLabel, RunDate,
         Baseline_Claims, Open_Claims,
         Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
         OCR_Reduced_This_Week, Pct_Claims_Closed)
      values (
        "&cycle_id.", 1, 'Week 1', &sas_d1.,
        &baseline_claims., &week1_open., &week1_ocr.,
        &w1_cumul_closed., &w1_closed_this_week.,
        &w1_ocr_reduced.,  &w1_pct_closed.
      );
    quit;
    %put NOTE: Week 1 row inserted for CycleID=&cycle_id..;
  %end;

  %if %length(&week2_open.) > 0 %then %do;
    proc sql noprint;
      insert into STI_WER.OCR_Weekly_Tracker
        (CycleID, WeekSequence, WeekLabel, RunDate,
         Baseline_Claims, Open_Claims,
         Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
         OCR_Reduced_This_Week, Pct_Claims_Closed)
      values (
        "&cycle_id.", 2, 'Week 2', &sas_d2.,
        &baseline_claims., &week2_open., &week2_ocr.,
        &w2_cumul_closed., &w2_closed_this_week.,
        &w2_ocr_reduced.,  &w2_pct_closed.
      );
    quit;
    %put NOTE: Week 2 row inserted for CycleID=&cycle_id..;
  %end;

  %if %length(&week3_open.) > 0 %then %do;
    proc sql noprint;
      insert into STI_WER.OCR_Weekly_Tracker
        (CycleID, WeekSequence, WeekLabel, RunDate,
         Baseline_Claims, Open_Claims,
         Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
         OCR_Reduced_This_Week, Pct_Claims_Closed)
      values (
        "&cycle_id.", 3, 'Week 3', &sas_d3.,
        &baseline_claims., &week3_open., &week3_ocr.,
        &w3_cumul_closed., &w3_closed_this_week.,
        &w3_ocr_reduced.,  &w3_pct_closed.
      );
    quit;
    %put NOTE: Week 3 row inserted for CycleID=&cycle_id..;
  %end;

  %if %length(&week4_open.) > 0 %then %do;
    proc sql noprint;
      insert into STI_WER.OCR_Weekly_Tracker
        (CycleID, WeekSequence, WeekLabel, RunDate,
         Baseline_Claims, Open_Claims,
         Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
         OCR_Reduced_This_Week, Pct_Claims_Closed)
      values (
        "&cycle_id.", 4, 'Week 4', &sas_d4.,
        &baseline_claims., &week4_open., &week4_ocr.,
        &w4_cumul_closed., &w4_closed_this_week.,
        &w4_ocr_reduced.,  &w4_pct_closed.
      );
    quit;
    %put NOTE: Week 4 row inserted for CycleID=&cycle_id..;
  %end;

  %if %length(&week5_open.) > 0 %then %do;
    proc sql noprint;
      insert into STI_WER.OCR_Weekly_Tracker
        (CycleID, WeekSequence, WeekLabel, RunDate,
         Baseline_Claims, Open_Claims,
         Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
         OCR_Reduced_This_Week, Pct_Claims_Closed)
      values (
        "&cycle_id.", 5, 'Week 5', &sas_d5.,
        &baseline_claims., &week5_open., &week5_ocr.,
        &w5_cumul_closed., &w5_closed_this_week.,
        &w5_ocr_reduced.,  &w5_pct_closed.
      );
    quit;
    %put NOTE: Week 5 row inserted for CycleID=&cycle_id..;
  %end;

  /*------------------------------------------------------------
    2h. Verification -- print what was inserted for this cycle.
  ------------------------------------------------------------*/
  proc sql;
    title "OCR_Weekly_Tracker - CycleID &cycle_id. Backfill Verification";
    select WeekSequence,
           WeekLabel,
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

  %put NOTE: Backfill complete for CycleID=&cycle_id..;

%mend ocr_backfill;

/*==============================================================
  3. CALL THE MACRO HERE.
     Fill in the actual values for the cycle being backfilled.
     Remove week parameters you do not have yet.
==============================================================*/
%ocr_backfill(
  cycle_id         = 202603,

  baseline_date    = 20260316,
  baseline_claims  = 678,
  baseline_ocr     = 3388533,

  week1_date       = 20260323,
  week1_open       = 397,
  week1_ocr        = 2013784,

  week2_date       = 20260330,
  week2_open       = 249,
  week2_ocr        = 1590398,

  week3_date       = 20260406,
  week3_open       = 197,
  week3_ocr        = 1256864,

  cycle_status     = CLOSED
);

      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw MINT
NOTE: Libref WH_CRL was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/CL/InForce_Stacks/Daily/Product
NOTE: Libref WH_COM was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/02 Common
NOTE: Libref WH_ENH was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/03 Enhanced
NOTE: Libref WH_REP refers to the same physical library as W_REPORT.
NOTE: Libref WH_REP was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/04 Reporting Summaries
NOTE: Libref WH_SS refers to the same physical library as W_IDIT.
NOTE: Libref WH_SS was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/IDIT
NOTE: Libref WH_FLOW was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/03 Enhanced/MINT/FLOW
NOTE: Libref WH_PRFT was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance/Profitability/Saved Results/Overall
NOTE: Libref WH_DO was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance/Debit Order & Customer Analysis/Saved Extracts
NOTE: Libref WH_TEST was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/05 Testing
NOTE: Libref WH_IIPRD was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/06 Production Datasets
NOTE: Libref WH_COVID was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/07 Covid Data
NOTE: Libref WH_KPI was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/03 Enhanced/KPIs
NOTE: Libref WH_F_ADV was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/02 Advisory
NOTE: Libref WH_ADHOC was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/08 Adhoc
NOTE: Libref WH_IFRS was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/10 IFRS17
NOTE: Libref W_POL was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Atlas/01 Policy
NOTE: Libref W_ROLE was successfully assigned as follows: 
      Engine:        V9 
2                                                          The SAS System                             20:33 Saturday, April 11, 2026

      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Atlas/02 Role
NOTE: Libref W_COVER was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Atlas/03 Cover
NOTE: Libref W_PERS was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Atlas/04 Personal
NOTE: Libref W_CONT was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Atlas/05 Contact
NOTE: Libref W_COL was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Atlas/06 Collections
NOTE: Libref W_CLM was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Atlas/07 Claims
NOTE: Libref W_PRD was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Atlas/08 Product
NOTE: Libref W_LOOKUP was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Atlas/09 Lookups
NOTE: Libref W_TRANS was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/02 Common/99 Transactional
NOTE: Libref W_RAWUVW was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw UserVW
NOTE: Libref W_RAWUVL was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw UserVW/LOGS
NOTE: Libref W_RUNMET was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/00 Metadata
NOTE: Libref W_R_METD refers to the same physical library as W_RUNMD1.
NOTE: Libref W_R_METD was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Atlas/Run Meta/Daily Logs
NOTE: Libref W_REP_L was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/04 Reporting Summaries/Lookups
NOTE: Libref W_REP_R was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/04 Reporting Summaries/Raw
NOTE: Libref W_REP_M was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/04 Reporting Summaries/Logs
NOTE: Libref W_ENHRAW was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/03 Enhanced/Underlying Data
NOTE: Libref W_WORKF was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Workflow
NOTE: Libref W_WF_CLM was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Workflow/Claims
NOTE: Libref W_REPORT refers to the same physical library as WH_REP.
NOTE: Libref W_REPORT was successfully assigned as follows: 
3                                                          The SAS System                             20:33 Saturday, April 11, 2026

      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/04 Reporting Summaries
NOTE: Libref W_RUNMD1 refers to the same physical library as W_R_METD.
NOTE: Libref W_RUNMD1 was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Atlas/Run Meta/Daily Logs
NOTE: Libref W_RUNMD2 was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw ALIS/Run Meta/Daily Logs
NOTE: Libref W_RUNMD3 was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw MINT/Daily Logs
NOTE: Libref W_RUNMD4 was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw DWS-Sybase/Daily Logs
NOTE: Libref W_RUNMD4 was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw DWS-Sybase/Daily Logs
NOTE: Libref W_RAW_CL was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Credit Life Product table
NOTE: Libref W_RAW_CL was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Credit Life Product table
NOTE: Libref W_RAW_ST was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/01 Raw Data/99 Raw Short Term Product table
NOTE: Libref W_ALIS was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/CL/InForce_Stacks/Daily/Common Tables
NOTE: Libref W_IDIT refers to the same physical library as WH_SS.
NOTE: Libref W_IDIT was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/IDIT
NOTE: Libref W_MTV was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/MTV
NOTE: Libref W_IDIT_T was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/IDIT_TEST
NOTE: Libref W_FICA was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance/Business Intelligence/AD_HOC/New folder
NOTE: Libref W_NAM refers to the same physical library as WH_SS_NM.
NOTE: Libref W_NAM was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/IDIT_NAMIBIA
NOTE: Libref WH_SS_NM refers to the same physical library as W_NAM.
NOTE: Libref WH_SS_NM was successfully assigned as follows: 
      Engine:        V9 
      Physical Name: /data/fnbinsurance_warehouse/data/life/IDIT_NAMIBIA


{SAS002}79F38A012BDD8D4E0CD8F41A49DBCA3B01717D80056353D2

NOTE: PROCEDURE PWENCODE used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
4                                                          The SAS System                             20:33 Saturday, April 11, 2026

      

NOTE: Libref STI_PBI was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_LOC was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_OPS was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_META was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_SC was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref AN_OPS was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_STAG was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_DBO was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_AN was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref CA was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_SL was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_COM was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_CA was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_FLOW was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref LIFE_OPS was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_BGA was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_LC was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_BEV was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_CAR was successfully assigned as follows: 
      Engine:        ODBC 
5                                                          The SAS System                             20:33 Saturday, April 11, 2026

      Physical Name: 
NOTE: Libref MVCLAIM was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref HSL_AIP was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref CON was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_RES was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: Libref STI_WER was successfully assigned as follows: 
      Engine:        ODBC 
      Physical Name: 
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.12 seconds
      cpu time            0.08 seconds
      

NOTE: No existing record for CycleID=202603. Proceeding.
ERROR: CLI execute error: [SAS][ODBC SQL Server Wire Protocol driver][Microsoft SQL Server]Cannot insert the value NULL into column 
       'BaselineDate', table 'FNB_STI_Analytics.Claims.OCR_Cycle_Control'; column does not allow nulls. INSERT fails. : [SAS][ODBC 
       SQL Server Wire Protocol driver][Microsoft SQL Server]The statement has been terminated.
NOTE: This insert failed while attempting to add data from VALUES clause 1 to the data set.
ERROR: ROLLBACK issued due to errors for data set STI_WER.OCR_Cycle_Control.DATA.
NOTE: PROC SQL set option NOEXEC and will continue to check the syntax of statements.
NOTE: The SAS System stopped processing this step because of errors.
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.18 seconds
      cpu time            0.12 seconds
      
ERROR: INSERT into OCR_Cycle_Control failed. SQLRC=24.
ERROR: Execution canceled by an %ABORT CANCEL statement.
