/*==============================================================
  FILE: OCR_02_Baseline.sas
  PURPOSE: Runs on the 16th of each month. Handles both Motor
           and Non-Motor baselines in one file.
           1. Refreshes Investigate_Claims.
           2. Auto-closes the previous ACTIVE cycle for each tracker.
           3. Counts baseline claims and OCR for each portfolio.
           4. Opens a new cycle and inserts WeekSequence=0 rows.
           5. Sends a success email once both baselines complete.

  SCHEDULE: 16th of every month — run BEFORE OCR_03_Weekly.sas.

  FIXES APPLIED (2026-04-16):
    1. sas_rd derivation: today() returns raw integer first,
       formatted string (rd) derived from it — not the reverse.
    2. BaselineDate INSERT: uses SAS date literal syntax "..."d
       so the ODBC layer passes a typed date, not a plain integer.
    3. File saved UTF-8 without BOM to prevent Error 180-322
       on the opening comment block.
==============================================================*/

/*--------------------------------------------------------------
  Libnames + Logging
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
  Derive run date and CycleID.

  FIX 1: today() returns a raw SAS date integer directly.
          We format that integer into a string (rd) for display
          and CycleID — never the other way around.
          This prevents inputn() misreading the format name and
          returning a missing value for sas_rd.
--------------------------------------------------------------*/
%if not %symexist(rd) %then %do;
  /* Normal scheduled run — derive everything from today()     */
  %let sas_rd = %sysfunc(today());                         /* raw SAS date integer, e.g. 24221  */
  %let rd     = %sysfunc(putn(&sas_rd., yymmddn8.));       /* formatted string,     e.g. 20260416 */
%end;
%else %do;
  /* rd was injected externally (manual rerun with a date arg) */
  /* Strip any whitespace before converting to avoid inputn()  */
  /* receiving a blank token.                                   */
  %let sas_rd = %sysfunc(inputn(%sysfunc(compress(&rd.)), yymmddN8.));
%end;

%let cycle_id = %substr(&rd., 1, 6);
%let rd_fmt   = %sysfunc(putn(&sas_rd., date9.));

/* Diagnostic — confirm all four values resolved correctly */
%put NOTE: [DIAG] rd       = [&rd.];
%put NOTE: [DIAG] sas_rd   = [&sas_rd.];
%put NOTE: [DIAG] cycle_id = [&cycle_id.];
%put NOTE: [DIAG] rd_fmt   = [&rd_fmt.];

/* Global success flags — set to 1 only when each section completes */
%global motor_success nm_success;
%let motor_success = 0;
%let nm_success    = 0;

/* Previous cycle closing position — populated before cycles are closed */
%global prev_cycle_id    prev_close_claims  prev_close_ocr
        prev_pct_closed
        nm_prev_cycle_id nm_prev_close_claims nm_prev_close_ocr
        nm_prev_pct_closed;

%ocr_log(BASELINE_START, STARTED, info=Cycle &cycle_id. baseline initiated);

/*--------------------------------------------------------------
  Step 0 — Capture previous cycle closing position for BOTH
  portfolios BEFORE the auto-close updates Status to CLOSED.
--------------------------------------------------------------*/

/* Motor — last week of the outgoing cycle */
proc sql noprint;
  select t.CycleID,
         t.Open_Claims,
         t.Current_OCR_Amt,
         t.Pct_Claims_Closed
  into :prev_cycle_id      trimmed,
       :prev_close_claims  trimmed,
       :prev_close_ocr     trimmed,
       :prev_pct_closed    trimmed
  from STI_WER.OCR_Weekly_Tracker t
  inner join STI_WER.OCR_Cycle_Control c
      on t.CycleID = c.CycleID
  where c.Status = 'ACTIVE'
    and t.WeekSequence = (
          select max(WeekSequence)
          from STI_WER.OCR_Weekly_Tracker
          where CycleID = t.CycleID
        )
  order by c.BaselineDate desc;
quit;

%if &sqlobs. = 0 %then %do;
  %let prev_cycle_id     = N/A;
  %let prev_close_claims = .;
  %let prev_close_ocr    = .;
  %let prev_pct_closed   = .;
  %put NOTE: No previous Motor cycle found — first run or no prior data.;
%end;

/* Non-Motor — last week of the outgoing cycle */
proc sql noprint;
  select t.CycleID,
         t.Open_Claims,
         t.Current_OCR_Amt,
         t.Pct_Claims_Closed
  into :nm_prev_cycle_id      trimmed,
       :nm_prev_close_claims  trimmed,
       :nm_prev_close_ocr     trimmed,
       :nm_prev_pct_closed    trimmed
  from STI_WER.NM_Weekly_Tracker t
  inner join STI_WER.NM_Cycle_Control c
      on t.CycleID = c.CycleID
  where c.Status = 'ACTIVE'
    and t.WeekSequence = (
          select max(WeekSequence)
          from STI_WER.NM_Weekly_Tracker
          where CycleID = t.CycleID
        )
  order by c.BaselineDate desc;
quit;

%if &sqlobs. = 0 %then %do;
  %let nm_prev_cycle_id     = N/A;
  %let nm_prev_close_claims = .;
  %let nm_prev_close_ocr    = .;
  %let nm_prev_pct_closed   = .;
  %put NOTE: No previous Non-Motor cycle found — first run or no prior data.;
%end;

%ocr_log(PREV_CYCLE_CAPTURE, SUCCESS,
         info=Motor prev=&prev_cycle_id. NM prev=&nm_prev_cycle_id.);

/*==============================================================
  EMAIL MACROS
==============================================================*/

/* --- 1. Baseline reset email --- */
%macro send_baseline_email;

  filename bl_outbx email;

  data _null_;
    file bl_outbx
      to      = ("morris.nkomo@fnb.co.za")
      cc      = ("asher.levin@fnb.co.za" "Webster.khoza@fnb.co.za")
      from    = ("morris.nkomo@fnb.co.za")
      subject = "OCR Baseline Reset -- Cycle &cycle_id. (&rd_fmt.)";
    put "I hope you're well.";
    put " ";
    put "Please be advised that the monthly OCR baseline has been refreshed for Cycle &cycle_id..";
    put "Both Motor and Non-Motor trackers have been reset and are ready for weekly tracking.";
    put " ";
    put "-------------------------------";
    put "Motor OCR Baseline (Retail)";
    put "-------------------------------";
    put " ";
    put "Baseline claims:";
    put "  &baseline_claims.";
    put " ";
    put "Baseline OCR amount:";
    put "  R &baseline_ocr_fmt.";
    put " ";
    put "-------------------------------";
    put "Non-Motor OCR Baseline (Retail)";
    put "-------------------------------";
    put " ";
    put "Baseline claims:";
    put "  &nm_baseline_claims.";
    put " ";
    put "Baseline OCR amount:";
    put "  R &nm_baseline_ocr_fmt.";
    put " ";
    put "-------------------------------";
    put " ";
    put "Weekly tracking (OCR_03_Weekly.sas) will commence from next week.";
    put " ";
    put "Kind regards";
    put "Morris";
  run;

  %put NOTE: Baseline reset email sent for CycleID=&cycle_id.;
  %ocr_log(EMAIL_RESET_SENT, SUCCESS,
           info=Baseline reset email sent to morris.nkomo@fnb.co.za for cycle &cycle_id.);

%mend send_baseline_email;


/* --- 2. Cycle-over-cycle comparison email --- */
%macro send_comparison_email;

  %let motor_new_claims_fmt = %sysfunc(putn(&baseline_claims.,    comma10.));
  %let motor_new_ocr_fmt    = %sysfunc(putn(&baseline_ocr.,       comma18.2));
  %let nm_new_claims_fmt    = %sysfunc(putn(&nm_baseline_claims., comma10.));
  %let nm_new_ocr_fmt       = %sysfunc(putn(&nm_baseline_ocr.,    comma18.2));

  %local motor_prev_claims_fmt motor_prev_ocr_fmt motor_prev_pct_fmt;
  %local nm_prev_claims_fmt    nm_prev_ocr_fmt    nm_prev_pct_fmt;
  %local motor_claims_delta    motor_ocr_delta;
  %local nm_claims_delta       nm_ocr_delta;
  %local motor_claims_arrow    motor_ocr_arrow;
  %local nm_claims_arrow       nm_ocr_arrow;

  %if %str(&prev_cycle_id.) = %str(N/A) %then %do;
    %let motor_prev_claims_fmt = N/A (first cycle);
    %let motor_prev_ocr_fmt    = N/A;
    %let motor_prev_pct_fmt    = N/A;
    %let motor_claims_delta    = N/A;
    %let motor_ocr_delta       = N/A;
    %let motor_claims_arrow    =;
    %let motor_ocr_arrow       =;
  %end;
  %else %do;
    %let motor_prev_claims_fmt =
      %sysfunc(putn(&prev_close_claims., comma10.));
    %let motor_prev_ocr_fmt    =
      %sysfunc(putn(&prev_close_ocr.,    comma18.2));
    %let motor_prev_pct_fmt    =
      %sysfunc(putn(%sysevalf(&prev_pct_closed.*100), 8.1));

    %let _mdelta = %sysevalf(&baseline_claims. - &prev_close_claims.);
    %let motor_claims_delta = %sysfunc(putn(&_mdelta., comma10.));
    %if %sysevalf(&_mdelta. > 0) %then %let motor_claims_arrow = [+] More claims this cycle;
    %else %if %sysevalf(&_mdelta. < 0) %then %let motor_claims_arrow = [-] Fewer claims this cycle;
    %else %let motor_claims_arrow = [=] No change;

    %let _modelta = %sysevalf(&baseline_ocr. - &prev_close_ocr.);
    %let motor_ocr_delta = %sysfunc(putn(&_modelta., comma18.2));
    %if %sysevalf(&_modelta. > 0) %then %let motor_ocr_arrow = [+] Higher OCR this cycle;
    %else %if %sysevalf(&_modelta. < 0) %then %let motor_ocr_arrow = [-] Lower OCR this cycle;
    %else %let motor_ocr_arrow = [=] No change;
  %end;

  %if %str(&nm_prev_cycle_id.) = %str(N/A) %then %do;
    %let nm_prev_claims_fmt = N/A (first cycle);
    %let nm_prev_ocr_fmt    = N/A;
    %let nm_prev_pct_fmt    = N/A;
    %let nm_claims_delta    = N/A;
    %let nm_ocr_delta       = N/A;
    %let nm_claims_arrow    =;
    %let nm_ocr_arrow       =;
  %end;
  %else %do;
    %let nm_prev_claims_fmt =
      %sysfunc(putn(&nm_prev_close_claims., comma10.));
    %let nm_prev_ocr_fmt    =
      %sysfunc(putn(&nm_prev_close_ocr.,    comma18.2));
    %let nm_prev_pct_fmt    =
      %sysfunc(putn(%sysevalf(&nm_prev_pct_closed.*100), 8.1));

    %let _nmdelta = %sysevalf(&nm_baseline_claims. - &nm_prev_close_claims.);
    %let nm_claims_delta = %sysfunc(putn(&_nmdelta., comma10.));
    %if %sysevalf(&_nmdelta. > 0) %then %let nm_claims_arrow = [+] More claims this cycle;
    %else %if %sysevalf(&_nmdelta. < 0) %then %let nm_claims_arrow = [-] Fewer claims this cycle;
    %else %let nm_claims_arrow = [=] No change;

    %let _nmodelta = %sysevalf(&nm_baseline_ocr. - &nm_prev_close_ocr.);
    %let nm_ocr_delta = %sysfunc(putn(&_nmodelta., comma18.2));
    %if %sysevalf(&_nmodelta. > 0) %then %let nm_ocr_arrow = [+] Higher OCR this cycle;
    %else %if %sysevalf(&_nmodelta. < 0) %then %let nm_ocr_arrow = [-] Lower OCR this cycle;
    %else %let nm_ocr_arrow = [=] No change;
  %end;

  filename cmp_outbx email;

  data _null_;
    file cmp_outbx
      to      = ("morris.nkomo@fnb.co.za")
      cc      = ("asher.levin@fnb.co.za" "Webster.khoza@fnb.co.za")
      from    = ("Morris.Nkomo@fnb.co.za")
      subject = "OCR Cycle Comparison -- &prev_cycle_id. vs &cycle_id. (&rd_fmt.)";
    put "I hope you're well.";
    put " ";
    put "Please find below the month-on-month opening position comparison for";
    put "Cycle &cycle_id. vs the closing position of Cycle &prev_cycle_id..";
    put " ";
    put "A higher opening claims count or OCR amount means we are starting";
    put "this cycle in a worse position than last month closed.";
    put " ";
    put "===============================";
    put "MOTOR (Retail)";
    put "===============================";
    put " ";
    put "                     Prev Close     New Baseline    Change";
    put "                     ----------     ------------    ------";
    put "  Open claims:       &motor_prev_claims_fmt.   &motor_new_claims_fmt.   &motor_claims_delta.";
    put "  OCR amount (R):    &motor_prev_ocr_fmt.   &motor_new_ocr_fmt.   &motor_ocr_delta.";
    put "  % closed (prev):   &motor_prev_pct_fmt.%";
    put " ";
    put "  &motor_claims_arrow.";
    put "  &motor_ocr_arrow.";
    put " ";
    put "===============================";
    put "NON-MOTOR (Retail)";
    put "===============================";
    put " ";
    put "                     Prev Close     New Baseline    Change";
    put "                     ----------     ------------    ------";
    put "  Open claims:       &nm_prev_claims_fmt.   &nm_new_claims_fmt.   &nm_claims_delta.";
    put "  OCR amount (R):    &nm_prev_ocr_fmt.   &nm_new_ocr_fmt.   &nm_ocr_delta.";
    put "  % closed (prev):   &nm_prev_pct_fmt.%";
    put " ";
    put "  &nm_claims_arrow.";
    put "  &nm_ocr_arrow.";
    put " ";
    put "===============================";
    put " ";
    put "Kind regards";
    put "Morris";
  run;

  %put NOTE: Cycle comparison email sent — &prev_cycle_id. vs &cycle_id.;
  %ocr_log(EMAIL_COMPARISON_SENT, SUCCESS,
           info=Comparison email sent prev=&prev_cycle_id. new=&cycle_id.);

%mend send_comparison_email;


/*==============================================================
  MOTOR BASELINE
==============================================================*/
%macro run_motor_baseline;

  /*--- Auto-close previous Motor cycle ---*/
  proc sql noprint;
    select CycleID into :prev_cycle_id trimmed
    from STI_WER.OCR_Cycle_Control
    where Status = 'ACTIVE'
    order by BaselineDate desc;
  quit;

  %if &sqlobs. > 0 %then %do;
    proc sql noprint;
      update STI_WER.OCR_Cycle_Control
      set Status    = 'CLOSED',
          UpdatedAt = today()
      where Status = 'ACTIVE';
    quit;
    %put NOTE: Previous Motor cycle &prev_cycle_id. auto-closed.;
    %ocr_log(CLOSE_PREV_CYCLE, SUCCESS,
             info=Motor CycleID &prev_cycle_id. auto-closed before opening &cycle_id.);
  %end;
  %else %do;
    %put NOTE: No active Motor cycle to close — may be first run.;
  %end;

  /*--- Re-run guard ---*/
  proc sql noprint;
    select count(*) into :cycle_exists trimmed
    from STI_WER.OCR_Cycle_Control
    where CycleID = "&cycle_id.";
  quit;

  %if &cycle_exists. > 0 %then %do;
    %put WARNING: Motor CycleID=&cycle_id. already exists — baseline insert skipped.;
    %ocr_log(BASELINE_SKIP, WARNING,
             info=Motor CycleID &cycle_id. already active - baseline insert skipped);
    %let motor_success = 1;
    %return;
  %end;

  /*--- Refresh Investigate_Claims (monthly snapshot) ---*/
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
      DROP TABLE IF EXISTS FNB_STI_Analytics.Claims.Investigate_Claims;

      SELECT
          ClaimCode,
          SubClaimCode,
          ProductTypeSplit,
          Division,
          ReportMonth,
          Estimate_OCR,
          Total_Paid_ExVAT,
          ClaimHandler,
          GETDATE() AS RunDate
      INTO FNB_STI_Analytics.Claims.Investigate_Claims
      FROM FNB_STI_Analytics.Claims.vw_OCR_Claim_Age
      WHERE Investigate_Flag = 'Investigate'
      ORDER BY ReportMonth DESC;
    ) by sqlsvr;

    disconnect from sqlsvr;
  quit;

  %put NOTE: Investigate_Claims refreshed.;
  %ocr_log(EXTRACT_INVESTIGATE, SUCCESS);

  /*--- Count Motor + Retail baseline claims ---*/
  proc sql noprint;
    select count(distinct ClaimCode) into :baseline_claims trimmed
    from STI_WER.Investigate_Claims
    where upcase(strip(ProductTypeSplit)) = 'MOTOR'
      and upcase(strip(Division))         = 'RETAIL';
  quit;

  %put NOTE: Motor baseline claim count = &baseline_claims.;

  /*--- Motor baseline OCR total ---*/
  proc sql noprint;
    select sum(coalesce(a.Total_Estimate_OCR_ExVAT, 0))
    into :baseline_ocr trimmed
    from STI_WER.Investigate_Claims c
    left join STI_WER.vw_OpsClaimsReport a
        on c.SubClaimCode = a.SubClaimCode
    where upcase(strip(c.ProductTypeSplit)) = 'MOTOR'
      and upcase(strip(c.Division))         = 'RETAIL'
      and coalesce(a.Total_Estimate_OCR_ExVAT, 0) > 0;
  quit;

  %let baseline_ocr_fmt = %sysfunc(putn(&baseline_ocr., comma18.2));
  %put NOTE: Motor baseline OCR amount = &baseline_ocr.;
  %ocr_log(CALC_BASELINE, SUCCESS, records=&baseline_claims., metric=&baseline_ocr.);

  /*--- Open Motor cycle in OCR_Cycle_Control ---*/
  /*
    FIX 2: BaselineDate uses SAS date literal syntax — "&rd_fmt."d
    This tells SAS/ODBC to pass a typed DATE value to SQL Server
    rather than a plain integer, which SQL Server cannot implicitly
    cast to a date column and silently converts to NULL.
    &rd_fmt. resolves to e.g. 16APR2026, making the literal '16APR2026'd
  */
  proc sql noprint;
    insert into STI_WER.OCR_Cycle_Control
      (CycleID, BaselineDate, BaselineClaims, BaselineOCR, Status)
    values (
      "&cycle_id.",
      "&rd_fmt."d,
      &baseline_claims.,
      &baseline_ocr.,
      'ACTIVE'
    );
  quit;

  %if &sqlrc. ne 0 %then %do;
    %ocr_log(OPEN_CYCLE, FAILED,
             error=INSERT into OCR_Cycle_Control failed SQLRC=&sqlrc.);
    %put ERROR: Motor INSERT into OCR_Cycle_Control failed.;
    %abort cancel;
  %end;

  %put NOTE: Motor cycle &cycle_id. opened in OCR_Cycle_Control.;
  %ocr_log(OPEN_CYCLE, SUCCESS, info=Motor CycleID &cycle_id. status=ACTIVE);

  /*--- Insert Motor Baseline row (WeekSequence=0) ---*/
  proc sql noprint;
    insert into STI_WER.OCR_Weekly_Tracker
      (CycleID, WeekSequence, WeekLabel, RunDate,
       Baseline_Claims, Open_Claims, Current_OCR_Amt,
       Cumul_Closed, Closed_This_Week, OCR_Reduced_This_Week, Pct_Claims_Closed)
    values (
      "&cycle_id.",
      0,
      'Baseline',
      "&rd_fmt."d,
      &baseline_claims.,
      &baseline_claims.,
      &baseline_ocr.,
      0, 0, 0, 0.0
    );
  quit;

  %if &sqlrc. ne 0 %then %do;
    %ocr_log(INSERT_BASELINE, FAILED,
             error=INSERT into OCR_Weekly_Tracker failed SQLRC=&sqlrc.);
    %put ERROR: Motor INSERT into OCR_Weekly_Tracker failed.;
    %abort cancel;
  %end;

  %put NOTE: Motor Baseline row (WeekSequence=0) inserted for CycleID=&cycle_id..;
  %ocr_log(INSERT_BASELINE, SUCCESS, records=&baseline_claims., metric=&baseline_ocr.);

  %let motor_success = 1;

%mend run_motor_baseline;

%run_motor_baseline;


/*==============================================================
  NON-MOTOR BASELINE
==============================================================*/
%macro run_nm_baseline;

  /*--- Auto-close previous Non-Motor cycle ---*/
  proc sql noprint;
    select CycleID into :nm_prev_cycle_id trimmed
    from STI_WER.NM_Cycle_Control
    where Status = 'ACTIVE'
    order by BaselineDate desc;
  quit;

  %if &sqlobs. > 0 %then %do;
    proc sql noprint;
      update STI_WER.NM_Cycle_Control
      set Status    = 'CLOSED',
          UpdatedAt = today()
      where Status = 'ACTIVE';
    quit;
    %put NOTE: Previous Non-Motor cycle &nm_prev_cycle_id. auto-closed.;
    %ocr_log(NM_CLOSE_PREV_CYCLE, SUCCESS,
             info=NM CycleID &nm_prev_cycle_id. auto-closed before opening &cycle_id.);
  %end;
  %else %do;
    %put NOTE: No active Non-Motor cycle to close — may be first run.;
  %end;

  /*--- Re-run guard ---*/
  proc sql noprint;
    select count(*) into :nm_cycle_exists trimmed
    from STI_WER.NM_Cycle_Control
    where CycleID = "&cycle_id.";
  quit;

  %if &nm_cycle_exists. > 0 %then %do;
    %put WARNING: Non-Motor CycleID=&cycle_id. already exists — baseline insert skipped.;
    %ocr_log(NM_BASELINE_SKIP, WARNING,
             info=NM CycleID &cycle_id. already active - baseline insert skipped);
    %let nm_success = 1;
    %return;
  %end;

  /*--- Count Non-Motor + Retail baseline claims ---*/
  proc sql noprint;
    select count(distinct ClaimCode) into :nm_baseline_claims trimmed
    from STI_WER.Investigate_Claims
    where upcase(strip(ProductTypeSplit)) ne 'MOTOR'
      and upcase(strip(Division))         = 'RETAIL';
  quit;

  %put NOTE: Non-Motor baseline claim count = &nm_baseline_claims.;

  /*--- Non-Motor baseline OCR total ---*/
  proc sql noprint;
    select sum(coalesce(a.Total_Estimate_OCR_ExVAT, 0))
    into :nm_baseline_ocr trimmed
    from STI_WER.Investigate_Claims c
    left join STI_WER.vw_OpsClaimsReport a
        on c.SubClaimCode = a.SubClaimCode
    where upcase(strip(c.ProductTypeSplit)) ne 'MOTOR'
      and upcase(strip(c.Division))         = 'RETAIL'
      and coalesce(a.Total_Estimate_OCR_ExVAT, 0) > 0;
  quit;

  %let nm_baseline_ocr_fmt = %sysfunc(putn(&nm_baseline_ocr., comma18.2));
  %put NOTE: Non-Motor baseline OCR amount = &nm_baseline_ocr.;
  %ocr_log(NM_CALC_BASELINE, SUCCESS, records=&nm_baseline_claims., metric=&nm_baseline_ocr.);

  /*--- Open Non-Motor cycle in NM_Cycle_Control ---*/
  /*
    FIX 2 (NM): Same date literal fix as Motor above.
  */
  proc sql noprint;
    insert into STI_WER.NM_Cycle_Control
      (CycleID, BaselineDate, BaselineClaims, BaselineOCR, Status)
    values (
      "&cycle_id.",
      "&rd_fmt."d,
      &nm_baseline_claims.,
      &nm_baseline_ocr.,
      'ACTIVE'
    );
  quit;

  %if &sqlrc. ne 0 %then %do;
    %ocr_log(NM_OPEN_CYCLE, FAILED,
             error=INSERT into NM_Cycle_Control failed SQLRC=&sqlrc.);
    %put ERROR: Non-Motor INSERT into NM_Cycle_Control failed.;
    %abort cancel;
  %end;

  %put NOTE: Non-Motor cycle &cycle_id. opened in NM_Cycle_Control.;
  %ocr_log(NM_OPEN_CYCLE, SUCCESS, info=NM CycleID &cycle_id. status=ACTIVE);

  /*--- Insert Non-Motor Baseline row (WeekSequence=0) ---*/
  proc sql noprint;
    insert into STI_WER.NM_Weekly_Tracker
      (CycleID, WeekSequence, WeekLabel, RunDate,
       Baseline_Claims, Open_Claims, Current_OCR_Amt,
       Cumul_Closed, Closed_This_Week, OCR_Reduced_This_Week, Pct_Claims_Closed)
    values (
      "&cycle_id.",
      0,
      'Baseline',
      "&rd_fmt."d,
      &nm_baseline_claims.,
      &nm_baseline_claims.,
      &nm_baseline_ocr.,
      0, 0, 0, 0.0
    );
  quit;

  %if &sqlrc. ne 0 %then %do;
    %ocr_log(NM_INSERT_BASELINE, FAILED,
             error=INSERT into NM_Weekly_Tracker failed SQLRC=&sqlrc.);
    %put ERROR: Non-Motor INSERT into NM_Weekly_Tracker failed.;
    %abort cancel;
  %end;

  %put NOTE: Non-Motor Baseline row (WeekSequence=0) inserted for CycleID=&cycle_id..;
  %ocr_log(NM_INSERT_BASELINE, SUCCESS,
           records=&nm_baseline_claims., metric=&nm_baseline_ocr.);

  %let nm_success = 1;

%mend run_nm_baseline;

%run_nm_baseline;


%global baseline_ocr_fmt nm_baseline_ocr_fmt;

/*==============================================================
  SEND EMAILS
  Both only fire when motor_success=1 AND nm_success=1.
==============================================================*/
%if &motor_success. = 1 and &nm_success. = 1 %then %do;
  %send_baseline_email;
  %send_comparison_email;
%end;
%else %do;
  %put WARNING: One or both baselines did not complete — emails suppressed.;
  %ocr_log(EMAIL_SUPPRESSED, WARNING,
           info=Motor=&motor_success. NM=&nm_success. emails not sent);
%end;

%ocr_log(BASELINE_END, COMPLETED, info=Cycle &cycle_id. baseline finished);
