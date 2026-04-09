/*==============================================================
  FILE: OCR_02_Baseline.sas
  PURPOSE: Runs on the 16th of each month.
           1. Refreshes Investigate_Claims (existing logic).
           2. Counts baseline Motor + Retail claims and OCR.
           3. Opens a new cycle in OCR_Cycle_Control.
           4. Inserts the Baseline row (WeekSequence=0) into
              OCR_Weekly_Tracker.

  DESIGN PRINCIPLES:
    - No hardcoding. CycleID is always derived from today's date.
    - No deletes. Every historical row is preserved forever.
    - Re-run safety: guarded by a check against Cycle_Control.
      If this cycle already exists as ACTIVE, the baseline step
      is skipped (only Investigate_Claims is refreshed).

  CHANGES:
    Bug 3 fixed   — date informat changed from yymmdd8. to
                    yymmddN8. to correctly parse packed YYYYMMDD
                    strings (e.g. 20260316) that have no
                    delimiters. yymmdd8. expects dashes or slashes.
    Auto-close    — the previous ACTIVE cycle is now automatically
                    closed at the start of each baseline run, before
                    the new cycle is opened. No manual close-off step
                    or separate file is needed. The cycle boundary is
                    always the 16th, regardless of how many weekly
                    runs occurred.

  SCHEDULE: 16th of every month — run BEFORE OCR_03_Weekly.sas.
==============================================================*/

/*--------------------------------------------------------------
  1. Libname
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
  2. Derive run date and CycleID dynamically — no hardcoding.
     rd       = today in YYYYMMDD (used for filenames / dates).
     cycle_id = YYYYMM of today (= the new cycle being opened).
--------------------------------------------------------------*/
%if not %symexist(rd) %then %do;
  %let rd = %sysfunc(today(), yymmddn8.);
%end;

%let cycle_id = %sysfunc(substr(&rd., 1, 6));  /* YYYYMM from YYYYMMDD */

%put NOTE: Run date = &rd.;
%put NOTE: Cycle ID = &cycle_id.;

%ocr_log(BASELINE_START, STARTED,
         info=Cycle &cycle_id. baseline initiated);

/*--------------------------------------------------------------
  3. Auto-close the previous active cycle.
     The cycle boundary is always the 16th. Whatever cycle was
     ACTIVE (however many weeks it ran) is closed here before
     the new one opens. This replaces any manual close-off step.
     Safe to re-run — if no ACTIVE cycle exists (e.g. first ever
     run, or already closed) the UPDATE affects 0 rows and the
     job continues normally.
--------------------------------------------------------------*/
proc sql noprint;
  select CycleID
  into :prev_cycle_id trimmed
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

  %put NOTE: Previous cycle &prev_cycle_id. automatically closed.;
  %ocr_log(CLOSE_PREV_CYCLE, SUCCESS,
           info=CycleID &prev_cycle_id. auto-closed before opening &cycle_id.);
%end;
%else %do;
  %put NOTE: No active cycle found to close — this may be the first baseline run.;
%end;

/*--------------------------------------------------------------
  4. Refresh Investigate_Claims (monthly snapshot).
     This always runs regardless of whether the baseline row
     already exists — the view is a dependency for the weekly
     jobs and should always reflect the current 16th-of-month
     extract.
     Note: runs AFTER auto-close so the new snapshot is always
     associated with the incoming cycle, not the closed one.
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

/*--------------------------------------------------------------
  5. Re-run guard — check whether this cycle is already in
     OCR_Cycle_Control. If the row exists and is ACTIVE, it
     means the baseline was already captured for this month.
     We log a warning and skip the insert steps to protect the
     existing baseline data.
--------------------------------------------------------------*/
%macro run_baseline;

  proc sql noprint;
    select count(*)
    into :cycle_exists trimmed
    from STI_WER.OCR_Cycle_Control
    where CycleID = "&cycle_id.";
  quit;

  %if &cycle_exists. > 0 %then %do;
    %put WARNING: CycleID=&cycle_id. already exists in OCR_Cycle_Control.;
    %put WARNING: Baseline insert skipped — Investigate_Claims has been refreshed.;
    %put WARNING: If a re-baseline is genuinely needed, close the existing cycle first.;
    %ocr_log(BASELINE_SKIP, WARNING,
             info=CycleID &cycle_id. already active - baseline insert skipped);
    %return;
  %end;

  /*------------------------------------------------------------
    6. Count baseline Motor + Retail claims.
  ------------------------------------------------------------*/
  proc sql noprint;
    select count(distinct ClaimCode)
    into :baseline_claims trimmed
    from STI_WER.Investigate_Claims
    where upcase(strip(ProductTypeSplit)) = 'MOTOR'
      and upcase(strip(Division))         = 'RETAIL';
  quit;

  %put NOTE: Baseline claim count = &baseline_claims.;

  /*------------------------------------------------------------
    7. Get baseline OCR total (from live view, same as claims).
  ------------------------------------------------------------*/
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

  %put NOTE: Baseline OCR amount = &baseline_ocr.;

  %ocr_log(CALC_BASELINE, SUCCESS,
           records=&baseline_claims.,
           metric=&baseline_ocr.);

  /*------------------------------------------------------------
    8. Open this cycle in OCR_Cycle_Control.
       This is the authoritative record of what the baseline
       values were — the weekly job reads from here, not from
       macro variables, so nothing ever needs to be hardcoded.
  ------------------------------------------------------------*/

  /* Bug 3 fix: yymmddN8. correctly parses packed YYYYMMDD    */
  /* strings with no delimiters. yymmdd8. expects dashes or   */
  /* slashes (e.g. 2026-03-16) and may silently misparse.     */
  %let sas_rd = %sysfunc(inputn(&rd., yymmddN8.));

  proc sql noprint;
    insert into STI_WER.OCR_Cycle_Control
      (CycleID, BaselineDate, BaselineClaims, BaselineOCR, Status)
    values (
      "&cycle_id.",
      &sas_rd.,
      &baseline_claims.,
      &baseline_ocr.,
      'ACTIVE'
    );
  quit;

  %if &sqlrc. ne 0 %then %do;
    %ocr_log(OPEN_CYCLE, FAILED,
             error=INSERT into OCR_Cycle_Control failed SQLRC=&sqlrc.);
    %put ERROR: INSERT into OCR_Cycle_Control failed. SQLRC=&sqlrc.. Aborting.;
    %abort cancel;
  %end;

  %put NOTE: Cycle &cycle_id. opened in OCR_Cycle_Control.;
  %ocr_log(OPEN_CYCLE, SUCCESS, info=CycleID &cycle_id. status=ACTIVE);

  /*------------------------------------------------------------
    9. Insert Baseline row (WeekSequence=0) into tracker.
       No DELETE before this — history is never touched.
       The UNIQUE constraint on (CycleID, WeekSequence) prevents
       accidental duplicates at the database level.
  ------------------------------------------------------------*/
  proc sql noprint;
    insert into STI_WER.OCR_Weekly_Tracker
      (CycleID, WeekSequence, WeekLabel, RunDate,
       Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    values (
      "&cycle_id.",
      0,
      'Baseline',
      &sas_rd.,
      &baseline_claims.,
      &baseline_claims.,   /* on baseline, open = baseline total */
      &baseline_ocr.,
      0,                   /* nothing closed yet */
      0,                   /* nothing closed yet */
      0,                   /* no OCR reduction yet */
      0.0                  /* 0% closed */
    );
  quit;

  %if &sqlrc. ne 0 %then %do;
    %ocr_log(INSERT_BASELINE, FAILED,
             error=INSERT into OCR_Weekly_Tracker failed SQLRC=&sqlrc.);
    %put ERROR: INSERT into OCR_Weekly_Tracker failed. SQLRC=&sqlrc.. Aborting.;
    %abort cancel;
  %end;

  %put NOTE: Baseline row (WeekSequence=0) inserted for CycleID=&cycle_id..;
  %ocr_log(INSERT_BASELINE, SUCCESS,
           records=&baseline_claims.,
           metric=&baseline_ocr.);

%mend run_baseline;

%run_baseline;
