/* ============================================================
   JOB:      STI_CA_D_REDROP_MANAGER
   STATUS:   PROD
   PURPOSE:  Redrop Request Management - Lead Status Tracking,
             Approval Logic, Exclusion List Build, Notification
   ============================================================

   DEPENDENCIES:
     - SharePoint Excel file (network path) with two sheets:
         Sheet1: REDROP_REQUESTS  - campaign team submits requests
         Sheet2: APPROVERS        - senior approver register
     - STI_PBI.LEAD_STATUS_TABLE  - persistent lead-level status
       (built and maintained by this job each run)
     - STI_PBI.APNS_DATA          - main campaign output table
     - STI_PBI.DROP_REASON_REF    - drop reason classification ref

   FLOW:
     1.  Load approver register from SharePoint Excel
     2.  Load redrop requests from SharePoint Excel
     3.  Refresh lead-level status table from latest APNS_DATA
     4.  Validate and classify each pending request
     5.  Build exclusion lists for approved requests
     6.  Write redrop-eligible output per campaign
     7.  Write status back to SharePoint queue
     8.  Send tiered email notifications
   ============================================================ */

%include "/data/fnbins/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Automation/STI_CA_2/Libnames.sas";

proc printto
  log="/data/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Logs/BGA/APN_DATA/STI_CA_D_REDROP_MANAGER.log"
  new;
run;

/* ============================================================
   CONFIGURATION - EDIT THIS SECTION ONLY
   ============================================================ */

/* Path the VM can reach - update to your actual SharePoint UNC path */
%let sharepoint_path  = /data/fnb/shared/campaigns/redrop;
%let request_file     = &sharepoint_path./REDROP_REQUESTS.xlsx;
%let status_out_path  = &sharepoint_path./REDROP_STATUS_UPDATE.csv;
%let redrop_out_path  = &sharepoint_path./outputs;

/* Morris notification address */
%let morris_email     = Morris.Nkomo@fnb.co.za;
%let ops_dl           = dlfnbstioperationalanalytics@fnb.co.za;

/* How many days after original drop date to still allow a redrop */
%let max_redrop_days  = 30;

/* ============================================================
   SECTION 1: LOAD APPROVER REGISTER
   Sheet: APPROVERS
   Columns: name, email, can_self_approve (Y/N)
   ============================================================ */

proc import
  datafile = "&request_file."
  out      = work.approvers_raw
  dbms     = xlsx
  replace;
  sheet    = "APPROVERS";
  getnames = yes;
run;

data work.approvers;
  set work.approvers_raw;
  /* Normalise - trim and uppercase for reliable matching */
  name_clean           = upcase(strip(name));
  email_clean          = lowcase(strip(email));
  can_self_approve_flg = (upcase(strip(can_self_approve)) = "Y");
  keep name_clean email_clean can_self_approve_flg;
run;

/* Build macro variable list of self-approvers for inline checks */
proc sql noprint;
  select count(*)
  into   :approver_count trimmed
  from   work.approvers
  where  can_self_approve_flg = 1;

  select name_clean
  into   :approver_1 - :approver_&approver_count.
  from   work.approvers
  where  can_self_approve_flg = 1;
quit;

%put NOTE: &approver_count. senior approvers loaded.;


/* ============================================================
   SECTION 2: LOAD REDROP REQUESTS
   Sheet: REDROP_REQUESTS
   Columns: request_id, campaign_code, product_code,
            original_drop_date, reason_for_redrop,
            requested_by, approved_by, date_requested, status
   ============================================================ */

proc import
  datafile = "&request_file."
  out      = work.requests_raw
  dbms     = xlsx
  replace;
  sheet    = "REDROP_REQUESTS";
  getnames = yes;
run;

data work.requests_clean;
  set work.requests_raw;

  /* Normalise fields */
  request_id_c       = strip(request_id);
  campaign_code_c    = upcase(strip(campaign_code));
  product_code_c     = upcase(strip(product_code));
  reason_c           = strip(reason_for_redrop);
  requested_by_c     = upcase(strip(requested_by));
  approved_by_c      = upcase(strip(approved_by));
  status_c           = upcase(strip(status));

  /* Only work on pending requests */
  if status_c = "PENDING";

  /* Validate original_drop_date is populated */
  if original_drop_date = . then do;
    status_c      = "REJECTED";
    reject_reason = "No original drop date supplied";
  end;

  /* Reject requests older than max_redrop_days */
  if original_drop_date ne .
    and intck('day', original_drop_date, today()) > &max_redrop_days. then do;
    status_c      = "REJECTED";
    reject_reason = "Original drop date exceeds "||strip(put(&max_redrop_days.,best.))
                    ||" day redrop window";
  end;

  keep request_id_c campaign_code_c product_code_c original_drop_date
       reason_c requested_by_c approved_by_c date_requested
       status_c reject_reason;
run;


/* ============================================================
   SECTION 3: APPROVAL LOGIC
   Rules:
     A) requested_by IS in approvers list  -> self-approved, process
     B) approved_by IS in approvers list   -> approved by senior, process
     C) approved_by filled but NOT in list -> reject (invalid approver)
     D) approved_by blank, requester junior -> leave pending, alert Morris
   ============================================================ */

proc sql;
  create table work.requests_assessed as
  select
    r.*,

    /* Is the requester a senior self-approver? */
    case when a_req.name_clean is not null and a_req.can_self_approve_flg = 1
         then 1 else 0
    end as requester_is_senior,

    /* Is the approver a valid senior? */
    case when r.approved_by_c ne "" and a_app.name_clean is not null
              and a_app.can_self_approve_flg = 1
         then 1 else 0
    end as approver_is_valid,

    /* Invalid approver - someone filled in a name not on the list */
    case when r.approved_by_c ne ""
              and a_app.name_clean is null
         then 1 else 0
    end as approver_is_invalid,

    /* Derive final approval status */
    case
      when r.status_c in ("REJECTED")         then "REJECTED"
      when calculated requester_is_senior = 1 then "SELF_APPROVED"
      when calculated approver_is_valid   = 1 then "APPROVED"
      when calculated approver_is_invalid = 1 then "REJECTED"
      else                                         "PENDING"
    end as approval_status,

    case
      when calculated approver_is_invalid = 1
        then "Approver name '"||strip(r.approved_by_c)||
             "' not found in senior approver register"
      when r.status_c = "REJECTED" then r.reject_reason
      else ""
    end as final_reject_reason

  from work.requests_clean r

  /* Join to check requester */
  left join work.approvers a_req
    on  r.requested_by_c = a_req.name_clean

  /* Join to check approver */
  left join work.approvers a_app
    on  r.approved_by_c = a_app.name_clean;
quit;

/* Separate into actionable buckets */
data work.to_process    /* approved - run exclusion logic */
     work.still_pending /* waiting for approval            */
     work.rejected;     /* invalid - notify and close      */
  set work.requests_assessed;
  select (approval_status);
    when ("SELF_APPROVED", "APPROVED") output work.to_process;
    when ("PENDING")                   output work.still_pending;
    when ("REJECTED")                  output work.rejected;
    otherwise;
  end;
run;

proc sql noprint;
  select count(*) into :process_count   trimmed from work.to_process;
  select count(*) into :pending_count   trimmed from work.still_pending;
  select count(*) into :rejected_count  trimmed from work.rejected;
quit;

%put NOTE: &process_count. requests to process, &pending_count. pending approval, &rejected_count. rejected.;


/* ============================================================
   SECTION 4: REFRESH LEAD-LEVEL STATUS TABLE
   Upsert from latest APNS_DATA each run.
   Persists authoritative per-lead state across runs.

   Table key: cust_no + product_code_to_adobe + date_to_adobe

   current_status values:
     Sent to Adobe         - successfully loaded
     Not Loaded (<=5 days) - within tolerance window
     Not Loaded (>5 days)  - stale, should be investigated
     Dropped - Retryable   - eligible for redrop
     Dropped - Permanent   - do not retry
     Dropped - Review      - human decision needed
   ============================================================ */

/* Load drop reason classification reference */
/* If STI_PBI.DROP_REASON_REF does not exist yet, seed it here */
%macro seed_drop_reason_ref;
  %if %sysfunc(exist(STI_PBI.DROP_REASON_REF)) = 0 %then %do;
    %put NOTE: DROP_REASON_REF not found - seeding with defaults.;
    data STI_PBI.DROP_REASON_REF;
      length drop_reason $100 retry_category $20 retry_eligible $1 description $200;
      infile datalines delimiter="|" dsd missover;
      input drop_reason $ retry_category $ retry_eligible $ description $;
    datalines;
TIMEOUT|Retryable|Y|System or network timeout - safe to retry
BATCH_FAILURE|Retryable|Y|Batch processing failure - safe to retry
NOT_LOADED_5D|Retryable|Y|Not loaded into Adobe within 5 day window
SYSTEM_ERROR|Retryable|Y|Technical system error - safe to retry
OPT_OUT|Permanent|N|Customer has opted out - do not contact
CONVERTED|Permanent|N|Customer already converted
DECEASED|Permanent|N|Customer deceased
WRONG_PRODUCT|Permanent|N|Product not applicable to customer
INELIGIBLE|Permanent|N|Customer does not meet eligibility criteria
UNKNOWN|Review|R|Reason unclear - requires human review before redrop
;
    run;
    %put NOTE: DROP_REASON_REF seeded with &sysnobs. rows.;
  %end;
%mend;
%seed_drop_reason_ref;

/* Build current status snapshot from APNS_DATA */
proc sql;
  create table work.status_snapshot as
  select
    a.cust_no,
    a.product_code_to_adobe          as product_code,
    a.date_to_adobe,
    a.campaign_name,
    a.drop_reason_to_adobe           as drop_reason,
    a.Adobe,
    a.date_loaded,
    a.mucn_to_adobe                  as mucn,
    a.sub_segment,

    /* Classify current status */
    case
      when a.Adobe = "      Loaded                                    "
        then "Sent to Adobe"
      when a.drop_reason_to_adobe = ""
           and intck('day', a.date_to_adobe, today()) <= 5
        then "Not Loaded (<=5 days)"
      when a.drop_reason_to_adobe = ""
           and intck('day', a.date_to_adobe, today()) > 5
        then "Not Loaded (>5 days)"
      when r.retry_category = "Retryable"
        then "Dropped - Retryable"
      when r.retry_category = "Permanent"
        then "Dropped - Permanent"
      when r.retry_category = "Review"
        then "Dropped - Review"
      when a.drop_reason_to_adobe ne ""
        then "Dropped - Review"   /* unlisted reason defaults to review */
      else "Unknown"
    end as current_status,

    coalesce(r.retry_eligible, "R")  as retry_eligible,
    coalesce(r.retry_category, "Review") as retry_category,
    today()                          as status_date format date9.,
    time()                           as status_time format time9.

  from STI_PBI.APNS_DATA a

  left join STI_PBI.DROP_REASON_REF r
    on upcase(strip(a.drop_reason_to_adobe)) = upcase(strip(r.drop_reason));
quit;

/* Upsert into persistent lead status table */
%macro upsert_lead_status;

  %if %sysfunc(exist(STI_PBI.LEAD_STATUS_TABLE)) = 0 %then %do;
    /* First run - create from snapshot */
    %put NOTE: LEAD_STATUS_TABLE does not exist - creating from snapshot.;
    proc sql;
      create table STI_PBI.LEAD_STATUS_TABLE as
      select * from work.status_snapshot;
    quit;
    %put NOTE: LEAD_STATUS_TABLE created with &sqlobs. rows.;
  %end;

  %else %do;
    /* Subsequent runs - update existing records, insert new ones */
    proc sql;

      /* Update existing records where status has changed */
      update STI_PBI.LEAD_STATUS_TABLE as t
      set current_status = s.current_status,
          retry_eligible = s.retry_eligible,
          retry_category = s.retry_category,
          date_loaded    = s.date_loaded,
          Adobe          = s.Adobe,
          status_date    = s.status_date,
          status_time    = s.status_time
      from work.status_snapshot as s
      where t.cust_no      = s.cust_no
        and t.product_code = s.product_code
        and t.date_to_adobe = s.date_to_adobe
        and t.current_status ne s.current_status; /* only update if changed */

      /* Insert new records not yet in the table */
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
%upsert_lead_status;


/* ============================================================
   SECTION 5: BUILD EXCLUSION LISTS AND REDROP OUTPUTS
   For each approved request, produce a redrop-eligible list
   excluding anyone who:
     - Already reached Adobe successfully
     - Has a permanent drop reason
   ============================================================ */

%macro process_redrop_request(
  req_id        =,
  campaign_code =,
  product_code  =,
  drop_date     =,
  requested_by  =,
  approved_by   =,
  approval_type =   /* SELF_APPROVED or APPROVED */
);

  %put NOTE: Processing redrop request &req_id. for &campaign_code. / &product_code.;

  /* Pull eligible leads from status table */
  proc sql;
    create table work.redrop_&req_id. as
    select
      cust_no,
      product_code,
      date_to_adobe,
      campaign_name,
      drop_reason,
      current_status,
      retry_category,
      mucn,
      sub_segment,
      "&req_id."      as redrop_request_id,
      "&requested_by." as redrop_requested_by,
      "&approved_by."  as redrop_approved_by,
      "&approval_type." as approval_type,
      today()         as redrop_date format date9.

    from STI_PBI.LEAD_STATUS_TABLE
    where upcase(strip(product_code)) = upcase("&product_code.")
      and date_to_adobe               = "&drop_date."d

      /* EXCLUSIONS - do not redrop these */
      and current_status not in (
        "Sent to Adobe",         /* already succeeded       */
        "Not Loaded (<=5 days)"  /* still within tolerance  */
      )
      and retry_eligible ne "N"; /* permanent drop reasons  */
  quit;

  proc sql noprint;
    select count(*) into :eligible_count trimmed from work.redrop_&req_id.;
  quit;

  /* Count excluded for reporting */
  proc sql noprint;
    select count(*) into :excluded_count trimmed
    from STI_PBI.LEAD_STATUS_TABLE
    where upcase(strip(product_code)) = upcase("&product_code.")
      and date_to_adobe               = "&drop_date."d
      and (current_status in ("Sent to Adobe","Not Loaded (<=5 days)")
           or retry_eligible = "N");
  quit;

  %put NOTE: Request &req_id. - &eligible_count. eligible for redrop, &excluded_count. excluded.;

  /* Write output file for campaign team */
  %if &eligible_count. > 0 %then %do;
    proc export
      data    = work.redrop_&req_id.
      outfile = "&redrop_out_path./REDROP_&req_id._&campaign_code..csv"
      dbms    = csv
      replace;
    run;
    %put NOTE: Redrop file written: REDROP_&req_id._&campaign_code..csv;
  %end;
  %else %do;
    %put WARNING: Request &req_id. - zero eligible leads. No output file written.;
  %end;

  /* Store summary for notification email */
  data work.redrop_summary_&req_id.;
    length request_id $20 campaign_code $20 product_code $30
           requested_by $100 approved_by $100 approval_type $20
           eligible_count 8 excluded_count 8 output_file $200;
    request_id     = "&req_id.";
    campaign_code  = "&campaign_code.";
    product_code   = "&product_code.";
    requested_by   = "&requested_by.";
    approved_by    = "&approved_by.";
    approval_type  = "&approval_type.";
    eligible_count = &eligible_count.;
    excluded_count = &excluded_count.;
    %if &eligible_count. > 0 %then %do;
      output_file  = "REDROP_&req_id._&campaign_code..csv";
    %end;
    %else %do;
      output_file  = "No output - zero eligible leads";
    %end;
  run;

%mend;


/* Iterate over approved requests and call the macro for each */
%macro run_all_approved_requests;

  %if &process_count. = 0 %then %do;
    %put NOTE: No approved requests to process this run.;
  %end;
  %else %do;

    /* Read approved requests into macro variables */
    proc sql noprint;
      select request_id_c, campaign_code_c, product_code_c,
             put(original_drop_date, date9.), requested_by_c,
             approved_by_c, approval_status
      into   :req_id_1      - :req_id_&process_count.,
             :req_camp_1    - :req_camp_&process_count.,
             :req_prod_1    - :req_prod_&process_count.,
             :req_date_1    - :req_date_&process_count.,
             :req_reqby_1   - :req_reqby_&process_count.,
             :req_appby_1   - :req_appby_&process_count.,
             :req_apptype_1 - :req_apptype_&process_count.
      from work.to_process;
    quit;

    %do i = 1 %to &process_count.;
      %process_redrop_request(
        req_id        = &&req_id_&i.,
        campaign_code = &&req_camp_&i.,
        product_code  = &&req_prod_&i.,
        drop_date     = &&req_date_&i.,
        requested_by  = &&req_reqby_&i.,
        approved_by   = &&req_appby_&i.,
        approval_type = &&req_apptype_&i.
      );
    %end;

    /* Combine all summaries */
    data work.all_redrop_summaries;
      set work.redrop_summary_:;
    run;

  %end;

%mend;
%run_all_approved_requests;


/* ============================================================
   SECTION 6: WRITE STATUS BACK TO SHAREPOINT QUEUE
   Updates status column so campaign team can see their request
   was picked up without needing to ask Morris.
   ============================================================ */

proc sql;
  create table work.status_updates as

  /* Approved and processed */
  select request_id_c as request_id,
         "PROCESSED"  as new_status,
         ""           as reject_reason,
         put(today(), date9.) as processed_date
  from work.to_process

  union all

  /* Rejected requests */
  select request_id_c,
         "REJECTED",
         final_reject_reason,
         put(today(), date9.)
  from work.rejected

  union all

  /* Still pending - no change but log for audit */
  select request_id_c,
         "PENDING",
         "Awaiting approval",
         ""
  from work.still_pending;
quit;

proc export
  data    = work.status_updates
  outfile = "&status_out_path."
  dbms    = csv
  replace;
run;

/* NOTE: A Power Automate flow or Python script on SharePoint side
   can pick up this CSV and write the status back into the Excel file.
   Alternatively, Morris can paste it in manually if automation
   of the writeback is not yet in place.                           */


/* ============================================================
   SECTION 7: EMAIL NOTIFICATIONS
   Tiered by situation:
     A) Requests processed (self-approved)   - FYI to Morris
     B) Requests processed (approved by X)   - FYI to Morris
     C) Requests waiting for approval        - Action needed
     D) Requests rejected                    - Inform requester
   ============================================================ */

%macro send_notifications;

  /* ---- A & B: Processed requests - FYI to Morris ---- */
  %if &process_count. > 0 %then %do;

    filename eml_fyi email
      to      = "&morris_email."
      cc      = "&ops_dl."
      from    = "&ops_dl."
      subject = "FYI: &process_count. Redrop Request(s) Processed Today";

    data _null_;
      file eml_fyi;
      put "Hi Morris,";
      put " ";
      put "The following redrop request(s) were processed in today's run.";
      put "No action is required from you.";
      put " ";
      put "-----------------------------------------------------------";
    run;

    /* Loop through summaries and write one paragraph per request */
    %do i = 1 %to &process_count.;
      data _null_;
        file eml_fyi mod;
        set work.all_redrop_summaries;
        if request_id = "&&req_id_&i." then do;
          put "Request ID   : " request_id;
          put "Campaign     : " campaign_code;
          put "Product Code : " product_code;
          put "Requested by : " requested_by;
          if approval_type = "SELF_APPROVED" then
            put "Approval     : Self-approved (senior approver)";
          else
            put "Approved by  : " approved_by;
          put "Leads eligible for redrop : " eligible_count;
          put "Leads excluded (sent/permanent) : " excluded_count;
          put "Output file  : " output_file;
          put "-----------------------------------------------------------";
        end;
      run;
    %end;

    data _null_;
      file eml_fyi mod;
      put " ";
      put "Kind Regards,";
      put "Automated Campaign Operations";
    run;

  %end;


  /* ---- C: Pending requests - Action needed by Morris ---- */
  %if &pending_count. > 0 %then %do;

    filename eml_pend email
      to      = "&morris_email."
      from    = "&ops_dl."
      subject = "Action Needed: &pending_count. Redrop Request(s) Awaiting Approval";

    data _null_;
      file eml_pend;
      put "Hi Morris,";
      put " ";
      put "The following redrop request(s) are waiting for a senior approval";
      put "before they can be processed.";
      put " ";
      put "To approve: open the REDROP_REQUESTS.xlsx on SharePoint,";
      put "find the request below, and enter your name in the 'approved_by' column.";
      put "The job will pick it up in the next scheduled run.";
      put " ";
      put "-----------------------------------------------------------";
    run;

    data _null_;
      file eml_pend mod;
      set work.still_pending;
      put "Request ID   : " request_id_c;
      put "Campaign     : " campaign_code_c;
      put "Product Code : " product_code_c;
      put "Requested by : " requested_by_c;
      put "Date Requested : " date_requested;
      put "Reason       : " reason_c;
      put "-----------------------------------------------------------";
    run;

    data _null_;
      file eml_pend mod;
      put " ";
      put "Kind Regards,";
      put "Automated Campaign Operations";
    run;

  %end;


  /* ---- D: Rejected requests - Inform requester ---- */
  %if &rejected_count. > 0 %then %do;

    filename eml_rej email
      to      = "&morris_email."
      cc      = "&ops_dl."
      from    = "&ops_dl."
      subject = "Alert: &rejected_count. Redrop Request(s) Rejected";

    data _null_;
      file eml_rej;
      put "Hi Morris,";
      put " ";
      put "The following redrop request(s) were rejected automatically.";
      put "Please follow up with the requester where needed.";
      put " ";
      put "-----------------------------------------------------------";
    run;

    data _null_;
      file eml_rej mod;
      set work.rejected;
      put "Request ID     : " request_id_c;
      put "Campaign       : " campaign_code_c;
      put "Requested by   : " requested_by_c;
      put "Reject Reason  : " final_reject_reason;
      put "-----------------------------------------------------------";
    run;

    data _null_;
      file eml_rej mod;
      put " ";
      put "Kind Regards,";
      put "Automated Campaign Operations";
    run;

  %end;

%mend;

options mprint mlogic symbolgen;
%send_notifications;


/* ============================================================
   SECTION 8: AUDIT LOG
   Append a record of every request processed this run
   to a permanent audit table for traceability.
   ============================================================ */

data work.audit_entry;
  set work.requests_assessed;
  run_date       = today(); format run_date date9.;
  run_time       = time();  format run_time time9.;
  final_status   = approval_status;
  keep request_id_c campaign_code_c product_code_c original_drop_date
       reason_c requested_by_c approved_by_c approval_status
       final_reject_reason run_date run_time;
  rename request_id_c       = request_id
         campaign_code_c    = campaign_code
         product_code_c     = product_code
         requested_by_c     = requested_by
         approved_by_c      = approved_by
         final_reject_reason = reject_reason;
run;

%macro append_audit;
  %if %sysfunc(exist(STI_PBI.REDROP_AUDIT_LOG)) = 0 %then %do;
    data STI_PBI.REDROP_AUDIT_LOG;
      set work.audit_entry;
    run;
    %put NOTE: REDROP_AUDIT_LOG created.;
  %end;
  %else %do;
    proc append base=STI_PBI.REDROP_AUDIT_LOG data=work.audit_entry force;
    run;
    %put NOTE: REDROP_AUDIT_LOG updated.;
  %end;
%mend;
%append_audit;


/* ============================================================
   SECTION 9: SUMMARY TO LOG
   ============================================================ */

%put ============================================================;
%put REDROP MANAGER RUN SUMMARY - %sysfunc(today(), date9.) %sysfunc(time(), time9.);
%put ============================================================;
%put Requests processed (approved)  : &process_count.;
%put Requests pending approval       : &pending_count.;
%put Requests rejected               : &rejected_count.;
%put Senior approvers on register    : &approver_count.;
%put ============================================================;

proc printto;
run;
