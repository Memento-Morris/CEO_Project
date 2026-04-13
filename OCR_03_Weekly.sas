/*==============================================================
  FILE: OCR_03_Weekly.sas
  PURPOSE: Runs every week. Handles Motor AND Non-Motor trackers.
           1. Reads the ACTIVE cycle from the relevant control table.
           2. Pulls current claim state.
           3. Computes weekly movement vs the previous week.
           4. Appends a new row to the relevant weekly tracker.
           5. Exports claims detail to Excel.
           6. Sends email.
==============================================================*/

/*--------------------------------------------------------------
  Libname + logging — must stay in open code.
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
  Run date — override with rd= for back-testing.
--------------------------------------------------------------*/
%if not %symexist(rd) %then %do;
  %let rd = %sysfunc(today(), yymmddn8.);
%end;

/*==============================================================
  MOTOR WEEKLY JOB
==============================================================*/

%global cycle_id baseline_claims baseline_ocr
        baseline_ocr_fmt baseline_claims_fmt
        prev_open prev_ocr_amt
        week_num existing_rows seq_exists
        open_this_week ocr_this_week
        cumul_closed closed_this_week ocr_reduced pct_closed
        cycle_mismatch_flag rd_yyyymm sas_rd outfile
        email_open_fmt email_baseline_fmt email_ocr_fmt
        email_reduced_fmt email_closed_fmt email_cumul_fmt email_pct_fmt;

%macro ocr_weekly_main;

%ocr_log(JOB_START, STARTED, info=Weekly Motor OCR job initiated rd=&rd.);

/*--- Resolve active cycle ---*/
proc sql noprint;
  select CycleID, BaselineClaims, BaselineOCR
  into :cycle_id trimmed, :baseline_claims trimmed, :baseline_ocr trimmed
  from STI_WER.OCR_Cycle_Control
  where Status = 'ACTIVE'
  order by BaselineDate desc;
quit;

%if &sqlobs. = 0 %then %do;
  %ocr_log(RESOLVE_CYCLE, FAILED, error=No ACTIVE cycle found in OCR_Cycle_Control);
  %put ERROR: No ACTIVE cycle found in OCR_Cycle_Control.;
  %put ERROR: Run OCR_02_Baseline.sas on the 16th first.;
  %abort cancel;
%end;

%put NOTE: Active Cycle ID     = &cycle_id.;
%put NOTE: Baseline Claims     = &baseline_claims.;
%put NOTE: Baseline OCR Amount = &baseline_ocr.;
%ocr_log(RESOLVE_CYCLE, SUCCESS, info=CycleID=&cycle_id. Claims=&baseline_claims.);

%let baseline_ocr_fmt    = %sysfunc(putn(&baseline_ocr.,    comma18.2));
%let baseline_claims_fmt = %sysfunc(putn(&baseline_claims., comma10.));

/*--- Cycle / run-date mismatch warning ---*/
%let rd_yyyymm = %sysfunc(substr(&rd., 1, 6));

%if %str(&rd_yyyymm.) ne %str(&cycle_id.) %then %do;
  %put WARNING: Run date month (&rd_yyyymm.) ne active CycleID (&cycle_id.).;
  %ocr_log(CYCLE_DATE_MISMATCH, WARNING, info=RunDate &rd_yyyymm. ne CycleID &cycle_id.);
  %let cycle_mismatch_flag = Y;
%end;
%else %let cycle_mismatch_flag = N;

/*--- Next week number ---*/
proc sql noprint;
  select count(*)
  into :existing_rows trimmed
  from STI_WER.OCR_Weekly_Tracker
  where CycleID = "&cycle_id.";
quit;

%let week_num = &existing_rows.;
%put NOTE: Week number (next to insert) = &week_num.;

/*--- Previous week values ---*/
proc sql noprint;
  select Open_Claims, Current_OCR_Amt
  into :prev_open trimmed, :prev_ocr_amt trimmed
  from STI_WER.OCR_Weekly_Tracker
  where CycleID = "&cycle_id."
    and RunDate = (select max(RunDate) from STI_WER.OCR_Weekly_Tracker
                   where CycleID = "&cycle_id.");
quit;

%if &sqlobs. = 0 %then %do;
  %ocr_log(PREV_WEEK_RESOLVE, FAILED,
           error=Could not resolve previous week values for CycleID &cycle_id.);
  %put ERROR: Could not resolve Open_Claims / Current_OCR_Amt from previous week.;
  %abort cancel;
%end;

/*--- Duplicate-run guard ---*/
proc sql noprint;
  select count(*)
  into :seq_exists trimmed
  from STI_WER.OCR_Weekly_Tracker
  where CycleID = "&cycle_id." and WeekSequence = &week_num.;
quit;

%if &seq_exists. > 0 %then %do;
  %ocr_log(WEEK_RESOLVE, FAILED,
           error=WeekSequence &week_num. already exists for CycleID &cycle_id.);
  %put ERROR: Row for CycleID=&cycle_id. WeekSequence=&week_num. already exists.;
  %abort cancel;
%end;

/*--- Max-weeks guard ---*/
%if &week_num. > 5 %then %do;
  %ocr_log(MAX_WEEKS_EXCEEDED, FAILED,
           error=WeekSequence &week_num. exceeds max of 5 for CycleID &cycle_id.);
  %put ERROR: WeekSequence &week_num. exceeds maximum of 5 for CycleID=&cycle_id..;
  %abort cancel;
%end;

%ocr_log(WEEK_RESOLVE, SUCCESS,
         records=&week_num., info=CycleID=&cycle_id. PrevOpen=&prev_open.);

/*--- Pull snapshot: Motor + Retail ---*/
data work.snapshot;
  set STI_WER.Investigate_Claims(
    keep= ClaimCode SubClaimCode ReportMonth
          Estimate_OCR ProductTypeSplit Division ClaimHandler
  );
  if upcase(strip(ProductTypeSplit)) ne 'MOTOR'  then delete;
  if upcase(strip(Division))         ne 'RETAIL' then delete;
run;

%ocr_log(EXTRACT_SNAPSHOT, SUCCESS, records=&sysnobs.);

/*--- Current estimates ---*/
data work.current_est;
  set STI_WER.vw_OpsClaimsReport(
    keep= SubClaimCode Total_Estimate_OCR_ExVAT Total_Paid_ExVAT
  );
run;

%ocr_log(EXTRACT_ESTIMATES, SUCCESS, records=&sysnobs.);

/*--- Build final claims detail ---*/
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

/*--- Weekly summary metrics ---*/
proc sql noprint;
  select count(distinct ClaimCode), sum(Current_Estimate_OCR)
  into :open_this_week trimmed, :ocr_this_week trimmed
  from work.MotorClaims_Final;
quit;

%let cumul_closed     = %sysevalf(&baseline_claims. - &open_this_week.);
%let closed_this_week = %sysevalf(&prev_open.       - &open_this_week.);
%let ocr_reduced      = %sysevalf(&prev_ocr_amt.    - &ocr_this_week.);

%if %sysevalf(&baseline_claims. > 0, boolean) %then
  %let pct_closed = %sysevalf(&cumul_closed. / &baseline_claims.);
%else
  %let pct_closed = 0;

%ocr_log(CALC_METRICS, SUCCESS, records=&open_this_week., metric=&ocr_this_week.);

/*--- Insert weekly row ---*/
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
      "&cycle_id.", &week_num., "Week &week_num.",
      CONVERT(DATE, "&rd.", 112),
      &baseline_claims., &open_this_week., &ocr_this_week.,
      &cumul_closed., &closed_this_week., &ocr_reduced., &pct_closed.
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

/*--- Pull full tracker for this cycle ---*/
proc sql;
  create table work.tracker_this_cycle as
  select * from STI_WER.OCR_Weekly_Tracker
  where CycleID = "&cycle_id."
  order by WeekSequence;
quit;

/*--- Pivot tracker wide ---*/
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

/*--- Charts ---*/
/* FIX: imagepath= and the closing semicolon must be on the same line.   */
/* Previously imagepath was on a separate line causing ERROR 22-322.     */
ods graphics on / width=800px height=400px imagename="ocr_trend" outputfmt=png imagepath="/data/fnbinsurance/Short_Term/Monitoring/";

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

/*--- Export to Excel ---*/
%let outfile = /data/fnbinsurance/Short_Term/Monitoring/MotorOCR_Tracker_&rd..xlsx;

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
    format Estimate_OCR_When_Flagged Current_Estimate_OCR OCR_Movement comma18.2;
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

%ocr_log(EXPORT_EXCEL, SUCCESS, info=&outfile.);

/*--- Pre-format email values ---*/
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
  put "Filters: Motor | Retail | Not Paid Off";
  put " ";
  put "Regards,";
  put "FNB ST Analytics";
run;

%ocr_log(EMAIL, SUCCESS,
         records=&open_this_week., metric=&ocr_this_week.,
         info=Week &week_num. email sent to morris.nkomo@fnb.co.za);

%ocr_log(JOB_END, SUCCESS, records=&open_this_week., metric=&ocr_this_week.);

%mend ocr_weekly_main;

%ocr_weekly_main;


/*==============================================================
  NON-MOTOR WEEKLY JOB
  Uses separate tables: NM_Cycle_Control and NM_Weekly_Tracker.
  All logic mirrors the Motor job — only the filter, table
  names, file names and email labels differ.
==============================================================*/

%global nm_cycle_id nm_baseline_claims nm_baseline_ocr
        nm_baseline_ocr_fmt nm_baseline_claims_fmt
        nm_prev_open nm_prev_ocr_amt
        nm_week_num nm_existing_rows nm_seq_exists
        nm_open_this_week nm_ocr_this_week
        nm_cumul_closed nm_closed_this_week nm_ocr_reduced nm_pct_closed
        nm_cycle_mismatch_flag nm_outfile
        nm_email_open_fmt nm_email_baseline_fmt nm_email_ocr_fmt
        nm_email_reduced_fmt nm_email_closed_fmt nm_email_cumul_fmt nm_email_pct_fmt;

%macro nm_weekly_main;

%ocr_log(NM_JOB_START, STARTED, info=Weekly Non-Motor OCR job initiated rd=&rd.);

/*--- Resolve active cycle ---*/
proc sql noprint;
  select CycleID, BaselineClaims, BaselineOCR
  into :nm_cycle_id trimmed, :nm_baseline_claims trimmed, :nm_baseline_ocr trimmed
  from STI_WER.NM_Cycle_Control
  where Status = 'ACTIVE'
  order by BaselineDate desc;
quit;

%if &sqlobs. = 0 %then %do;
  %ocr_log(NM_RESOLVE_CYCLE, FAILED, error=No ACTIVE cycle found in NM_Cycle_Control);
  %put ERROR: No ACTIVE Non-Motor cycle found in NM_Cycle_Control.;
  %put ERROR: Run OCR_02_Baseline.sas on the 16th first.;
  %abort cancel;
%end;

%put NOTE: [NM] Active Cycle ID     = &nm_cycle_id.;
%put NOTE: [NM] Baseline Claims     = &nm_baseline_claims.;
%put NOTE: [NM] Baseline OCR Amount = &nm_baseline_ocr.;
%ocr_log(NM_RESOLVE_CYCLE, SUCCESS, info=CycleID=&nm_cycle_id. Claims=&nm_baseline_claims.);

%let nm_baseline_ocr_fmt    = %sysfunc(putn(&nm_baseline_ocr.,    comma18.2));
%let nm_baseline_claims_fmt = %sysfunc(putn(&nm_baseline_claims., comma10.));

/*--- Cycle / run-date mismatch warning ---*/
%let rd_yyyymm = %sysfunc(substr(&rd., 1, 6));

%if %str(&rd_yyyymm.) ne %str(&nm_cycle_id.) %then %do;
  %put WARNING: [NM] Run date month (&rd_yyyymm.) ne active CycleID (&nm_cycle_id.).;
  %ocr_log(NM_CYCLE_DATE_MISMATCH, WARNING, info=RunDate &rd_yyyymm. ne CycleID &nm_cycle_id.);
  %let nm_cycle_mismatch_flag = Y;
%end;
%else %let nm_cycle_mismatch_flag = N;

/*--- Next week number ---*/
proc sql noprint;
  select count(*)
  into :nm_existing_rows trimmed
  from STI_WER.NM_Weekly_Tracker
  where CycleID = "&nm_cycle_id.";
quit;

%let nm_week_num = &nm_existing_rows.;
%put NOTE: [NM] Week number (next to insert) = &nm_week_num.;

/*--- Previous week values ---*/
proc sql noprint;
  select Open_Claims, Current_OCR_Amt
  into :nm_prev_open trimmed, :nm_prev_ocr_amt trimmed
  from STI_WER.NM_Weekly_Tracker
  where CycleID = "&nm_cycle_id."
    and RunDate = (select max(RunDate) from STI_WER.NM_Weekly_Tracker
                   where CycleID = "&nm_cycle_id.");
quit;

%if &sqlobs. = 0 %then %do;
  %ocr_log(NM_PREV_WEEK_RESOLVE, FAILED,
           error=Could not resolve previous week values for CycleID &nm_cycle_id.);
  %put ERROR: [NM] Could not resolve previous week values.;
  %abort cancel;
%end;

/*--- Duplicate-run guard ---*/
proc sql noprint;
  select count(*)
  into :nm_seq_exists trimmed
  from STI_WER.NM_Weekly_Tracker
  where CycleID = "&nm_cycle_id." and WeekSequence = &nm_week_num.;
quit;

%if &nm_seq_exists. > 0 %then %do;
  %ocr_log(NM_WEEK_RESOLVE, FAILED,
           error=WeekSequence &nm_week_num. already exists for CycleID &nm_cycle_id.);
  %put ERROR: [NM] Row for CycleID=&nm_cycle_id. WeekSequence=&nm_week_num. already exists.;
  %abort cancel;
%end;

/*--- Max-weeks guard ---*/
%if &nm_week_num. > 5 %then %do;
  %ocr_log(NM_MAX_WEEKS_EXCEEDED, FAILED,
           error=WeekSequence &nm_week_num. exceeds max of 5 for CycleID &nm_cycle_id.);
  %put ERROR: [NM] WeekSequence &nm_week_num. exceeds maximum of 5.;
  %abort cancel;
%end;

%ocr_log(NM_WEEK_RESOLVE, SUCCESS,
         records=&nm_week_num., info=CycleID=&nm_cycle_id. PrevOpen=&nm_prev_open.);

/*--- Pull snapshot: Non-Motor + Retail ---*/
data work.nm_snapshot;
  set STI_WER.Investigate_Claims(
    keep= ClaimCode SubClaimCode ReportMonth
          Estimate_OCR ProductTypeSplit Division ClaimHandler
  );
  if upcase(strip(ProductTypeSplit)) = 'MOTOR'  then delete;
  if upcase(strip(Division))         ne 'RETAIL' then delete;
run;

%ocr_log(NM_EXTRACT_SNAPSHOT, SUCCESS, records=&sysnobs.);

/*--- Current estimates (reuse work.current_est if Motor ran first) ---*/
%if not %sysfunc(exist(work.current_est)) %then %do;
  data work.current_est;
    set STI_WER.vw_OpsClaimsReport(
      keep= SubClaimCode Total_Estimate_OCR_ExVAT Total_Paid_ExVAT
    );
  run;
%end;

/*--- Build final claims detail ---*/
proc sql;
  create table work.NMClaims_Final as
  select
      c.ClaimCode,
      c.ReportMonth                                             as ReportedMonth,
      c.ClaimHandler,
      c.Estimate_OCR                                            as Estimate_OCR_When_Flagged,
      round(a.Total_Estimate_OCR_ExVAT, 0.01)                  as Current_Estimate_OCR,
      round(a.Total_Estimate_OCR_ExVAT, 0.01) - c.Estimate_OCR as OCR_Movement
  from work.nm_snapshot c
  left join work.current_est a
      on c.SubClaimCode = a.SubClaimCode
  where coalesce(a.Total_Estimate_OCR_ExVAT, 0) > 0
  order by c.ReportMonth desc;
quit;

%ocr_log(NM_BUILD_CLAIMS_DETAIL, SUCCESS, records=&sqlobs.);

/*--- Weekly summary metrics ---*/
proc sql noprint;
  select count(distinct ClaimCode), sum(Current_Estimate_OCR)
  into :nm_open_this_week trimmed, :nm_ocr_this_week trimmed
  from work.NMClaims_Final;
quit;

%let nm_cumul_closed     = %sysevalf(&nm_baseline_claims. - &nm_open_this_week.);
%let nm_closed_this_week = %sysevalf(&nm_prev_open.       - &nm_open_this_week.);
%let nm_ocr_reduced      = %sysevalf(&nm_prev_ocr_amt.    - &nm_ocr_this_week.);

%if %sysevalf(&nm_baseline_claims. > 0, boolean) %then
  %let nm_pct_closed = %sysevalf(&nm_cumul_closed. / &nm_baseline_claims.);
%else
  %let nm_pct_closed = 0;

%ocr_log(NM_CALC_METRICS, SUCCESS, records=&nm_open_this_week., metric=&nm_ocr_this_week.);

/*--- Insert weekly row ---*/
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
    INSERT INTO FNB_STI_Analytics.Claims.NM_Weekly_Tracker
      (CycleID, WeekSequence, WeekLabel, RunDate,
       Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    VALUES (
      "&nm_cycle_id.", &nm_week_num., "Week &nm_week_num.",
      CONVERT(DATE, "&rd.", 112),
      &nm_baseline_claims., &nm_open_this_week., &nm_ocr_this_week.,
      &nm_cumul_closed., &nm_closed_this_week., &nm_ocr_reduced., &nm_pct_closed.
    )
  ) by sqlsvr;

  disconnect from sqlsvr;
quit;

%if &syserr. ne 0 %then %do;
  %ocr_log(NM_INSERT_TRACKER, FAILED,
           error=INSERT into NM_Weekly_Tracker failed SYSERR=&syserr.);
  %put ERROR: [NM] INSERT into NM_Weekly_Tracker failed. SYSERR=&syserr.. Aborting.;
  %abort cancel;
%end;

%ocr_log(NM_INSERT_TRACKER, SUCCESS);

/*--- Pull full tracker for this cycle ---*/
proc sql;
  create table work.nm_tracker_this_cycle as
  select * from STI_WER.NM_Weekly_Tracker
  where CycleID = "&nm_cycle_id."
  order by WeekSequence;
quit;

/*--- Pivot tracker wide ---*/
proc transpose data=work.nm_tracker_this_cycle
               out=work.nm_tracker_wide(drop=_label_)
               prefix=Col_;
  id WeekLabel;
  var Open_Claims Current_OCR_Amt Cumul_Closed
      Closed_This_Week OCR_Reduced_This_Week Pct_Claims_Closed;
run;

data work.nm_tracker_wide;
  set work.nm_tracker_wide;
  rename _NAME_ = Metric;
run;

/*--- Charts ---*/
ods graphics on / width=800px height=400px imagename="nm_ocr_trend" outputfmt=png imagepath="/data/fnbinsurance/Short_Term/Monitoring/";

proc sgplot data=work.nm_tracker_this_cycle;
  series x=WeekLabel y=Current_OCR_Amt /
    markers
    markerattrs=(symbol=circlefilled size=10 color=darkred)
    lineattrs=(thickness=2 color=darkred);
  yaxis label="Current OCR Amount (R)" grid valuesformat=comma18.;
  xaxis label="Week" discreteorder=data;
  title "OCR Amount Movement -- Non-Motor Retail (CycleID &nm_cycle_id.)";
  footnote j=left
    "Baseline: R &nm_baseline_ocr_fmt.  |  Claims: &nm_baseline_claims_fmt.  |  Run: &rd.";
run;

ods graphics on / imagename="nm_claims_closed";

proc sgplot data=work.nm_tracker_this_cycle;
  vbar WeekLabel / response=Closed_This_Week
    fillattrs=(color=firebrick)
    datalabel
    datalabelattrs=(size=10 weight=bold);
  yaxis label="Claims Closed This Week" grid;
  xaxis label="Week" discreteorder=data;
  title "Claims Closed Per Week -- Non-Motor Retail (CycleID &nm_cycle_id.)";
run;

ods graphics off;
%ocr_log(NM_CHARTS, SUCCESS);

/*--- Export to Excel ---*/
%let nm_outfile = /data/fnbinsurance/Short_Term/Monitoring/NonMotorOCR_Tracker_&rd..xlsx;

ods excel file="&nm_outfile."
  options(
    sheet_name      = "Summary"
    embedded_titles = "yes"
    frozen_headers  = "yes"
    autofilter      = "yes"
    flow            = "tables"
  );
  title "OCR Weekly Tracker -- Non-Motor Retail -- Week &nm_week_num. (Cycle &nm_cycle_id.)";
  proc print data=work.nm_tracker_wide noobs label; run;

ods excel options(sheet_name="Claims Detail" autofilter="yes");
  title "Non-Motor Retail Claims Under Investigation -- Week &nm_week_num.";
  proc print data=work.NMClaims_Final noobs label;
    format Estimate_OCR_When_Flagged Current_Estimate_OCR OCR_Movement comma18.2;
  run;

ods excel options(sheet_name="OCR Trend Chart");
  proc sgplot data=work.nm_tracker_this_cycle;
    series x=WeekLabel y=Current_OCR_Amt /
      markers
      markerattrs=(symbol=circlefilled size=10 color=darkred)
      lineattrs=(thickness=2 color=darkred);
    yaxis label="Current OCR Amount (R)" grid valuesformat=comma18.;
    xaxis label="Week" discreteorder=data;
    title "OCR Amount Movement -- Non-Motor Retail";
  run;

ods excel options(sheet_name="Claims Closed Chart");
  proc sgplot data=work.nm_tracker_this_cycle;
    vbar WeekLabel / response=Closed_This_Week
      fillattrs=(color=firebrick)
      datalabel
      datalabelattrs=(size=10 weight=bold);
    yaxis label="Claims Closed This Week" grid;
    xaxis label="Week" discreteorder=data;
    title "Claims Closed Per Week -- Non-Motor Retail";
  run;

ods excel close;
title; footnote;

%ocr_log(NM_EXPORT_EXCEL, SUCCESS, info=&nm_outfile.);

/*--- Pre-format email values ---*/
%let nm_email_open_fmt     = %sysfunc(putn(&nm_open_this_week.,   comma10.));
%let nm_email_baseline_fmt = %sysfunc(putn(&nm_baseline_claims.,  comma10.));
%let nm_email_ocr_fmt      = %sysfunc(putn(&nm_ocr_this_week.,    comma18.2));
%let nm_email_reduced_fmt  = %sysfunc(putn(&nm_ocr_reduced.,      comma18.2));
%let nm_email_closed_fmt   = %sysfunc(putn(&nm_closed_this_week., comma10.));
%let nm_email_cumul_fmt    = %sysfunc(putn(&nm_cumul_closed.,      comma10.));
%let nm_email_pct_fmt      = %sysfunc(putn(%sysevalf(&nm_pct_closed.*100), 8.1))%;

filename nm_outbx email;

data _null_;
  file nm_outbx
    to      = ("morris.nkomo@fnb.co.za")
    from    = ("FNB ST Analytics <fnbst-analytics@fnb.co.za>")
    subject = "Non-Motor OCR Tracker -- Week &nm_week_num. (&rd.) [Cycle &nm_cycle_id.]"
    attach  = (
      "&nm_outfile."
      content_type=
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    );

  put "Good morning Morris,";
  put " ";
  put "Please find attached the Non-Motor Retail OCR Tracker for Week &nm_week_num..";
  put " ";

  %if %str(&nm_cycle_mismatch_flag.) = %str(Y) %then %do;
  put "*** NOTE: Report run on &rd. but active cycle is &nm_cycle_id..";
  put "*** Run date month (&rd_yyyymm.) does not match cycle month (&nm_cycle_id.).";
  put " ";
  %end;

  put "=====================================";
  put "  WEEK &nm_week_num. SUMMARY  (Cycle &nm_cycle_id.)";
  put "=====================================";
  put "  Baseline Claims         : &nm_email_baseline_fmt.";
  put "  Open Claims This Week   : &nm_email_open_fmt.";
  put "  Closed This Week        : &nm_email_closed_fmt.";
  put "  Cumulative Closed       : &nm_email_cumul_fmt.";
  put "  % Claims Closed         : &nm_email_pct_fmt.%";
  put " ";
  put "  Current OCR Amount      : R &nm_email_ocr_fmt.";
  put "  OCR Reduced This Week   : R &nm_email_reduced_fmt.";
  put "=====================================";
  put " ";
  put "Filters: Non-Motor | Retail | Not Paid Off";
  put " ";
  put "Regards,";
  put "FNB ST Analytics";
run;

%ocr_log(NM_EMAIL, SUCCESS,
         records=&nm_open_this_week., metric=&nm_ocr_this_week.,
         info=Week &nm_week_num. NM email sent to morris.nkomo@fnb.co.za);

%ocr_log(NM_JOB_END, SUCCESS, records=&nm_open_this_week., metric=&nm_ocr_this_week.);

%mend nm_weekly_main;

%nm_weekly_main;
