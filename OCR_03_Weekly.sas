/*==============================================================
  FILE: OCR_03_Weekly.sas
  PURPOSE: Runs every week (every Monday, or agreed day).
           1. Reads the ACTIVE cycle from OCR_Cycle_Control.
           2. Pulls current claim state.
           3. Computes weekly movement vs the previous week.
           4. Appends a new row to OCR_Weekly_Tracker.
           5. Exports the detail claims list to Excel.
           6. Sends email.

  CHANGES:
    Bug 1 fixed        — %let week_num moved outside PROC SQL.
    Bug 2 fixed        — division by zero guard on pct_closed.
    Bug 3 fixed        — yymmddN8. informat for packed dates.
    Bug 4 fixed        — abort if prev week values not found.
    Feature 3          — max-weeks guard (abort if > 5).
    Feature 5          — cycle/run-date mismatch warning.
    Fix (abort)        — job wrapped in %ocr_weekly_main so
                         %abort cancel works correctly.
    Fix (scoping)      — all key macro variables declared
                         %global BEFORE the master macro so
                         PROC SQL SELECT INTO writes to the
                         global symbol table. Nested macro
                         %resolve_cycle removed and inlined —
                         SELECT INTO inside a nested macro does
                         not propagate results to the calling
                         macro's symbol table.
    Fix (%if strings)  — string comparisons use %str(),
                         boolean numeric check uses %sysevalf.
==============================================================*/

/*--------------------------------------------------------------
  1. Libname + logging. Must stay in open code so the libref
     and %ocr_log macro exist before the main macro runs.
--------------------------------------------------------------*/
%include "/data/fnbins/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Automation/STI_CA_2/Libnames.sas";
%include "/data/fnbins/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Automation/STI_CA_2/OCR_00_Logging.sas";

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
  2. Run date — set in open code before the main macro.
     Override with rd= for back-testing.
--------------------------------------------------------------*/
%if not %symexist(rd) %then %do;
  %let rd = %sysfunc(today(), yymmddn8.);
%end;

/*--------------------------------------------------------------
  Global declarations — declared here in open code so that
  PROC SQL SELECT INTO statements inside %ocr_weekly_main
  write directly to the global symbol table and are visible
  everywhere. Without this, SAS creates local macro variables
  inside the macro that vanish when it returns.
--------------------------------------------------------------*/
%global cycle_id baseline_claims baseline_ocr
        baseline_ocr_fmt baseline_claims_fmt
        prev_open prev_ocr_amt
        week_num existing_rows seq_exists
        open_this_week ocr_this_week
        cumul_closed closed_this_week ocr_reduced pct_closed
        cycle_mismatch_flag rd_yyyymm sas_rd outfile
        email_open_fmt email_baseline_fmt email_ocr_fmt
        email_reduced_fmt email_closed_fmt email_cumul_fmt email_pct_fmt;

/*==============================================================
  MASTER MACRO — wraps entire job so %abort cancel works.
==============================================================*/
%macro ocr_weekly_main;

%ocr_log(JOB_START, STARTED, info=Weekly OCR job initiated rd=&rd.);

/*--------------------------------------------------------------
  3. Resolve active cycle from OCR_Cycle_Control.
     NOTE: Do NOT move this into a nested macro. Variables set
     by PROC SQL SELECT INTO inside a nested macro are local to
     that macro and disappear when it exits — even if declared
     %global. Inlining here is the correct pattern.
--------------------------------------------------------------*/
proc sql noprint;
  select CycleID,
         BaselineClaims,
         BaselineOCR
  into :cycle_id       trimmed,
       :baseline_claims trimmed,
       :baseline_ocr    trimmed
  from STI_WER.OCR_Cycle_Control
  where Status = 'ACTIVE'
  order by BaselineDate desc;
quit;

%if &sqlobs. = 0 %then %do;
  %ocr_log(RESOLVE_CYCLE, FAILED,
           error=No ACTIVE cycle found in OCR_Cycle_Control);
  %put ERROR: No ACTIVE cycle found in OCR_Cycle_Control.;
  %put ERROR: Run OCR_02_Baseline.sas on the 16th first.;
  %abort cancel;
%end;

%put NOTE: Active Cycle ID     = &cycle_id.;
%put NOTE: Baseline Claims     = &baseline_claims.;
%put NOTE: Baseline OCR Amount = &baseline_ocr.;
%ocr_log(RESOLVE_CYCLE, SUCCESS,
         info=CycleID=&cycle_id. Claims=&baseline_claims.);

/* Pre-format baseline values for use in footnotes/titles.    */
/* This avoids %sysfunc(putn()) at compile time inside procs. */
%let baseline_ocr_fmt    = %sysfunc(putn(&baseline_ocr.,    comma18.2));
%let baseline_claims_fmt = %sysfunc(putn(&baseline_claims., comma10.));

/*--------------------------------------------------------------
  Feature 5: Cycle / run-date mismatch warning.
--------------------------------------------------------------*/
%let rd_yyyymm = %sysfunc(substr(&rd., 1, 6));

%if %str(&rd_yyyymm.) ne %str(&cycle_id.) %then %do;
  %put WARNING: Run date month (&rd_yyyymm.) ne active CycleID (&cycle_id.).;
  %put WARNING: If intentional (cycle still open after month-end) ignore this.;
  %put WARNING: If NOT intentional check OCR_02_Baseline.sas ran for &rd_yyyymm..;
  %ocr_log(CYCLE_DATE_MISMATCH, WARNING,
           info=RunDate &rd_yyyymm. ne CycleID &cycle_id.);
  %let cycle_mismatch_flag = Y;
%end;
%else %let cycle_mismatch_flag = N;

/*--------------------------------------------------------------
  4a. Count existing rows for this cycle (= next week number).
--------------------------------------------------------------*/
proc sql noprint;
  select count(*)
  into :existing_rows trimmed
  from STI_WER.OCR_Weekly_Tracker
  where CycleID = "&cycle_id.";
quit;

%let week_num = &existing_rows.;
%put NOTE: Week number (next to insert) = &week_num.;

/*--------------------------------------------------------------
  4b. Pull previous week values for delta calculations.
--------------------------------------------------------------*/
proc sql noprint;
  select Open_Claims,
         Current_OCR_Amt
  into :prev_open    trimmed,
       :prev_ocr_amt trimmed
  from STI_WER.OCR_Weekly_Tracker
  where CycleID = "&cycle_id."
    and RunDate = (
        select max(RunDate)
        from STI_WER.OCR_Weekly_Tracker
        where CycleID = "&cycle_id."
    );
quit;

%if &sqlobs. = 0 %then %do;
  %ocr_log(PREV_WEEK_RESOLVE, FAILED,
           error=Could not resolve previous week values for CycleID &cycle_id.);
  %put ERROR: Could not resolve Open_Claims / Current_OCR_Amt from previous week.;
  %put ERROR: CycleID=&cycle_id. — check OCR_Weekly_Tracker has at least the baseline row.;
  %abort cancel;
%end;

%put NOTE: Previous open claims = &prev_open.;
%put NOTE: Previous OCR amount  = &prev_ocr_amt.;

/*--------------------------------------------------------------
  4c. Duplicate-run guard.
--------------------------------------------------------------*/
proc sql noprint;
  select count(*)
  into :seq_exists trimmed
  from STI_WER.OCR_Weekly_Tracker
  where CycleID      = "&cycle_id."
    and WeekSequence = &week_num.;
quit;

%if &seq_exists. > 0 %then %do;
  %ocr_log(WEEK_RESOLVE, FAILED,
           error=WeekSequence &week_num. already exists for CycleID &cycle_id.);
  %put ERROR: Row for CycleID=&cycle_id. WeekSequence=&week_num. already exists.;
  %put ERROR: Job has already run for this week. Aborting to prevent duplicates.;
  %abort cancel;
%end;

/*--------------------------------------------------------------
  Feature 3: Max-weeks guard.
--------------------------------------------------------------*/
%if &week_num. > 5 %then %do;
  %ocr_log(MAX_WEEKS_EXCEEDED, FAILED,
           error=WeekSequence &week_num. exceeds max of 5 for CycleID &cycle_id.);
  %put ERROR: WeekSequence &week_num. exceeds maximum of 5 for CycleID=&cycle_id..;
  %put ERROR: Close this cycle first then run OCR_02_Baseline.sas for the new cycle.;
  %abort cancel;
%end;

%ocr_log(WEEK_RESOLVE, SUCCESS,
         records=&week_num.,
         info=CycleID=&cycle_id. PrevOpen=&prev_open.);

/*--------------------------------------------------------------
  5. Pull snapshot — Motor + Retail from Investigate_Claims.
--------------------------------------------------------------*/
data work.snapshot;
  set STI_WER.Investigate_Claims(
    keep= ClaimCode SubClaimCode ReportMonth
          Estimate_OCR ProductTypeSplit Division ClaimHandler
  );
  if upcase(strip(ProductTypeSplit)) ne 'MOTOR'  then delete;
  if upcase(strip(Division))         ne 'RETAIL' then delete;
run;

%ocr_log(EXTRACT_SNAPSHOT, SUCCESS, records=&sysnobs.);

/*--------------------------------------------------------------
  6. Pull current estimates from live view.
--------------------------------------------------------------*/
data work.current_est;
  set STI_WER.vw_OpsClaimsReport(
    keep= SubClaimCode Total_Estimate_OCR_ExVAT Total_Paid_ExVAT
  );
run;

%ocr_log(EXTRACT_ESTIMATES, SUCCESS, records=&sysnobs.);

/*--------------------------------------------------------------
  7. Build final claims detail (not paid off only).
--------------------------------------------------------------*/
proc sql;
  create table work.MotorClaims_Final as
  select
      c.ClaimCode,
      c.ReportMonth                                             as ReportedMonth,
      c.ClaimHandler,
      c.Estimate_OCR                                            as Estimate_OCR_When_Flagged,
      round(a.Total_Estimate_OCR_ExVAT, 0.01)                  as Current_Estimate_OCR,
      round(a.Total_Estimate_OCR_ExVAT, 0.01) - c.Estimate_OCR as OCR_Movement
  from work.snapshot c
  left join work.current_est a
      on c.SubClaimCode = a.SubClaimCode
  where coalesce(a.Total_Estimate_OCR_ExVAT, 0) > 0
  order by c.ReportMonth desc;
quit;

%ocr_log(BUILD_CLAIMS_DETAIL, SUCCESS, records=&sqlobs.);

/*--------------------------------------------------------------
  8. Compute this week's summary metrics.
--------------------------------------------------------------*/
proc sql noprint;
  select count(distinct ClaimCode),
         sum(Current_Estimate_OCR)
  into :open_this_week trimmed,
       :ocr_this_week  trimmed
  from work.MotorClaims_Final;
quit;

%put NOTE: Open this week = &open_this_week.;
%put NOTE: OCR this week  = &ocr_this_week.;

%let cumul_closed     = %sysevalf(&baseline_claims. - &open_this_week.);
%let closed_this_week = %sysevalf(&prev_open.       - &open_this_week.);
%let ocr_reduced      = %sysevalf(&prev_ocr_amt.    - &ocr_this_week.);

%if %sysevalf(&baseline_claims. > 0, boolean) %then
  %let pct_closed = %sysevalf(&cumul_closed. / &baseline_claims.);
%else
  %let pct_closed = 0;

%put NOTE: Cumul closed     = &cumul_closed.;
%put NOTE: Closed this week = &closed_this_week.;
%put NOTE: OCR reduced      = &ocr_reduced.;
%put NOTE: Pct closed       = &pct_closed.;

%ocr_log(CALC_METRICS, SUCCESS,
         records=&open_this_week.,
         metric=&ocr_this_week.);

/*--------------------------------------------------------------
  9. Insert weekly row into OCR_Weekly_Tracker.
     RunDate: &rd. is a YYYYMMDD string (e.g. 20260413).
     Rather than converting to a SAS date integer and relying
     on the ODBC driver to map it, we use a pass-through
     EXECUTE block so SQL Server converts the string itself
     via CONVERT(DATE, '&rd.', 112).  Format 112 = YYYYMMDD.
     This is the most reliable approach and removes all
     dependence on SAS date integer / ODBC driver mapping.
--------------------------------------------------------------*/
%put NOTE: rd=&rd. inserting as RunDate via SQL CONVERT(DATE,112).;

proc sql noprint;
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
    INSERT INTO FNB_STI_Analytics.Claims.OCR_Weekly_Tracker
      (CycleID, WeekSequence, WeekLabel, RunDate,
       Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    VALUES (
      "&cycle_id.",
      &week_num.,
      "Week &week_num.",
      CONVERT(DATE, "&rd.", 112),
      &baseline_claims.,
      &open_this_week.,
      &ocr_this_week.,
      &cumul_closed.,
      &closed_this_week.,
      &ocr_reduced.,
      &pct_closed.
    )
  ) by sqlsvr;

  disconnect from sqlsvr;
quit;

%if &syserr. ne 0 %then %do;
  %ocr_log(INSERT_TRACKER, FAILED,
           error=INSERT into OCR_Weekly_Tracker failed SYSERR=&syserr.);
  %put ERROR: INSERT into OCR_Weekly_Tracker failed. SYSERR=&syserr.. Aborting.;
  %abort cancel;
%end;

%ocr_log(INSERT_TRACKER, SUCCESS);
%put NOTE: Week &week_num. inserted into OCR_Weekly_Tracker (CycleID=&cycle_id.).;

/*--------------------------------------------------------------
  10. Pull full tracker for this cycle.
--------------------------------------------------------------*/
proc sql;
  create table work.tracker_this_cycle as
  select *
  from STI_WER.OCR_Weekly_Tracker
  where CycleID = "&cycle_id."
  order by WeekSequence;
quit;

/*--------------------------------------------------------------
  11. Pivot tracker wide (metrics as rows, weeks as columns).
--------------------------------------------------------------*/
proc transpose data=work.tracker_this_cycle
               out=work.tracker_wide(drop=_label_)
               prefix=Col_;
  id WeekLabel;
  var Open_Claims Current_OCR_Amt Cumul_Closed
      Closed_This_Week OCR_Reduced_This_Week Pct_Claims_Closed;
run;

data work.tracker_wide;
  set work.tracker_wide;
  rename _NAME_ = Metric;
run;

/*--------------------------------------------------------------
  12. Charts.
--------------------------------------------------------------*/
ods graphics on / width=800px height=400px imagename="ocr_trend"
               outputfmt=png
               imagepath="/data/fnbinsurance/Short_Term/Monitoring/";

proc sgplot data=work.tracker_this_cycle;
  series x=WeekLabel y=Current_OCR_Amt /
    markers
    markerattrs=(symbol=circlefilled size=10 color=darkblue)
    lineattrs=(thickness=2 color=darkblue);
  yaxis label="Current OCR Amount (R)" grid valuesformat=comma18.;
  xaxis label="Week" discreteorder=data;
  title "OCR Amount Movement -- Motor Retail (CycleID &cycle_id.)";
  footnote j=left
    "Baseline: R &baseline_ocr_fmt.  |  Claims: &baseline_claims_fmt.  |  Run: &rd.";
run;

ods graphics on / imagename="claims_closed";

proc sgplot data=work.tracker_this_cycle;
  vbar WeekLabel / response=Closed_This_Week
    fillattrs=(color=steelblue)
    datalabel
    datalabelattrs=(size=10 weight=bold);
  yaxis label="Claims Closed This Week" grid;
  xaxis label="Week" discreteorder=data;
  title "Claims Closed Per Week -- Motor Retail (CycleID &cycle_id.)";
run;

ods graphics off;
%ocr_log(CHARTS, SUCCESS);

/*--------------------------------------------------------------
  13. Export to Excel — 4 sheets.
--------------------------------------------------------------*/
%let outfile =
  /data/fnbinsurance/Short_Term/Monitoring/MotorOCR_Tracker_&rd..xlsx;

ods excel file="&outfile."
  options(
    sheet_name      = "Summary"
    embedded_titles = "yes"
    frozen_headers  = "yes"
    autofilter      = "yes"
    flow            = "tables"
  );

  title "OCR Weekly Tracker -- Motor Retail -- Week &week_num. (Cycle &cycle_id.)";
  proc print data=work.tracker_wide noobs label; run;

ods excel options(sheet_name="Claims Detail" autofilter="yes");
  title "Motor Retail Claims Under Investigation -- Week &week_num.";
  proc print data=work.MotorClaims_Final noobs label;
    format Estimate_OCR_When_Flagged
           Current_Estimate_OCR
           OCR_Movement           comma18.2;
  run;

ods excel options(sheet_name="OCR Trend Chart");
  proc sgplot data=work.tracker_this_cycle;
    series x=WeekLabel y=Current_OCR_Amt /
      markers
      markerattrs=(symbol=circlefilled size=10 color=darkblue)
      lineattrs=(thickness=2 color=darkblue);
    yaxis label="Current OCR Amount (R)" grid valuesformat=comma18.;
    xaxis label="Week" discreteorder=data;
    title "OCR Amount Movement -- Motor Retail";
  run;

ods excel options(sheet_name="Claims Closed Chart");
  proc sgplot data=work.tracker_this_cycle;
    vbar WeekLabel / response=Closed_This_Week
      fillattrs=(color=steelblue)
      datalabel
      datalabelattrs=(size=10 weight=bold);
    yaxis label="Claims Closed This Week" grid;
    xaxis label="Week" discreteorder=data;
    title "Claims Closed Per Week -- Motor Retail";
  run;

ods excel close;
title; footnote;

%put NOTE: Excel written to &outfile.;
%ocr_log(EXPORT_EXCEL, SUCCESS, info=&outfile.);

/*--------------------------------------------------------------
  14. Email.
     All numeric macro variables are pre-formatted into string
     macro variables here — before the DATA step — so that the
     DATA step contains only plain string references with no
     putn() calls. putn(&variable.) inside a DATA step fails
     when the macro variable is empty at compile time.
--------------------------------------------------------------*/

/* Pre-format all email metric values */
%let email_open_fmt     = %sysfunc(putn(&open_this_week.,   comma10.));
%let email_baseline_fmt = %sysfunc(putn(&baseline_claims.,  comma10.));
%let email_ocr_fmt      = %sysfunc(putn(&ocr_this_week.,    comma18.2));
%let email_reduced_fmt  = %sysfunc(putn(&ocr_reduced.,      comma18.2));
%let email_closed_fmt   = %sysfunc(putn(&closed_this_week., comma10.));
%let email_cumul_fmt    = %sysfunc(putn(&cumul_closed.,      comma10.));
%let email_pct_fmt      = %sysfunc(putn(%sysevalf(&pct_closed.*100), 8.1))%;

filename outbox email;

data _null_;
  file outbox
    to      = ("morris.nkomo@fnb.co.za")
    from    = ("FNB ST Analytics <fnbst-analytics@fnb.co.za>")
    subject = "Motor OCR Tracker -- Week &week_num. (&rd.) [Cycle &cycle_id.]"
    attach  = (
      "&outfile."
      content_type=
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    );

  put "Good morning Morris,";
  put " ";
  put "Please find attached the Motor Retail OCR Tracker for Week &week_num..";
  put " ";

  %if %str(&cycle_mismatch_flag.) = %str(Y) %then %do;
  put "*** NOTE: Report run on &rd. but active cycle is &cycle_id..";
  put "*** Run date month (&rd_yyyymm.) does not match cycle month (&cycle_id.).";
  put "*** Please confirm this is intentional before distributing.";
  put " ";
  %end;

  put "=====================================";
  put "  WEEK &week_num. SUMMARY  (Cycle &cycle_id.)";
  put "=====================================";
  put "  Baseline Claims         : &email_baseline_fmt.";
  put "  Open Claims This Week   : &email_open_fmt.";
  put "  Closed This Week        : &email_closed_fmt.";
  put "  Cumulative Closed       : &email_cumul_fmt.";
  put "  % Claims Closed         : &email_pct_fmt.%";
  put " ";
  put "  Current OCR Amount      : R &email_ocr_fmt.";
  put "  OCR Reduced This Week   : R &email_reduced_fmt.";
  put "=====================================";
  put " ";
  put "The attached Excel file contains:";
  put "  - Summary tracker table (all weeks this cycle)";
  put "  - Full claims detail list";
  put "  - OCR Amount trend chart";
  put "  - Claims closed per week chart";
  put " ";
  put "Filters: Motor | Retail | Not Paid Off";
  put " ";
  put "Regards,";
  put "FNB ST Analytics";
run;

%put NOTE: Email sent for Week &week_num. (CycleID=&cycle_id.).;
%ocr_log(EMAIL, SUCCESS,
         records=&open_this_week.,
         metric=&ocr_this_week.,
         info=Week &week_num. email sent to morris.nkomo@fnb.co.za);

%ocr_log(JOB_END, SUCCESS,
         records=&open_this_week.,
         metric=&ocr_this_week.);

%mend ocr_weekly_main;

/*--------------------------------------------------------------
  Entry point.
--------------------------------------------------------------*/
%ocr_weekly_main;
