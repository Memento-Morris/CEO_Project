/*==============================================================
  FILE: OCR_03_Weekly.sas
  PURPOSE: Runs every week (e.g. every Monday).
           1. Pulls current claim state
           2. Computes weekly movement vs last week
           3. Appends a new row to OCR_Weekly_Tracker
           4. Exports the detail claims list to Excel
           5. Sends email
  SCHEDULE: Weekly — every Monday (or agreed day), after the
            16th baseline has run for that month.
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
  2. Run date & week number
--------------------------------------------------------------*/
%if not %symexist(rd) %then %do;
  %let rd = %sysfunc(today(), yymmddn8.);
%end;

/* Determine week number = rows already in tracker this month + 1
   (Baseline row counts as row 0 effectively, Week 1 = first weekly run) */
proc sql noprint;
  select count(*)
  into :existing_rows trimmed
  from STI_WER.OCR_Weekly_Tracker
  where YEAR(RunDate)  = %sysfunc(year(%sysfunc(today())))
    and MONTH(RunDate) = %sysfunc(month(%sysfunc(today())));

  /* Baseline row is already there, so week_num = existing rows (not +1) */
  %let week_num = &existing_rows.;

  /* Pull baseline stats for this month */
  select Baseline_Claims,
         Current_OCR_Amt,
         Open_Claims
  into :baseline_claims trimmed,
       :baseline_ocr    trimmed,
       :prev_open       trimmed
  from STI_WER.OCR_Weekly_Tracker
  where YEAR(RunDate)  = %sysfunc(year(%sysfunc(today())))
    and MONTH(RunDate) = %sysfunc(month(%sysfunc(today())))
    and WeekLabel      = 'Baseline';

  /* Pull last week's OCR and open count for delta */
  select Open_Claims,
         Current_OCR_Amt
  into :prev_open    trimmed,
       :prev_ocr_amt trimmed
  from STI_WER.OCR_Weekly_Tracker
  where RunDate = (
      select max(RunDate)
      from STI_WER.OCR_Weekly_Tracker
      where YEAR(RunDate)  = %sysfunc(year(%sysfunc(today())))
        and MONTH(RunDate) = %sysfunc(month(%sysfunc(today())))
  );
quit;

%put NOTE: Week number  = &week_num.;
%put NOTE: Prev open    = &prev_open.;
%put NOTE: Prev OCR amt = &prev_ocr_amt.;

/*--------------------------------------------------------------
  3. Pull snapshot — Motor + Retail from Investigate_Claims
--------------------------------------------------------------*/
data work.snapshot;
  set STI_WER.Investigate_Claims(
    keep= ClaimCode SubClaimCode ReportMonth
          Estimate_OCR ProductTypeSplit Division ClaimHandler
  );
  if upcase(strip(ProductTypeSplit)) ne 'MOTOR'  then delete;
  if upcase(strip(Division))         ne 'RETAIL' then delete;
run;

/*--------------------------------------------------------------
  4. Pull current estimates from live view
--------------------------------------------------------------*/
data work.current_est;
  set STI_WER.vw_OpsClaimsReport(
    keep= SubClaimCode Total_Estimate_OCR_ExVAT Total_Paid_ExVAT
  );
run;

/*--------------------------------------------------------------
  5. Build final claims detail (not paid off only)
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

/*--------------------------------------------------------------
  6. Compute this week's summary metrics
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

/* Derived metrics */
%let cumul_closed     = %sysevalf(&baseline_claims. - &open_this_week.);
%let closed_this_week = %sysevalf(&prev_open.       - &open_this_week.);
%let ocr_reduced      = %sysevalf(&prev_ocr_amt.    - &ocr_this_week.);
%let pct_closed       = %sysevalf(&cumul_closed. / &baseline_claims.);

%put NOTE: Cumul closed     = &cumul_closed.;
%put NOTE: Closed this week = &closed_this_week.;
%put NOTE: OCR reduced      = &ocr_reduced.;
%put NOTE: Pct closed       = &pct_closed.;

/*--------------------------------------------------------------
  7. Insert weekly row into tracker
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
    INSERT INTO FNB_STI_Analytics.Claims.OCR_Weekly_Tracker
      (WeekLabel, RunDate, Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    VALUES (
      %unquote('Week &week_num.'),
      CAST(GETDATE() AS DATE),
      %unquote(&baseline_claims.),
      %unquote(&open_this_week.),
      %unquote(&ocr_this_week.),
      %unquote(&cumul_closed.),
      %unquote(&closed_this_week.),
      %unquote(&ocr_reduced.),
      %unquote(&pct_closed.)
    )
  ) by sqlsvr;

  disconnect from sqlsvr;
quit;

%put NOTE: Week &week_num. row inserted into OCR_Weekly_Tracker.;

/*--------------------------------------------------------------
  8. Pull full tracker for this month (for report + charts)
--------------------------------------------------------------*/
proc sql;
  create table work.tracker_this_month as
  select *
  from STI_WER.OCR_Weekly_Tracker
  where YEAR(RunDate)  = %sysfunc(year(%sysfunc(today())))
    and MONTH(RunDate) = %sysfunc(month(%sysfunc(today())))
  order by RunDate;
quit;

/*--------------------------------------------------------------
  9. Pivot tracker wide (metrics as rows, weeks as columns)
     Matches the layout of your Excel table
--------------------------------------------------------------*/
proc transpose data=work.tracker_this_month
               out=work.tracker_wide(drop=_label_)
               prefix=Col_;
  id WeekLabel;
  var Open_Claims Current_OCR_Amt Cumul_Closed
      Closed_This_Week OCR_Reduced_This_Week Pct_Claims_Closed;
run;

/* Rename _NAME_ to Metric */
data work.tracker_wide;
  set work.tracker_wide;
  rename _NAME_ = Metric;
run;

/*--------------------------------------------------------------
  10. Charts
--------------------------------------------------------------*/
/* Output charts to PNG files for embedding in email */
ods graphics on / width=800px height=400px imagename="ocr_trend" outputfmt=png
               imagepath="/data/fnbinsurance/Short_Term/Monitoring/";

/* Chart 1 — OCR Amount declining over weeks */
proc sgplot data=work.tracker_this_month;
  series x=WeekLabel y=Current_OCR_Amt /
    markers
    markerattrs=(symbol=circlefilled size=10 color=darkblue)
    lineattrs=(thickness=2 color=darkblue);
  yaxis label="Current OCR Amount (R)"
        grid
        valuesformat=comma18.;
  xaxis label="Week" discreteorder=data;
  title "OCR Amount Movement — Motor Retail";
  footnote j=left "Baseline: R %sysfunc(putn(&baseline_ocr., comma18.2))  |  "
                  "Claims: &baseline_claims.  |  Run: &rd.";
run;

ods graphics on / imagename="claims_closed";

/* Chart 2 — Claims closed per week */
proc sgplot data=work.tracker_this_month;
  vbar WeekLabel / response=Closed_This_Week
    fillattrs=(color=steelblue)
    datalabel
    datalabelattrs=(size=10 weight=bold);
  yaxis label="Claims Closed This Week" grid;
  xaxis label="Week" discreteorder=data;
  title "Claims Closed Per Week — Motor Retail";
run;

ods graphics off;

/*--------------------------------------------------------------
  11. Export to Excel — 3 sheets:
      Sheet 1: Summary tracker table
      Sheet 2: Claims detail
      Sheet 3: (Charts embedded manually or via ODS Excel)
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

  title "OCR Weekly Performance Tracker — Motor Retail — Week &week_num.";
  proc print data=work.tracker_wide noobs label; run;

ods excel options(sheet_name="Claims Detail" autofilter="yes");

  title "Motor Retail Claims Under Investigation — Week &week_num.";
  proc print data=work.MotorClaims_Final noobs label;
    format Estimate_OCR_When_Flagged
           Current_Estimate_OCR
           OCR_Movement           comma18.2;
  run;

ods excel options(sheet_name="OCR Trend Chart");
  proc sgplot data=work.tracker_this_month;
    series x=WeekLabel y=Current_OCR_Amt /
      markers
      markerattrs=(symbol=circlefilled size=10 color=darkblue)
      lineattrs=(thickness=2 color=darkblue);
    yaxis label="Current OCR Amount (R)" grid valuesformat=comma18.;
    xaxis label="Week" discreteorder=data;
    title "OCR Amount Movement — Motor Retail";
  run;

ods excel options(sheet_name="Claims Closed Chart");
  proc sgplot data=work.tracker_this_month;
    vbar WeekLabel / response=Closed_This_Week
      fillattrs=(color=steelblue)
      datalabel
      datalabelattrs=(size=10 weight=bold);
    yaxis label="Claims Closed This Week" grid;
    xaxis label="Week" discreteorder=data;
    title "Claims Closed Per Week — Motor Retail";
  run;

ods excel close;
title; footnote;

%put NOTE: Excel report written to &outfile.;

/*--------------------------------------------------------------
  12. Email
--------------------------------------------------------------*/
filename outbox email;

data _null_;
  file outbox
    to      = ("morris.nkomo@fnb.co.za")
    from    = ("FNB ST Analytics <fnbst-analytics@fnb.co.za>")
    subject = "Motor OCR Tracker — Week &week_num. (&rd.)"
    attach  = (
      "&outfile."
      content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    );

  /* Format numbers nicely for email body */
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
  put "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
  put "  WEEK &week_num. SUMMARY";
  put "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
  put "  Baseline Claims         : " baseline_fmt;
  put "  Open Claims This Week   : " open_fmt;
  put "  Closed This Week        : " closed_fmt;
  put "  Cumulative Closed       : " cumul_fmt;
  put "  % Claims Closed         : " pct_fmt;
  put " ";
  put "  Current OCR Amount      : R " ocr_fmt;
  put "  OCR Reduced This Week   : R " reduced_fmt;
  put "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
  put " ";
  put "The attached Excel file contains:";
  put "  - Summary tracker table (all weeks this month)";
  put "  - Full claims detail list";
  put "  - OCR Amount trend chart";
  put "  - Claims closed per week chart";
  put " ";
  put "Filters: Motor | Retail | Not Paid Off";
  put " ";
  put "Regards,";
  put "FNB ST Analytics";
run;

%put NOTE: Email sent for Week &week_num.;
