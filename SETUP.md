/*==========================================================
  1. Environment & Libname Setup
==========================================================*/
%include "/data/fnbins/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Automation/STI_CA_2/Libnames.sas";

%macro logging(libname,database,schema,server);
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
%logging(STI_OPS, FNB_STI_Analytics, Claims, LFE-RBPREATLDB1);  /* for vw_OpsClaimsReport */

/*==========================================================
  2. Run Date (YYYYMMDD)
==========================================================*/
%if not %symexist(rd) %then %do;
  %let rd = %sysfunc(today(), yymmddn8.);
%end;

/*==========================================================
  3. Pull current OCR from vw_OpsClaimsReport
     Used to derive Paid_Off_Ind (= 1 when Current_Estimate_OCR = 0)
==========================================================*/
data work.OpsOCR;
  set STI_OPS.vw_OpsClaimsReport(
    keep=
      ClaimCode
      Total_Estimate_OCR_ExVAT
  );
  /* Derive Paid_Off_Ind to match Excel dashboard logic */
  if round(Total_Estimate_OCR_ExVAT, 0.01) = 0 then Paid_Off_Ind = 1;
  else Paid_Off_Ind = 0;

  keep ClaimCode Paid_Off_Ind;
run;

/*==========================================================
  4. Motor + Retail + Unpaid Claims
     Join Investigate_Claims to OpsOCR and filter Paid_Off_Ind = 0
==========================================================*/
proc sql;
  create table work.MotorClaims_Final as
  select
    a.ClaimCode,
    a.ReportMonth,
    a.ProductTypeSplit,
    a.Total_Paid_ExVAT,
    a.Estimate_OCR,
    a.ClaimHandler
  from STI_WER.Investigate_Claims a
  inner join work.OpsOCR b
    on a.ClaimCode = b.ClaimCode
  where upcase(strip(a.ProductTypeSplit)) = 'MOTOR'
    and upcase(a.Division)               = 'RETAIL'
    and b.Paid_Off_Ind                   = 0   /* exclude paid-off claims */
  ;
quit;

/*==========================================================
  5. Export Motor Claims Excel
==========================================================*/
proc export data=work.MotorClaims_Final
  outfile="/data/fnbinsurance/Short_Term/Monitoring/MotorClaimsPaid&rd..xlsx"
  dbms=xlsx
  replace;
  sheet="Motor_Claims";
run;

/*==========================================================
  6. Email – Motor Claims ONLY
==========================================================*/
filename outbox email;
data _null_;
  file outbox
    to     = ("morris.nkomo@fnb.co.za")
    from   = ("FNB ST Analytics <fnbst-analytics@fnb.co.za>")
    subject= "Daily Motor Claims – Retail (Under Investigation)"
    attach = (
      "/data/fnbinsurance/Short_Term/Monitoring/MotorClaimsPaid&rd..xlsx"
      content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    );
  put "Good morning Morris,";
  put;
  put "Please find attached the Motor Retail claims still under investigation.";
  put;
  put "Filters applied:";
  put "- Product Type: Motor";
  put "- Division: Retail";
  put "- Paid Off Indicator = 0 (Current Estimate OCR > 0)";
  put;
  put "Columns included:";
  put "- Claim Code";
  put "- Report Month";
  put "- Total Paid (Ex VAT)";
  put "- Estimated OCR";
  put "- Claim Handler";
  put;
  put "Regards,";
  put "FNB ST Analytics";
run;
