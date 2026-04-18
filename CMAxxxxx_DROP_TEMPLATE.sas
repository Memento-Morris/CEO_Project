/* ============================================================
   CAMPAIGN FILE TEMPLATE
   FILE:     CMAxxxxx_DROP.sas
   RENAME TO: CMAxxxxx_DROP.sas  (replace xxxxx with campaign code)

   HOW THIS FILE IS CALLED:
     - INITIAL DROP: You run this file manually once.
     - REDROPS:      The orchestrator (STI_CA_D_ORCHESTRATOR.sas)
                     calls this file automatically via %include
                     when the campaign team submits a request.

   PARAMETERS INJECTED BY ORCHESTRATOR (do not set manually):
     &run_mode.      = REDROP  (orchestrator sets this)
     &campaign_code. = CMAxxxxx
     &product_code.  = CMAxxxxxVxxMxx
     &drop_date.     = date of original drop (date9. format)
     &request_id.    = request ID for output labelling
     &redrop_out_path= folder path for redrop output CSVs

   YOUR JOB:
     1. Fill in SECTION 1 (campaign config) for the new campaign
     2. Fill in SECTION 3 (campaign-specific drop logic)
     3. Save as CMAxxxxx_DROP.sas in the campaigns folder
     4. Run manually for the initial drop
     5. Hand off - redrops run automatically from here

   DO NOT CHANGE anything in:
     - SECTION 2 (run mode detection)
     - SECTION 4 (exclusion logic)
     - SECTION 5 (output and logging)
   These are standardised across all campaign files.
   ============================================================ */


/* ============================================================
   SECTION 1: CAMPAIGN CONFIGURATION
   *** FILL THIS IN FOR EACH NEW CAMPAIGN ***
   ============================================================ */

/* Set these only when running manually for the initial drop.
   The orchestrator overrides them automatically for redrops.  */

%let campaign_code  = CMAxxxxx;              /* e.g. CMA10184          */
%let product_code   = CMAxxxxxVxxMxx;        /* e.g. CMA10184V01M01    */

/* For initial drop - set today's date.
   Orchestrator overrides this with original_drop_date for redrops. */
%if %symexist(run_mode) = 0 %then %do;
  %let run_mode  = INITIAL;
  %let drop_date = %sysfunc(today(), date9.);
  %let request_id = INITIAL_&campaign_code.;
%end;

/* Campaign-specific libname or source data path */
%let campaign_source = /data/fnb/clb/prod_data/5_optimise/passed_phase1;

/* Product codes for Adobe sends filter (used in Section 3) */
%let product_codes =
  "CMAxxxxx V01M01"  /* add all variants here */
;

%put NOTE: ====================================================;
%put NOTE: Campaign : &campaign_code.;
%put NOTE: Product  : &product_code.;
%put NOTE: Run Mode : &run_mode.;
%put NOTE: Drop Date: &drop_date.;
%put NOTE: Request  : &request_id.;
%put NOTE: ====================================================;


/* ============================================================
   SECTION 2: RUN MODE DETECTION
   DO NOT EDIT - standardised across all campaign files
   ============================================================ */

/* Detect whether this is an initial drop or a redrop.
   The orchestrator sets &run_mode = REDROP before %include.
   When run manually, &run_mode defaults to INITIAL above.    */

%let is_redrop = 0;
%if %upcase(&run_mode.) = REDROP %then %let is_redrop = 1;

%put NOTE: is_redrop flag = &is_redrop.;


/* ============================================================
   SECTION 3: CAMPAIGN-SPECIFIC DROP LOGIC
   *** FILL THIS IN FOR EACH NEW CAMPAIGN ***
   This is where your unique population-build logic goes.
   Output must be a work table called: work.drop_population
   Minimum required columns:
     cust_no        - customer number
     product_code   - product code
     campaign_name  - campaign name
     sub_segment    - sub segment
     mucn           - MUCN
     drop_reason    - blank for passes, reason code for drops
   ============================================================ */

/* EXAMPLE - replace with actual campaign logic:

libname src "&campaign_source.";

proc sql;
  create table work.drop_population as
  select
    cust_no,
    "&product_code."  as product_code,
    "&campaign_code." as campaign_name,
    sub_segment,
    mucn,
    ""                as drop_reason
  from src.CMAxxxxx_PASSED
  where product_code = "&product_code.";
quit;

*/

/* ── Placeholder so template compiles cleanly ── */
data work.drop_population;
  length cust_no $20 product_code $30 campaign_name $30
         sub_segment $50 mucn $20 drop_reason $100;
  stop;
run;

/* ============================================================
   END OF CAMPAIGN-SPECIFIC SECTION
   ============================================================ */


/* ============================================================
   SECTION 4: EXCLUSION LOGIC
   DO NOT EDIT - standardised across all campaign files.
   Handles both redrop scenarios automatically:
     A) Partial drop - some leads got through, some did not.
        Excludes successes, retries the rest.
     B) Full failure - nothing went through.
        Almost no exclusions - near-full population reruns.
   The lead status table knows which is which.
   ============================================================ */

%macro apply_exclusions;

  %if &is_redrop. = 1 %then %do;

    %put NOTE: REDROP mode - building exclusion list from lead status table.;

    /* Pull exclusions for this campaign + product + original drop date */
    proc sql;
      create table work.exclusions as
      select distinct cust_no
      from STI_PBI.LEAD_STATUS_TABLE
      where upcase(strip(product_code)) = upcase("&product_code.")
        and date_to_adobe = "&drop_date."d
        and (
          /* Already made it to Adobe successfully - never retry */
          current_status = "Sent to Adobe"

          /* Still within the 5-day loading window - too early to retry */
          or current_status = "Not Loaded (<=5 days)"

          /* Permanent drop reason - ineligible, opted out, converted etc */
          or retry_eligible = "N"
        );
    quit;

    proc sql noprint;
      select count(*) into :excl_count trimmed from work.exclusions;
    quit;

    proc sql noprint;
      select count(*) into :pop_count trimmed from work.drop_population;
    quit;

    %put NOTE: Original population : &pop_count. leads;
    %put NOTE: Excluded            : &excl_count. leads (sent/permanent/window);

    /* Remove excluded leads from population */
    proc sql;
      create table work.drop_population_final as
      select a.*
      from work.drop_population a
      left join work.exclusions b
        on a.cust_no = b.cust_no
      where b.cust_no is null; /* keep only non-excluded */
    quit;

    proc sql noprint;
      select count(*) into :eligible_count trimmed
      from work.drop_population_final;
    quit;

    %put NOTE: Eligible for redrop : &eligible_count. leads;

    %if &eligible_count. = 0 %then %do;
      %put WARNING: =====================================================;
      %put WARNING: Zero leads eligible for redrop on &campaign_code.;
      %put WARNING: All leads either succeeded, are within the 5-day;
      %put WARNING: window, or have permanent drop reasons.;
      %put WARNING: No output file will be written.;
      %put WARNING: =====================================================;
    %end;

  %end;

  %else %do;

    /* INITIAL drop - no exclusions, use full population as-is */
    %put NOTE: INITIAL drop mode - no exclusions applied.;

    data work.drop_population_final;
      set work.drop_population;
    run;

    proc sql noprint;
      select count(*) into :eligible_count trimmed
      from work.drop_population_final;
    quit;

    %let excl_count = 0;
    %put NOTE: Full population: &eligible_count. leads going to drop.;

  %end;

%mend apply_exclusions;
%apply_exclusions;


/* ============================================================
   SECTION 5: OUTPUT AND LOGGING
   DO NOT EDIT - standardised across all campaign files.
   Writes output, updates lead status, logs result.
   ============================================================ */

%macro write_output;

  %if &eligible_count. > 0 %then %do;

    /* Add run metadata to final output */
    data work.drop_output;
      set work.drop_population_final;
      redrop_request_id = "&request_id.";
      run_mode          = "&run_mode.";
      drop_date         = "&drop_date."d; format drop_date date9.;
      run_timestamp     = datetime();     format run_timestamp datetime20.;
    run;

    %if &is_redrop. = 1 %then %do;

      /* Redrop - write output CSV to SharePoint for campaign team */
      %let out_file = &redrop_out_path./REDROP_&request_id._&campaign_code..csv;

      proc export
        data    = work.drop_output
        outfile = "&out_file."
        dbms    = csv replace;
      run;

      %put NOTE: Redrop output written: &out_file.;

    %end;

    %else %do;

      /* Initial drop - follow your existing output process here.
         Replace this comment with whatever you normally do
         e.g. load to production table, export to Adobe path etc. */
      %put NOTE: INITIAL drop output - follow campaign output process.;

      /* Example:
      proc sql;
        create table STI_PBI.&campaign_code._DROP as
        select * from work.drop_output;
      quit;
      */

    %end;

  %end;

  /* Always log the drop summary to a persistent audit table */
  data work.drop_log_entry;
    length campaign_code $20 product_code $30 request_id $20
           run_mode $10 drop_date_str $12
           population_count 8 excluded_count 8 eligible_count 8
           log_date 8 log_time 8;
    campaign_code     = "&campaign_code.";
    product_code      = "&product_code.";
    request_id        = "&request_id.";
    run_mode          = "&run_mode.";
    drop_date_str     = "&drop_date.";
    population_count  = &pop_count.;     /* if INITIAL, same as eligible */
    excluded_count    = &excl_count.;
    eligible_count    = &eligible_count.;
    log_date          = today(); format log_date date9.;
    log_time          = time();  format log_time time9.;
  run;

  %if %sysfunc(exist(STI_PBI.CAMPAIGN_DROP_LOG)) = 0 %then %do;
    data STI_PBI.CAMPAIGN_DROP_LOG;
      set work.drop_log_entry;
    run;
  %end;
  %else %do;
    proc append base=STI_PBI.CAMPAIGN_DROP_LOG
                data=work.drop_log_entry force;
    run;
  %end;

  %put NOTE: Drop log updated for &campaign_code. request &request_id.;

%mend write_output;
%write_output;

/* ============================================================
   END OF CAMPAIGN FILE TEMPLATE
   ============================================================ */
