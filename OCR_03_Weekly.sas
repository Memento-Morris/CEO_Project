/*==============================================================
  FILE: OCR_03_Weekly.sas
  PURPOSE: Runs every week (every Monday, or agreed day).
           1. Reads the ACTIVE cycle from OCR_Cycle_Control —
              no hardcoding of CycleID or baseline_date needed.
           2. Pulls current claim state.
           3. Computes weekly movement vs the previous week.
           4. Appends a new row to OCR_Weekly_Tracker.
           5. Exports the detail claims list to Excel.
           6. Sends email.

  DESIGN PRINCIPLES:
    - Zero hardcoding. The active cycle is always resolved from
      OCR_Cycle_Control (Status = 'ACTIVE'). When the Baseline
      job runs on the 16th it inserts a new ACTIVE row there,
      which automatically drives the next run of this job into
      the new cycle.
    - No deletes. OCR_Weekly_Tracker accumulates forever.
    - If no ACTIVE cycle exists the job aborts cleanly with a
      clear message.
    - If a row already exists for (CycleID, WeekSequence) the
      job aborts before inserting to prevent duplicates.

  CHANGES:
    Bug 1 fixed — %let week_num moved outside PROC SQL so that
                  &existing_rows. is fully resolved before use.
                  The two SELECT statements are also split into
                  separate PROC SQL blocks for clarity.
    Bug 2 fixed — division by zero guard added to pct_closed
                  calculation.
    Bug 3 fixed — date informat changed from yymmdd8. to
                  yymmddN8. to correctly parse packed YYYYMMDD
                  strings with no delimiters.
    Bug 4 fixed — abort added if prev_open / prev_ocr_amt
                  cannot be resolved (sqlobs = 0).
    Feature 3   — max-weeks guard: job aborts cleanly if
                  WeekSequence would exceed 5, with a clear
                  message to close the cycle first.
    Feature 5   — cycle/run-date mismatch warning: if the run
                  date month does not match the active CycleID
                  a WARNING is written to the log and the email
                  so the analyst is aware.

  SCHEDULE: Weekly — every Monday (or agreed day), after the
            16th baseline has run for that month.
==============================================================*/

/*--------------------------------------------------------------
  1. Libname + logging macro
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
  2. Run date — override by passing rd= if back-testing.
--------------------------------------------------------------*/
%if not %symexist(rd) %then %do;
  %let rd = %sysfunc(today(), yymmddn8.);
%end;

%ocr_log(JOB_START, STARTED, info=Weekly OCR job initiated rd=&rd.);

/*--------------------------------------------------------------
  3. Resolve active cycle from OCR_Cycle_Control.

  This replaces ALL hardcoded %let baseline_date / %let cycle_id
  statements. The Baseline job (OCR_02) owns the decision of
  which CycleID is active — this job simply reads that decision.

  Fields resolved here:
    cycle_id        YYYYMM of the active cycle.
    baseline_claims Claim count captured on the 16th.
    baseline_ocr    OCR amount captured on the 16th.
--------------------------------------------------------------*/
%macro resolve_cycle;

  proc sql noprint;
    select CycleID,
           BaselineClaims,
           BaselineOCR
    into :cycle_id       trimmed,
         :baseline_claims trimmed,
         :baseline_ocr    trimmed
    from STI_WER.OCR_Cycle_Control
    where Status = 'ACTIVE'
    order by BaselineDate desc;   /* takes the most recent if somehow >1 */
  quit;

  /* &sqlobs. holds the row count of the last SELECT */
  %if &sqlobs. = 0 %then %do;
    %ocr_log(RESOLVE_CYCLE, FAILED,
             error=No ACTIVE cycle found in OCR_Cycle_Control);
    %put ERROR: No ACTIVE cycle found in OCR_Cycle_Control.;
    %put ERROR: Run OCR_02_Baseline.sas on the 16th first, then re-schedule this job.;
    %abort cancel;
  %end;

%mend resolve_cycle;

%resolve_cycle;

%put NOTE: Active Cycle ID      = &cycle_id.;
%put NOTE: Baseline Claims      = &baseline_claims.;
%put NOTE: Baseline OCR Amount  = &baseline_ocr.;

/*--------------------------------------------------------------
  Feature 5: Cycle / run-date mismatch warning.
  If the month in &rd. (YYYYMMDD) does not match &cycle_id.
  (YYYYMM) the job is running in a different month from the
  active cycle. This is not necessarily wrong (e.g. a cycle
  still ACTIVE after month-end) but it is worth flagging so
  the analyst can confirm intent before the row is inserted.
--------------------------------------------------------------*/
%let rd_yyyymm = %sysfunc(substr(&rd., 1, 6));

%if &rd_yyyymm. ne &cycle_id. %then %do;
  %put WARNING: Run date month (&rd_yyyymm.) does not match active CycleID (&cycle_id.).;
  %put WARNING: This job is running in a different month from the active cycle.;
  %put WARNING: If this is intentional (cycle still open after month-end) you can ignore this warning.;
  %put WARNING: If it is NOT intentional, check whether OCR_02_Baseline.sas has run for &rd_yyyymm..;
  %ocr_log(CYCLE_DATE_MISMATCH, WARNING,
           info=RunDate month &rd_yyyymm. ne CycleID &cycle_id.);
  /* Store flag for email — Y = mismatch warning to include */
  %let cycle_mismatch_flag = Y;
%end;
%else %let cycle_mismatch_flag = N;

/*--------------------------------------------------------------
  4. Determine the next WeekSequence to insert.

  Bug 1 fix: the original code placed %let week_num inside a
  PROC SQL block between two SELECT statements. Macro variable
  assignment mid-proc is unreliable — &existing_rows. may not
  yet be populated. The two queries are now in separate PROC SQL
  blocks and %let week_num is assigned after the first quit.

  Also pull the previous week's open claim count and OCR amount
  for delta calculations.
--------------------------------------------------------------*/

/* Step 4a: count existing rows for this cycle */
proc sql noprint;
  select count(*)
  into :existing_rows trimmed
  from STI_WER.OCR_Weekly_Tracker
  where CycleID = "&cycle_id.";
quit;

%let week_num = &existing_rows.;

%put NOTE: Week number (next to insert) = &week_num.;

/* Step 4b: pull previous week's values for delta calculations */
proc sql noprint;
  select Open_Claims,
         Current_OCR_Amt
  into :prev_open    trimmed,
       :prev_ocr_amt trimmed
  from STI_WER.OCR_Weekly_Tracker
  where CycleID = "&cycle_id."
    and RunDate  = (
        select max(RunDate)
        from STI_WER.OCR_Weekly_Tracker
        where CycleID = "&cycle_id."
    );
quit;

/* Bug 4 fix: abort cleanly if previous values cannot be found. */
%if &sqlobs. = 0 %then %do;
  %ocr_log(PREV_WEEK_RESOLVE, FAILED,
           error=Could not resolve previous week values for CycleID &cycle_id.);
  %put ERROR: Could not resolve Open_Claims / Current_OCR_Amt from the previous week.;
  %put ERROR: CycleID=&cycle_id.. Check that OCR_Weekly_Tracker contains at least the baseline row.;
  %abort cancel;
%end;

%put NOTE: Previous open claims         = &prev_open.;
%put NOTE: Previous OCR amount          = &prev_ocr_amt.;

/* Duplicate-run guard — abort if this WeekSequence already exists */
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
  %put ERROR: This job has already run for this week. Aborting to prevent duplicates.;
  %abort cancel;
%end;

/*--------------------------------------------------------------
  Feature 3: Max-weeks guard.
  A cycle is designed for up to 5 weekly runs (WeekSequence
  1–5). If week_num would exceed 5, the cycle should have been
  closed first. Abort with a clear message rather than inserting
  a Week 6+ row that is outside the expected cycle structure.
--------------------------------------------------------------*/
%if &week_num. > 5 %then %do;
  %ocr_log(MAX_WEEKS_EXCEEDED, FAILED,
           error=WeekSequence &week_num. exceeds maximum of 5 for CycleID &cycle_id.);
  %put ERROR: WeekSequence &week_num. would exceed the maximum of 5 for CycleID=&cycle_id..;
  %put ERROR: The cycle must be closed (Status=CLOSED in OCR_Cycle_Control) before a;
  %put ERROR: new baseline can be opened. Run OCR_04_CloseCycle.sas or update the;
  %put ERROR: Status column manually, then run OCR_02_Baseline.sas for the new cycle.;
  %abort cancel;
%end;

%ocr_log(WEEK_RESOLVE, SUCCESS,
         records=&week_num.,
         info=CycleID=&cycle_id. PrevOpen=&prev_open.);

/*--------------------------------------------------------------
  5. Pull snapshot — Motor + Retail from Investigate_Claims.
     Investigate_Claims is refreshed on the 16th by OCR_02
     and is the stable baseline list for the whole cycle.
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
      c.ReportMonth                                              as ReportedMonth,
      c.ClaimHandler,
      c.Estimate_OCR                                             as Estimate_OCR_When_Flagged,
      round(a.Total_Estimate_OCR_ExVAT, 0.01)                   as Current_Estimate_OCR,
      round(a.Total_Estimate_OCR_ExVAT, 0.01) - c.Estimate_OCR  as OCR_Movement
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
  into :open_this_week  trimmed,
       :ocr_this_week   trimmed
  from work.MotorClaims_Final;
quit;

%put NOTE: Open this week = &open_this_week.;
%put NOTE: OCR this week  = &ocr_this_week.;

%let cumul_closed     = %sysevalf(&baseline_claims. - &open_this_week.);
%let closed_this_week = %sysevalf(&prev_open.       - &open_this_week.);
%let ocr_reduced      = %sysevalf(&prev_ocr_amt.    - &ocr_this_week.);

/* Bug 2 fix: guard against division by zero if baseline_claims = 0 */
%if &baseline_claims. > 0 %then
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
     Uses PROC SQL INSERT via STI_WER libref.
     Bug 3 fix: yymmddN8. informat correctly parses packed
     YYYYMMDD strings (no delimiters).
     UNIQUE constraint (CycleID, WeekSequence) on the table
     provides a final database-level duplicate guard.
--------------------------------------------------------------*/
%let sas_rd = %sysfunc(inputn(&rd., yymmddN8.));

proc sql noprint;
  insert into STI_WER.OCR_Weekly_Tracker
    (CycleID, WeekSequence, WeekLabel, RunDate,
     Baseline_Claims, Open_Claims,
     Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
     OCR_Reduced_This_Week, Pct_Claims_Closed)
  values (
    "&cycle_id.",
    &week_num.,
    "Week &week_num.",
    &sas_rd.,
    &baseline_claims.,
    &open_this_week.,
    &ocr_this_week.,
    &cumul_closed.,
    &closed_this_week.,
    &ocr_reduced.,
    &pct_closed.
  );
quit;

%if &sqlrc. ne 0 %then %do;
  %ocr_log(INSERT_TRACKER, FAILED,
           error=INSERT into OCR_Weekly_Tracker failed SQLRC=&sqlrc.);
  %put ERROR: INSERT into OCR_Weekly_Tracker failed. SQLRC=&sqlrc.. Aborting.;
  %abort cancel;
%end;

%ocr_log(INSERT_TRACKER, SUCCESS);
%put NOTE: Week &week_num. row inserted into OCR_Weekly_Tracker (CycleID=&cycle_id.).;

/*--------------------------------------------------------------
  10. Pull full tracker for this cycle (for report + charts).
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
  12. Charts
--------------------------------------------------------------*/
ods graphics on / width=800px height=400px imagename="ocr_trend" outputfmt=png
               imagepath="/data/fnbinsurance/Short_Term/Monitoring/";

proc sgplot data=work.tracker_this_cycle;
  series x=WeekLabel y=Current_OCR_Amt /
    markers
    markerattrs=(symbol=circlefilled size=10 color=darkblue)
    lineattrs=(thickness=2 color=darkblue);
  yaxis label="Current OCR Amount (R)"
        grid
        valuesformat=comma18.;
  xaxis label="Week" discreteorder=data;
  title "OCR Amount Movement -- Motor Retail (CycleID &cycle_id.)";
  footnote j=left "Baseline: R %sysfunc(putn(&baseline_ocr., comma18.2))  |  "
                  "Claims: &baseline_claims.  |  Run: &rd.";
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
%let outfile = /data/fnbinsurance/Short_Term/Monitoring/MotorOCR_Tracker_&rd..xlsx;

ods excel file="&outfile."
  options(
    sheet_name        = "Summary"
    embedded_titles   = "yes"
    frozen_headers    = "yes"
    autofilter        = "yes"
    flow              = "tables"
  );

  title "OCR Weekly Performance Tracker -- Motor Retail -- Week &week_num. (Cycle &cycle_id.)";
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

%put NOTE: Excel report written to &outfile.;
%ocr_log(EXPORT_EXCEL, SUCCESS, info=&outfile.);

/*--------------------------------------------------------------
  14. Email
--------------------------------------------------------------*/
filename outbox email;

data _null_;
  file outbox
    to      = ("morris.nkomo@fnb.co.za")
    from    = ("FNB ST Analytics <fnbst-analytics@fnb.co.za>")
    subject = "Motor OCR Tracker -- Week &week_num. (&rd.) [Cycle &cycle_id.]"
    attach  = (
      "&outfile."
      content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    );

  open_fmt     = strip(putn(&open_this_week.,  'comma10.'));
  baseline_fmt = strip(putn(&baseline_claims., 'comma10.'));
  ocr_fmt      = strip(putn(&ocr_this_week.,   'comma18.2'));
  reduced_fmt  = strip(putn(&ocr_reduced.,     'comma18.2'));
  closed_fmt   = strip(putn(&closed_this_week.,'comma10.'));
  cumul_fmt    = strip(putn(&cumul_closed.,    'comma10.'));
  pct_fmt      = strip(putn(&pct_closed.*100,  '8.1')) || '%';

  put "Good morning Morris,";
  put " ";
  put "Please find attached the Motor Retail OCR Tracker for Week &week_num..";
  put " ";

  /* Feature 5: include mismatch warning in email body if flagged */
  %if &cycle_mismatch_flag. = Y %then %do;
  put "*** NOTE: This report was run on &rd. but the active cycle is &cycle_id..";
  put "*** The run date month (&rd_yyyymm.) does not match the cycle month (&cycle_id.).";
  put "*** Please confirm this is intentional before distributing.";
  put " ";
  %end;

  put "=====================================";
  put "  WEEK &week_num. SUMMARY  (Cycle &cycle_id.)";
  put "=====================================";
  put "  Baseline Claims         : " baseline_fmt;
  put "  Open Claims This Week   : " open_fmt;
  put "  Closed This Week        : " closed_fmt;
  put "  Cumulative Closed       : " cumul_fmt;
  put "  % Claims Closed         : " pct_fmt;
  put " ";
  put "  Current OCR Amount      : R " ocr_fmt;
  put "  OCR Reduced This Week   : R " reduced_fmt;
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
