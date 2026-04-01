/*==============================================================
  FILE: OCR_02_Baseline.sas
  PURPOSE: Runs on the 16th of each month.
           1. Drops and recreates Investigate_Claims (existing logic)
           2. Inserts the Baseline row into OCR_Weekly_Tracker
  SCHEDULE: 16th of every month — run BEFORE OCR_03_Weekly.sas
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
  2. Run date
--------------------------------------------------------------*/
%if not %symexist(rd) %then %do;
  %let rd = %sysfunc(today(), yymmddn8.);
%end;

/*--------------------------------------------------------------
  3. Recreate Investigate_Claims (your existing monthly logic)
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

%put NOTE: Investigate_Claims refreshed successfully.;

/*--------------------------------------------------------------
  4. Count baseline Motor + Retail claims
--------------------------------------------------------------*/
proc sql noprint;
  select count(distinct ClaimCode)
  into :baseline_claims trimmed
  from STI_WER.Investigate_Claims
  where upcase(strip(ProductTypeSplit)) = 'MOTOR'
    and upcase(strip(Division))         = 'RETAIL';
quit;

%put NOTE: Baseline claim count = &baseline_claims.;

/*--------------------------------------------------------------
  5. Get baseline OCR total
     Join to vw_OpsClaimsReport for current estimates
     (on the 16th, current = baseline since just refreshed)
--------------------------------------------------------------*/
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

/*--------------------------------------------------------------
  6. Insert Baseline row into tracker
     Clear any existing rows for this month first to avoid
     duplicates if the job is re-run on the 16th.
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

  /* Remove any rows already inserted this month (safe re-run) */
  execute (
    DELETE FROM FNB_STI_Analytics.Claims.OCR_Weekly_Tracker
    WHERE YEAR(RunDate)  = YEAR(GETDATE())
      AND MONTH(RunDate) = MONTH(GETDATE());
  ) by sqlsvr;

  /* Insert baseline */
  execute (
    INSERT INTO FNB_STI_Analytics.Claims.OCR_Weekly_Tracker
      (WeekLabel, RunDate, Baseline_Claims, Open_Claims,
       Current_OCR_Amt, Cumul_Closed, Closed_This_Week,
       OCR_Reduced_This_Week, Pct_Claims_Closed)
    VALUES (
      'Baseline',
      CAST(GETDATE() AS DATE),
      %unquote(&baseline_claims.),
      %unquote(&baseline_claims.),   /* on baseline, open = baseline */
      %unquote(&baseline_ocr.),
      0,     /* nothing closed yet */
      0,     /* nothing closed yet */
      0,     /* no OCR reduction yet */
      0.0    /* 0% closed */
    )
  ) by sqlsvr;

  disconnect from sqlsvr;
quit;

%put NOTE: Baseline row inserted into OCR_Weekly_Tracker.;
