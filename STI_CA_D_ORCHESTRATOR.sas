/* ============================================================
   JOB:      STI_CA_D_ORCHESTRATOR
   STATUS:   PROD
   PURPOSE:  Daily Campaign Drop Orchestrator
             Reads approved redrop requests from SharePoint,
             resolves each to its campaign SAS file by name,
             injects run parameters, and fires %include.
             Morris is not involved after initial file build.
   ============================================================

   SCHEDULE: Daily - runs AFTER STI_CA_D_APNS_DATA completes
             so the lead status table is always fresh.

   HOW IT WORKS:
     1. Reads REDROP_REQUESTS.xlsx from SharePoint
     2. Reads APPROVERS sheet - validates who can approve
     3. For each Pending + approved request:
          a. Constructs file path:
             &base_path. + campaign_code + "_DROP.sas"
          b. Checks file exists
          c. Sets macro parameters:
             &run_mode.    = REDROP
             &drop_date.   = original drop date from request
             &request_id.  = request ID for output labelling
             &product_code = product code from request
             &campaign_code= campaign code from request
          d. %include the campaign file - it runs in full
          e. Logs outcome, updates request status
     4. Sends tiered notification emails
     5. Appends audit log

   WHAT YOU DO PER CAMPAIGN (one time only):
     1. Build CMAxxxxx_DROP.sas using the template
     2. Drop it in &base_path.
     3. Done. Orchestrator finds it automatically.

   CONVENTIONS ENFORCED:
     - Campaign files named:  CMAxxxxx_DROP.sas
     - All files in one folder: &base_path.
     - Campaign files must accept these macro variables:
         &run_mode.     INITIAL or REDROP
         &drop_date.    SAS date value (e.g. 01APR2026)
         &request_id.   request identifier string
         &product_code. product code for this drop
         &campaign_code campaign code (CMAxxxxx)
   ============================================================ */

proc printto
  log="/data/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Logs/BGA/APN_DATA/STI_CA_D_ORCHESTRATOR.log"
  new;
run;

%include "/data/fnbins/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Automation/STI_CA_2/Libnames.sas";

options mprint mlogic symbolgen;


/* ============================================================
   CONFIGURATION — ONLY SECTION YOU EVER NEED TO EDIT
   ============================================================ */

/* Folder where all CMAxxxxx_DROP.sas files live */
%let base_path      = /data/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Campaigns/;

/* SharePoint / network paths */
%let sharepoint_path = /data/fnb/shared/campaigns/redrop;
%let request_file    = &sharepoint_path./REDROP_REQUESTS.xlsx;
%let status_out_path = &sharepoint_path./REDROP_STATUS_UPDATE.csv;
%let redrop_out_path = &sharepoint_path./outputs;

/* Notification */
%let morris_email    = Morris.Nkomo@fnb.co.za;
%let ops_dl          = dlfnbstioperationalanalytics@fnb.co.za;

/* Maximum days after original drop that a redrop is still allowed */
%let max_redrop_days = 30;

/* ============================================================
   END CONFIGURATION
   ============================================================ */


/* ============================================================
   SECTION 1: LOAD APPROVER REGISTER
   ============================================================ */

proc import
  datafile = "&request_file."
  out      = work.approvers_raw
  dbms     = xlsx replace;
  sheet    = "APPROVERS";
  getnames = yes;
run;

data work.approvers;
  set work.approvers_raw;
  name_clean           = upcase(strip(name));
  can_self_approve_flg = (upcase(strip(can_self_approve)) = "Y");
  keep name_clean can_self_approve_flg;
run;

proc sql noprint;
  select count(*) into :approver_count trimmed
  from work.approvers
  where can_self_approve_flg = 1;
quit;

%put NOTE: &approver_count. senior approvers loaded from register.;


/* ============================================================
   SECTION 2: LOAD AND VALIDATE REDROP REQUESTS
   ============================================================ */

proc import
  datafile = "&request_file."
  out      = work.requests_raw
  dbms     = xlsx replace;
  sheet    = "REDROP_REQUESTS";
  getnames = yes;
run;

/* Clean, validate, apply approval logic in one pass */
proc sql;
  create table work.requests_assessed as
  select
    strip(r.request_id)       as request_id,
    upcase(strip(r.campaign_code)) as campaign_code,
    upcase(strip(r.product_code))  as product_code,
    r.original_drop_date,
    strip(r.reason_for_redrop)     as reason_for_redrop,
    upcase(strip(r.requested_by))  as requested_by,
    upcase(strip(r.approved_by))   as approved_by,
    r.date_requested,

    /* Approval logic */
    case
      /* Already processed or rejected in a prior run */
      when upcase(strip(r.status)) not in ("PENDING") then upcase(strip(r.status))

      /* Missing drop date */
      when r.original_drop_date = . then "REJECTED"

      /* Outside redrop window */
      when intck('day', r.original_drop_date, today()) > &max_redrop_days. then "REJECTED"

      /* Requester is senior - self approve */
      when a_req.can_self_approve_flg = 1 then "SELF_APPROVED"

      /* Approved by a valid senior */
      when a_app.can_self_approve_flg = 1 then "APPROVED"

      /* Approved_by filled but name not on register - reject */
      when upcase(strip(r.approved_by)) ne ""
           and a_app.name_clean is null then "REJECTED"

      /* Waiting for approval */
      else "PENDING"
    end as approval_status,

    case
      when r.original_drop_date = .
        then "No original drop date supplied"
      when intck('day', r.original_drop_date, today()) > &max_redrop_days.
        then "Outside "||strip(put(&max_redrop_days.,best.))||" day redrop window"
      when upcase(strip(r.approved_by)) ne ""
           and a_app.name_clean is null
        then "Approver '"||strip(r.approved_by)||"' not in senior register"
      else ""
    end as reject_reason,

    case
      when a_req.can_self_approve_flg = 1 then "SELF_APPROVED"
      when a_app.can_self_approve_flg = 1
        then "APPROVED_BY_"||strip(upcase(r.approved_by))
      else ""
    end as approval_type

  from work.requests_raw r

  left join work.approvers a_req
    on upcase(strip(r.requested_by)) = a_req.name_clean

  left join work.approvers a_app
    on upcase(strip(r.approved_by))  = a_app.name_clean

  where upcase(strip(r.status)) = "PENDING"
     or (upcase(strip(r.status)) ne "PROCESSED"); /* re-evaluate non-processed */
quit;

/* Split into buckets */
data work.to_process
     work.still_pending
     work.rejected;
  set work.requests_assessed;
  select (approval_status);
    when ("SELF_APPROVED","APPROVED") output work.to_process;
    when ("PENDING")                  output work.still_pending;
    when ("REJECTED")                 output work.rejected;
    otherwise; /* already PROCESSED - skip */
  end;
run;

proc sql noprint;
  select count(*) into :process_count  trimmed from work.to_process;
  select count(*) into :pending_count  trimmed from work.still_pending;
  select count(*) into :rejected_count trimmed from work.rejected;
quit;

%put NOTE: To process=&process_count. | Pending=&pending_count. | Rejected=&rejected_count.;


/* ============================================================
   SECTION 3: REFRESH LEAD-LEVEL STATUS TABLE
   Called before any campaign file runs so exclusions are
   based on the freshest possible data.
   ============================================================ */

%macro refresh_lead_status;

  /* Seed drop reason reference if missing */
  %if %sysfunc(exist(STI_PBI.DROP_REASON_REF)) = 0 %then %do;
    data STI_PBI.DROP_REASON_REF;
      length drop_reason $100 retry_category $20 retry_eligible $1;
      infile datalines delimiter="|" dsd missover;
      input drop_reason $ retry_category $ retry_eligible $;
    datalines;
TIMEOUT|Retryable|Y
BATCH_FAILURE|Retryable|Y
NOT_LOADED_5D|Retryable|Y
SYSTEM_ERROR|Retryable|Y
OPT_OUT|Permanent|N
CONVERTED|Permanent|N
DECEASED|Permanent|N
WRONG_PRODUCT|Permanent|N
INELIGIBLE|Permanent|N
UNKNOWN|Review|R
;
    run;
  %end;

  /* Build fresh snapshot from APNS_DATA */
  proc sql;
    create table work.status_snapshot as
    select
      a.cust_no,
      a.product_code_to_adobe                as product_code,
      a.date_to_adobe,
      a.campaign_name,
      a.drop_reason_to_adobe                 as drop_reason,
      a.Adobe,
      a.date_loaded,
      a.mucn_to_adobe                        as mucn,
      a.sub_segment,
      case
        when a.Adobe = "      Loaded                                    "
          then "Sent to Adobe"
        when a.drop_reason_to_adobe = ""
             and intck('day', a.date_to_adobe, today()) <= 5
          then "Not Loaded (<=5 days)"
        when a.drop_reason_to_adobe = ""
             and intck('day', a.date_to_adobe, today()) > 5
          then "Not Loaded (>5 days)"
        when r.retry_category = "Retryable" then "Dropped - Retryable"
        when r.retry_category = "Permanent" then "Dropped - Permanent"
        when r.retry_category = "Review"    then "Dropped - Review"
        when a.drop_reason_to_adobe ne ""   then "Dropped - Review"
        else "Unknown"
      end as current_status,
      coalesce(r.retry_eligible,"R")         as retry_eligible,
      coalesce(r.retry_category,"Review")    as retry_category,
      today()  as status_date format date9.,
      time()   as status_time format time9.
    from STI_PBI.APNS_DATA a
    left join STI_PBI.DROP_REASON_REF r
      on upcase(strip(a.drop_reason_to_adobe)) = upcase(strip(r.drop_reason));
  quit;

  /* Upsert into persistent table */
  %if %sysfunc(exist(STI_PBI.LEAD_STATUS_TABLE)) = 0 %then %do;
    data STI_PBI.LEAD_STATUS_TABLE;
      set work.status_snapshot;
    run;
    %put NOTE: LEAD_STATUS_TABLE created with &sysnobs. rows.;
  %end;
  %else %do;
    proc sql;
      /* Update changed records */
      update STI_PBI.LEAD_STATUS_TABLE t
      set current_status = s.current_status,
          retry_eligible = s.retry_eligible,
          retry_category = s.retry_category,
          date_loaded    = s.date_loaded,
          Adobe          = s.Adobe,
          status_date    = s.status_date,
          status_time    = s.status_time
      from work.status_snapshot s
      where t.cust_no       = s.cust_no
        and t.product_code  = s.product_code
        and t.date_to_adobe = s.date_to_adobe
        and t.current_status ne s.current_status;

      /* Insert brand new records */
      insert into STI_PBI.LEAD_STATUS_TABLE
      select s.*
      from work.status_snapshot s
      left join STI_PBI.LEAD_STATUS_TABLE t
        on  s.cust_no       = t.cust_no
        and s.product_code  = t.product_code
        and s.date_to_adobe = t.date_to_adobe
      where t.cust_no is null;
    quit;
    %put NOTE: LEAD_STATUS_TABLE upsert complete.;
  %end;

%mend;
%refresh_lead_status;


/* ============================================================
   SECTION 4: CORE ORCHESTRATION MACRO
   Resolves file path from campaign_code, validates file
   exists, injects parameters, fires %include.

   All parameters visible inside the campaign file:
     &run_mode.      = REDROP
     &campaign_code. = e.g. CMA10184
     &product_code.  = e.g. CMA10184V01M01
     &drop_date.     = e.g. 01APR2026  (date9. formatted)
     &request_id.    = e.g. RDR001
     &redrop_out_path= output folder for redrop CSVs
   ============================================================ */

%macro fire_campaign(
  request_id    =,
  campaign_code =,
  product_code  =,
  drop_date     =,
  approval_type =
);

  /* ── Step 1: Resolve file path from campaign code alone ── */
  %let sas_file = &base_path.&campaign_code._DROP.sas;

  %put NOTE: ========================================;
  %put NOTE: Request   : &request_id.;
  %put NOTE: Campaign  : &campaign_code.;
  %put NOTE: Product   : &product_code.;
  %put NOTE: Drop Date : &drop_date.;
  %put NOTE: Approval  : &approval_type.;
  %put NOTE: File      : &sas_file.;
  %put NOTE: ========================================;

  /* ── Step 2: Safety check - file must exist ── */
  %if %sysfunc(fileexist(&sas_file.)) = 0 %then %do;

    %put ERROR: =====================================================;
    %put ERROR: No SAS file found for &campaign_code.;
    %put ERROR: Expected: &sas_file.;
    %put ERROR: Request &request_id. cannot be processed.;
    %put ERROR: Create the file and resubmit the request.;
    %put ERROR: =====================================================;

    /* Flag this request as FAILED for status writeback */
    data work.failed_&request_id.;
      length request_id $20 fail_reason $200;
      request_id  = "&request_id.";
      fail_reason = "SAS file not found: &sas_file.";
    run;

    /* Skip to next request */
    %return;

  %end;

  /* ── Step 3: Inject parameters then fire the campaign file ── */
  %let run_mode    = REDROP;   /* tells campaign file this is a redrop */

  /* These are now available inside the included file */
  /* No other changes needed to how the campaign file works */
  %include "&sas_file.";

  %put NOTE: Campaign file &campaign_code._DROP.sas completed for request &request_id.;

%mend fire_campaign;


/* ============================================================
   SECTION 5: ITERATE OVER APPROVED REQUESTS
   Reads each approved request into macro variables,
   calls %fire_campaign once per request.
   ============================================================ */

%macro run_orchestrator;

  %if &process_count. = 0 %then %do;
    %put NOTE: No approved requests to process today.;
  %end;

  %else %do;

    /* Load approved requests into indexed macro variables */
    proc sql noprint;
      select
        request_id,
        campaign_code,
        product_code,
        put(original_drop_date, date9.),
        approval_type
      into
        :req_id_1      - :req_id_&process_count.,
        :req_camp_1    - :req_camp_&process_count.,
        :req_prod_1    - :req_prod_&process_count.,
        :req_date_1    - :req_date_&process_count.,
        :req_apptype_1 - :req_apptype_&process_count.
      from work.to_process;
    quit;

    /* Initialise run summary table */
    data work.run_summary;
      length request_id $20 campaign_code $20 product_code $30
             drop_date $12 approval_type $50
             outcome $20 fail_reason $200;
      stop;
    run;

    /* Fire each campaign file in sequence */
    %do i = 1 %to &process_count.;

      %fire_campaign(
        request_id    = &&req_id_&i.,
        campaign_code = &&req_camp_&i.,
        product_code  = &&req_prod_&i.,
        drop_date     = &&req_date_&i.,
        approval_type = &&req_apptype_&i.
      );

      /* Check if a failure record was written for this request */
      %let outcome = SUCCESS;
      %if %sysfunc(exist(work.failed_&&req_id_&i.)) %then %do;
        %let outcome = FAILED;
      %end;

      /* Append to run summary */
      data work.run_summary;
        set work.run_summary;
        request_id    = "&&req_id_&i.";
        campaign_code = "&&req_camp_&i.";
        product_code  = "&&req_prod_&i.";
        drop_date     = "&&req_date_&i.";
        approval_type = "&&req_apptype_&i.";
        outcome       = "&outcome.";
        output;
      run;

    %end;

  %end;

%mend run_orchestrator;

%run_orchestrator;


/* ============================================================
   SECTION 6: WRITE STATUS BACK TO SHAREPOINT
   Campaign team sees Pending → Processed automatically.
   ============================================================ */

proc sql;
  create table work.status_updates as

  /* Successfully processed */
  select
    request_id,
    case when outcome = "SUCCESS" then "PROCESSED" else "FAILED" end as new_status,
    case when outcome = "FAILED"
      then "SAS file not found - check campaign file exists in "&base_path."."
      else "" end as notes,
    put(today(), date9.) as processed_date
  from work.run_summary

  union all

  /* Still pending */
  select
    request_id,
    "PENDING"                           as new_status,
    "Awaiting approval"                 as notes,
    ""                                  as processed_date
  from work.still_pending

  union all

  /* Rejected */
  select
    request_id,
    "REJECTED"                          as new_status,
    reject_reason                       as notes,
    put(today(), date9.)                as processed_date
  from work.rejected;
quit;

proc export
  data    = work.status_updates
  outfile = "&status_out_path."
  dbms    = csv replace;
run;


/* ============================================================
   SECTION 7: TIERED EMAIL NOTIFICATIONS
   ============================================================ */

%macro send_notifications;

  /* Count successes and failures from run summary */
  %let success_count = 0;
  %let failed_count  = 0;

  %if %sysfunc(exist(work.run_summary)) %then %do;
    proc sql noprint;
      select sum(outcome="SUCCESS") into :success_count trimmed from work.run_summary;
      select sum(outcome="FAILED")  into :failed_count  trimmed from work.run_summary;
    quit;
  %end;

  /* ── Processed successfully - FYI to Morris ── */
  %if &success_count. > 0 %then %do;

    filename eml_ok email
      to      = "&morris_email."
      cc      = "&ops_dl."
      from    = "&ops_dl."
      subject = "FYI: &success_count. Redrop(s) Processed - &sysdate9.";

    data _null_;
      file eml_ok;
      put "Hi Morris,";
      put " ";
      put "The following redrop(s) ran successfully today.";
      put "No action required from you.";
      put " ";
      put "-----------------------------------------------";
    run;

    data _null_;
      file eml_ok mod;
      set work.run_summary;
      where outcome = "SUCCESS";
      put "Request ID    : " request_id;
      put "Campaign      : " campaign_code;
      put "Product Code  : " product_code;
      put "Original Date : " drop_date;
      put "Approved via  : " approval_type;
      put "Output folder : " "&redrop_out_path.";
      put "-----------------------------------------------";
    run;

    data _null_;
      file eml_ok mod;
      put " ";
      put "Kind Regards,";
      put "Automated Campaign Operations";
    run;

  %end;

  /* ── Failed requests - action needed ── */
  %if &failed_count. > 0 %then %do;

    filename eml_fail email
      to      = "&morris_email."
      from    = "&ops_dl."
      subject = "Action Needed: &failed_count. Redrop(s) Failed - &sysdate9.";

    data _null_;
      file eml_fail;
      put "Hi Morris,";
      put " ";
      put "The following redrop request(s) could not be processed";
      put "because no SAS file was found for the campaign code.";
      put " ";
      put "This usually means the campaign file has not been built yet,";
      put "or the file name does not match the expected convention:";
      put "  CMAxxxxx_DROP.sas  in  &base_path.";
      put " ";
      put "-----------------------------------------------";
    run;

    data _null_;
      file eml_fail mod;
      set work.run_summary;
      where outcome = "FAILED";
      put "Request ID    : " request_id;
      put "Campaign      : " campaign_code;
      put "Expected file : " "&base_path." campaign_code +(-1) "_DROP.sas";
      put "-----------------------------------------------";
    run;

    data _null_;
      file eml_fail mod;
      put " ";
      put "Once the file is in place, the campaign team can resubmit";
      put "the request and it will run at the next scheduled job.";
      put " ";
      put "Kind Regards,";
      put "Automated Campaign Operations";
    run;

  %end;

  /* ── Pending requests - approval needed ── */
  %if &pending_count. > 0 %then %do;

    filename eml_pend email
      to      = "&morris_email."
      from    = "&ops_dl."
      subject = "Action Needed: &pending_count. Redrop(s) Awaiting Approval - &sysdate9.";

    data _null_;
      file eml_pend;
      put "Hi Morris,";
      put " ";
      put "The following redrop request(s) are waiting for a senior to";
      put "add their name in the 'Approved By' column of the SharePoint file.";
      put "The job will pick them up automatically at the next run.";
      put " ";
      put "-----------------------------------------------";
    run;

    data _null_;
      file eml_pend mod;
      set work.still_pending;
      put "Request ID    : " request_id;
      put "Campaign      : " campaign_code;
      put "Requested By  : " requested_by;
      put "Date Requested: " date_requested;
      put "Reason        : " reason_for_redrop;
      put "-----------------------------------------------";
    run;

    data _null_;
      file eml_pend mod;
      put " ";
      put "Kind Regards,";
      put "Automated Campaign Operations";
    run;

  %end;

  /* ── Rejected requests - inform Morris ── */
  %if &rejected_count. > 0 %then %do;

    filename eml_rej email
      to      = "&morris_email."
      from    = "&ops_dl."
      subject = "Alert: &rejected_count. Redrop Request(s) Rejected - &sysdate9.";

    data _null_;
      file eml_rej;
      put "Hi Morris,";
      put " ";
      put "The following request(s) were automatically rejected.";
      put "Please follow up with the requester.";
      put " ";
      put "-----------------------------------------------";
    run;

    data _null_;
      file eml_rej mod;
      set work.rejected;
      put "Request ID    : " request_id;
      put "Campaign      : " campaign_code;
      put "Requested By  : " requested_by;
      put "Reject Reason : " reject_reason;
      put "-----------------------------------------------";
    run;

    data _null_;
      file eml_rej mod;
      put " ";
      put "Kind Regards,";
      put "Automated Campaign Operations";
    run;

  %end;

%mend send_notifications;
%send_notifications;


/* ============================================================
   SECTION 8: AUDIT LOG
   Full traceable history of every request ever submitted.
   ============================================================ */

data work.audit_today;
  set work.requests_assessed;
  run_date = today(); format run_date date9.;
  run_time = time();  format run_time time9.;
run;

%macro append_audit;
  %if %sysfunc(exist(STI_PBI.REDROP_AUDIT_LOG)) = 0 %then %do;
    data STI_PBI.REDROP_AUDIT_LOG;
      set work.audit_today;
    run;
  %end;
  %else %do;
    proc append base=STI_PBI.REDROP_AUDIT_LOG
                data=work.audit_today force;
    run;
  %end;
%mend;
%append_audit;


/* ============================================================
   SECTION 9: LOG SUMMARY
   ============================================================ */

%put ============================================================;
%put ORCHESTRATOR COMPLETE - &sysdate9. &systime.;
%put ============================================================;
%put Requests fired (approved)  : &process_count.;
%put   of which succeeded       : &success_count.;
%put   of which failed (no file): &failed_count.;
%put Requests pending approval  : &pending_count.;
%put Requests rejected          : &rejected_count.;
%put ============================================================;

proc printto;
run;
