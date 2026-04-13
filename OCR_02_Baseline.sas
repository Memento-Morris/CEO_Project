/*==============================================================
  FILE: OCR_02_Baseline.sas
  PURPOSE: Runs on the 16th of each month. Handles both Motor
           and Non-Motor baselines in one file.
           1. Refreshes Investigate_Claims.
           2. Auto-closes the previous ACTIVE cycle for each tracker.
           3. Counts baseline claims and OCR for each portfolio.
           4. Opens a new cycle and inserts WeekSequence=0 rows.

  SCHEDULE: 16th of every month — run BEFORE OCR_03_Weekly.sas.
==============================================================*/

/*--------------------------------------------------------------
  Libname
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
  Derive run date and CycleID — no hardcoding.
--------------------------------------------------------------*/
%if not %symexist(rd) %then %do;
  %let rd = %sysfunc(today(), yymmddn8.);
%end;

%let cycle_id = %sysfunc(substr(&rd., 1, 6));
%let sas_rd   = %sysfunc(inputn(&rd., yymmddN8.));

%put NOTE: Run date = &rd.;
%put NOTE: Cycle ID = &cycle_id.;

%ocr_log(BASELINE_START, STARTED, info=Cycle &cycle_id. baseline initiated);

/*--------------------------------------------------------------
  Refresh Investigate_Claims (monthly snapshot).
  Always runs first — both Motor and Non-Motor depend on it.
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
      set Status = 'CLOSED', UpdatedAt = today()
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
    %return;
  %end;

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

  %put NOTE: Motor baseline OCR amount = &baseline_ocr.;
  %ocr_log(CALC_BASELINE, SUCCESS, records=&baseline_claims., metric=&baseline_ocr.);

  /*--- Open Motor cycle in OCR_Cycle_Control ---*/
  proc sql noprint;
    insert into STI_WER.OCR_Cycle_Control
      (CycleID, BaselineDate, BaselineClaims, BaselineOCR, Status)
    values ("&cycle_id.", &sas_rd., &baseline_claims., &baseline_ocr., 'ACTIVE');
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
      "&cycle_id.", 0, 'Baseline', &sas_rd.,
      &baseline_claims., &baseline_claims., &baseline_ocr.,
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

%mend run_motor_baseline;

%run_motor_baseline;


/*==============================================================
  NON-MOTOR BASELINE
  Uses NM_Cycle_Control and NM_Weekly_Tracker.
  Filter: ProductTypeSplit ne 'MOTOR' (all non-motor types),
          Division = 'RETAIL'.
  Adjust the Division filter below if Non-Motor uses a
  different division value in your data.
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
      set Status = 'CLOSED', UpdatedAt = today()
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

  %put NOTE: Non-Motor baseline OCR amount = &nm_baseline_ocr.;
  %ocr_log(NM_CALC_BASELINE, SUCCESS, records=&nm_baseline_claims., metric=&nm_baseline_ocr.);

  /*--- Open Non-Motor cycle in NM_Cycle_Control ---*/
  proc sql noprint;
    insert into STI_WER.NM_Cycle_Control
      (CycleID, BaselineDate, BaselineClaims, BaselineOCR, Status)
    values ("&cycle_id.", &sas_rd., &nm_baseline_claims., &nm_baseline_ocr., 'ACTIVE');
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
      "&cycle_id.", 0, 'Baseline', &sas_rd.,
      &nm_baseline_claims., &nm_baseline_claims., &nm_baseline_ocr.,
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

%mend run_nm_baseline;

%run_nm_baseline;
