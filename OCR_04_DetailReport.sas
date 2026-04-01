/*==============================================================
  FILE: OCR_04_DetailReport.sas
  PURPOSE: Ad hoc — pull the current claims detail list
           without updating the tracker. Safe to run any time.
  SCHEDULE: On demand only. Not scheduled.
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
  3. Pull claims
--------------------------------------------------------------*/
data work.snapshot;
  set STI_WER.Investigate_Claims(
    keep= ClaimCode SubClaimCode ReportMonth
          Estimate_OCR ProductTypeSplit Division ClaimHandler
  );
  if upcase(strip(ProductTypeSplit)) ne 'MOTOR'  then delete;
  if upcase(strip(Division))         ne 'RETAIL' then delete;
run;

data work.current_est;
  set STI_WER.vw_OpsClaimsReport(
    keep= SubClaimCode Total_Estimate_OCR_ExVAT
  );
run;

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
  4. Export
--------------------------------------------------------------*/
%let outfile = /data/fnbinsurance/Short_Term/Monitoring/MotorClaims_AdHoc_&rd..xlsx;

ods excel file="&outfile."
  options(sheet_name="Claims Detail" autofilter="yes" frozen_headers="yes");
  title "Motor Retail Claims — Ad Hoc Pull — &rd.";
  proc print data=work.MotorClaims_Final noobs label;
    format Estimate_OCR_When_Flagged
           Current_Estimate_OCR
           OCR_Movement           comma18.2;
  run;
ods excel close;
title;

%put NOTE: Ad hoc report written to &outfile.;
