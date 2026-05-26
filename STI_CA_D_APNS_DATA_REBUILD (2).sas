%put TAG:JobName1=STI_CA_D_APNS_DATA_REBUILD;
%put TAG:JobName2=Daily;
%put TAG:JobCategory=Campaigns;
%put TAG:JobPurpose=Operational;
%put TAG:JobPriority=Medium;
%put TAG:JobStatus=Prod;

options mprint mlogic symbolgen source notes;

%include "/data/fnbins/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Automation/STI_CA_2/Libnames.sas";


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 1: READ CAMPAIGN CONFIG FROM EXCEL
   ─ Reads Campaign_Code, Product_Code, Active, Target_Leads, Priority_Field
   ═══════════════════════════════════════════════════════════════════════════ */

filename APN_CFG "\\INS-RBFS01\Share\FNB_Insure\Campaign Profiles\APN_Campaign_Config.xlsx";

proc import
    datafile = APN_CFG
    out      = Campaign_Config_Raw
    dbms     = xlsx
    replace;
    sheet    = "Config";
    getnames = yes;
run;

filename APN_CFG clear;

data Campaign_Config;
    set Campaign_Config_Raw;
    where upcase(strip(Active)) = "Y"
      and strip(Campaign_Code)  ne ""
      and strip(Product_Code)   ne "";
    Campaign_Code  = upcase(strip(Campaign_Code));
    Product_Code   = upcase(strip(Product_Code));
    Priority_Field = coalescec(strip(Priority_Field), "date_to_adobe");
    /* Default target to 0 (no cap) if missing or blank */
    if missing(Target_Leads) then Target_Leads = 0;
run;

proc sql noprint;
    select count(*) into :config_count trimmed
    from Campaign_Config;
quit;

%if &config_count = 0 %then %do;
    %put ERROR: Config has no active rows. Check Excel file.;
    %abort cancel;
%end;

%put NOTE: &config_count active product codes loaded from config.;

title "CONFIG - Active Campaigns Loaded from Excel";
proc print data=Campaign_Config noobs; run;
title;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 2: BUILD DYNAMIC MACRO VARIABLES FROM CONFIG
   ═══════════════════════════════════════════════════════════════════════════ */

proc sql noprint;
    select count(distinct Campaign_Code)
    into   :camp_count trimmed
    from   Campaign_Config;

    select distinct Campaign_Code
    into   :camp_1 -
    from   Campaign_Config
    order  by Campaign_Code;

    select distinct cats("'", Product_Code, "'")
    into   :product_list separated by ","
    from   Campaign_Config;
quit;

%put NOTE: &camp_count distinct campaign codes found.;
%put NOTE: Product list: &product_list;

/* Target lookup table – one row per Campaign_Code + Product_Code */
proc sql noprint;
    create table work.target_lookup as
    select Campaign_Code,
           Product_Code,
           Target_Leads
    from Campaign_Config;
quit;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 3: CAPTURE PRE-RUN STATE
   ═══════════════════════════════════════════════════════════════════════════ */

proc sql noprint;
    select max(date_to_adobe) format date9.
    into   :Old_date trimmed
    from   STI_PBI.APN_POT;

    select max(time_created_to_adobe) format time9.
    into   :Old_time trimmed
    from   STI_PBI.APN_POT
    where  date_to_adobe = max(date_to_adobe);

    select count(CUST_NO)
    into   :Old_records trimmed
    from   STI_PBI.APN_POT;
quit;

%put Pre-run state: &Old_date &Old_time  Records: &Old_records;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 4: LIBNAMES
   ═══════════════════════════════════════════════════════════════════════════ */

libname Pass6    "/data/fnb/clb/archive/5_optimise/passed_phase1";
libname APN_Pass "/data/fnb/clb/prod_data/5_optimise/passed_phase1";
libname Drop6    "/data/fnb/clb/archive/5_optimise/dropped_phase1";
libname APN_Drop "/data/fnb/clb/prod_data/5_optimise/dropped_phase1";
libname APNS     "/data/fnb/clb/prod_data/7_tracking_views/Reporting_views";


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 5: CLEAR STALE WORK TABLES
   ═══════════════════════════════════════════════════════════════════════════ */

proc datasets library=work nolist;
    delete _tabpass_:      _tabdrop_:
           pass_tables_arch     pass_tables_live
           drop_tables_arch     drop_tables_live
           pass_tables_combined drop_tables_combined
           monthly_pass_list    monthly_drop_list
           adobe_final_new      adobe_final_table_clients
           adobe_to_clients_step  adobe_to_clients_step2
           adobe_to_clients_final adobe_delivery_test
           adobe_recent_drops     apns_sends_campaigns
           campaigns_to_adobe     campaigns_to_adobe_step
           campaigns_to_adobe_renamed joining
           apn_pot_step1          apn_pot_targeted
           cust_adobe_flag        cust_loaded_summary
           apn_pot_summary_final  target_tracking;
quit;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 6: CAMPAIGN TABLE DISCOVERY
   ═══════════════════════════════════════════════════════════════════════════ */

%macro build_campaign_filter(libref=, outds=);
    proc sql;
        create table &outds as
        select *
        from dictionary.tables
        where libname = "%upcase(&libref)"
          and (
            %do i = 1 %to &camp_count;
                %if &i > 1 %then or;
                memname like "&&camp_&i..%"
            %end;
          );
    quit;
%mend;

%build_campaign_filter(libref=PASS6,    outds=pass_tables_arch)
%build_campaign_filter(libref=APN_PASS, outds=pass_tables_live)
%build_campaign_filter(libref=DROP6,    outds=drop_tables_arch)
%build_campaign_filter(libref=APN_DROP, outds=drop_tables_live)

data pass_tables_combined;
    set pass_tables_arch (in=a)
        pass_tables_live (in=b);
    Source = ifc(b, 'Live', 'Archive');
run;

proc sort data=pass_tables_combined; by memname descending Source; run;
proc sort data=pass_tables_combined nodupkey; by memname; run;

data drop_tables_combined;
    set drop_tables_arch (in=a)
        drop_tables_live (in=b);
    Source = ifc(b, 'Live', 'Archive');
run;

proc sort data=drop_tables_combined; by memname descending Source; run;
proc sort data=drop_tables_combined nodupkey; by memname; run;

proc sql noprint;
    create table monthly_pass_list as
    select distinct memname, crdate, Source
    from pass_tables_combined
    order by memname;

    select count(*) into :monthly_pass_count trimmed
    from monthly_pass_list;
quit;

proc sql noprint;
    create table monthly_drop_list as
    select distinct memname, crdate, Source
    from drop_tables_combined
    order by memname;

    select count(*) into :monthly_drop_count trimmed
    from monthly_drop_list;
quit;

%put Pass tables found: &monthly_pass_count;
%put Drop tables found: &monthly_drop_count;

title "DEBUG 1 - Pass Tables Discovered";
proc print data=monthly_pass_list noobs; run;
title "DEBUG 1 - Drop Tables Discovered";
proc print data=monthly_drop_list noobs; run;
title;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 7: READ ALL PASSED RECORDS
   ═══════════════════════════════════════════════════════════════════════════ */

%macro iterate_pass;
    proc datasets library=work nolist;
        delete _tabpass_:;
    quit;

    %local i tname tdate tsource libref;
    %do i = 1 %to &monthly_pass_count;

        proc sql noprint;
            select memname, crdate, Source
            into   :tname trimmed, :tdate trimmed, :tsource trimmed
            from   monthly_pass_list
            where  monotonic() = &i;
        quit;

        %put Processing pass &i of &monthly_pass_count: &tname (&tsource);

        %if %upcase(&tsource) = LIVE %then %let libref = APN_Pass;
        %else                              %let libref = Pass6;

        data _tabpass_&i;
            set &libref..&tname
                (keep=CUST_NO Product_Code Drop_Reason sub_segment
                      Campaign_Name Brand MUCN);
            length _memname_ $50 _date_raw_ $8 _time_raw_ $4;
            _memname_ = "&tname";
            if index(_memname_,'_') > 0 then do;
                _date_raw_ = scan(_memname_, -2, '_');
                _time_raw_ = scan(_memname_, -1, '_');
                if length(strip(_time_raw_)) = 3 then
                    _time_raw_ = cats('0', strip(_time_raw_));
                Date_to_adobe         = input(_date_raw_, YYMMDD8.);
                Time_created_to_adobe = input(cats(substr(_time_raw_,1,2),':',
                                                   substr(_time_raw_,3,2),':00'),
                                              HHMMSS8.);
            end;
            else do;
                _date_raw_            = substr(_memname_, 16, 8);
                Date_to_adobe         = input(_date_raw_, YYMMDD10.);
                Time_created_to_adobe = input(substr("&tdate",9,8), HHMMSS.);
            end;
            format Date_to_adobe date9.;
            format Time_created_to_adobe time9.;
            rename CUST_NO = cust_no
                   MUCN    = mucn
                   Brand   = brand;
            drop _memname_ _date_raw_ _time_raw_;
        run;
    %end;
%mend;
%iterate_pass;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 8: READ ALL DROPPED RECORDS
   ═══════════════════════════════════════════════════════════════════════════ */

%macro iterate_drop;
    proc datasets library=work nolist;
        delete _tabdrop_:;
    quit;

    %local i tname tdate tsource libref;
    %do i = 1 %to &monthly_drop_count;

        proc sql noprint;
            select memname, crdate, Source
            into   :tname trimmed, :tdate trimmed, :tsource trimmed
            from   monthly_drop_list
            where  monotonic() = &i;
        quit;

        %put Processing drop &i of &monthly_drop_count: &tname (&tsource);

        %if %upcase(&tsource) = LIVE %then %let libref = APN_Drop;
        %else                              %let libref = Drop6;

        data _tabdrop_&i;
            set &libref..&tname
                (keep=CUST_NO Product_Code Drop_Reason sub_segment
                      Campaign_Name Brand MUCN);
            length _memname_ $50 _date_raw_ $8 _time_raw_ $4;
            _memname_ = "&tname";
            if index(_memname_,'_') > 0 then do;
                _date_raw_ = scan(_memname_, -2, '_');
                _time_raw_ = scan(_memname_, -1, '_');
                if length(strip(_time_raw_)) = 3 then
                    _time_raw_ = cats('0', strip(_time_raw_));
                Date_to_adobe         = input(_date_raw_, YYMMDD8.);
                Time_created_to_adobe = input(cats(substr(_time_raw_,1,2),':',
                                                   substr(_time_raw_,3,2),':00'),
                                              HHMMSS8.);
            end;
            else do;
                _date_raw_            = substr(_memname_, 16, 8);
                Date_to_adobe         = input(_date_raw_, YYMMDD10.);
                Time_created_to_adobe = input(substr("&tdate",9,8), HHMMSS.);
            end;
            format Date_to_adobe date9.;
            format Time_created_to_adobe time9.;
            rename CUST_NO = cust_no
                   MUCN    = mucn
                   Brand   = brand;
            drop _memname_ _date_raw_ _time_raw_;
        run;
    %end;
%mend;
%iterate_drop;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 9: COMBINE ALL CAMPAIGN DATA
   ═══════════════════════════════════════════════════════════════════════════ */

data CAMPAIGNS_TO_ADOBE;
    set _tabpass_:
        _tabdrop_:;
run;

proc sql noprint;
    select count(*) into :camp_rows trimmed
    from CAMPAIGNS_TO_ADOBE;
quit;

%put CAMPAIGNS_TO_ADOBE rows: &camp_rows;

title "DEBUG 2 - CAMPAIGNS_TO_ADOBE: Rows by Campaign and Product Code";
proc sql;
    select Campaign_Name,
           product_code,
           count(*)                         as Row_Count,
           sum(case when drop_reason = ''
                    then 1 else 0 end)      as Passed,
           sum(case when drop_reason ne ''
                    then 1 else 0 end)      as Dropped,
           min(Date_to_adobe) format=date9. as First_Batch,
           max(Date_to_adobe) format=date9. as Last_Batch
    from CAMPAIGNS_TO_ADOBE
    group by Campaign_Name, product_code
    order by Campaign_Name, product_code;
quit;
title;

proc sql noprint;
    select min(Date_to_adobe) format date9.
    into   :min_date trimmed
    from   CAMPAIGNS_TO_ADOBE;
quit;

%put Min date: &min_date;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 10: ADOBE SENDS
   ─ Window changed from 60 days to 2 days
   ─ answer column retained for open tracking
   ═══════════════════════════════════════════════════════════════════════════ */

data APNS_sends_campaigns
    (keep=cust_no mucn product_code Date_loaded Time
          Drop_reason brand Delivery_code distribution_status answer);
    set APNS.apn_sends_and_feedback;
    where product_code in (&product_list.)
      and datepart(Distribution_date) >= "&min_date."d;
    Brand         = substr(mucn, 1, 3);
    Drop_reason   = "";
    Date_loaded   = datepart(Distribution_date);
    format Date_loaded date9.;
    Time          = timepart(Distribution_date);
    format Time time9.;
    Delivery_code = UPCASE(Delivery_code);
run;

proc sort data=APNS_sends_campaigns nodupkey;
    by cust_no product_code date_loaded;
run;

proc sql noprint;
    select count(*) into :sends_rows trimmed
    from APNS_sends_campaigns;
quit;

%put Adobe sends after dedup: &sends_rows;

title "DEBUG 3 - Adobe Sends by Product Code";
proc sql;
    select product_code,
           count(*)                         as Row_Count,
           min(Date_loaded) format=date9.   as First_Send,
           max(Date_loaded) format=date9.   as Last_Send
    from APNS_sends_campaigns
    group by product_code
    order by product_code;
quit;
title;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 11: ADOBE DROP-OFFS
   ═══════════════════════════════════════════════════════════════════════════ */

data Adobe_recent_drops;
    set APNS.adobe_drop_offs_data;
    where product_code in (&product_list.)
      and datepart(Date_loaded) >= "&min_date."d;
    cust_no       = ucn;
    Date_loaded   = datepart(Date_loaded);
    format Date_loaded date9.;
    Time          = timepart(Date_loaded);
    format Time time9.;
    Brand         = substr(mucn, 1, 3);
    Delivery_code = "";
run;

proc sql noprint;
    select count(*) into :drops_rows trimmed
    from Adobe_recent_drops;
quit;

%put Adobe drop-offs: &drops_rows;

title "DEBUG 4 - Adobe Drop-offs by Product Code";
proc sql;
    select product_code,
           count(*)                         as Row_Count,
           min(Date_loaded) format=date9.   as First_Drop,
           max(Date_loaded) format=date9.   as Last_Drop
    from Adobe_recent_drops
    group by product_code
    order by product_code;
quit;
title;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 12: COMBINE ADOBE DATA
   ═══════════════════════════════════════════════════════════════════════════ */

data adobe_to_clients_step;
    length mucn                $28
           product_code        $29
           drop_reason         $50
           distribution_status $43
           answer              $815;
    set Adobe_recent_drops
        APNS_sends_campaigns;
run;

data adobe_to_clients_final (drop=etl_source_data etl_date daymonth);
    set adobe_to_clients_step;
    if drop_reason  = "" then success = 1; else success = 0;
    if drop_reason ne "" then drop    = 1; else drop    = 0;
run;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 13: OPTIMISE STEP
   ═══════════════════════════════════════════════════════════════════════════ */

data campaigns_to_adobe_step
    (keep=Optimize sub_segment Drop_reason product_code
          cust_no Date_to_adobe Time_created_to_adobe
          Campaign_Name mucn success_to_adobe drop_to_adobe);
    set CAMPAIGNS_TO_ADOBE;
    if drop_reason ne "" then optimize = drop_reason; else optimize = "Sent";
    if drop_reason  = "" then success_to_adobe = 1;   else success_to_adobe = 0;
    if drop_reason ne "" then drop_to_adobe    = 1;   else drop_to_adobe    = 0;
run;

data campaigns_to_adobe_renamed;
    set campaigns_to_adobe_step;
    rename Drop_Reason   = Drop_reason_to_adobe;
    rename mucn          = mucn_to_adobe;
    rename product_code  = product_code_to_adobe;
    rename Campaign_Name = Campaign_Name_to_adobe;
run;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 14: ADOBE CLASSIFICATION
   ═══════════════════════════════════════════════════════════════════════════ */

data adobe_to_clients_step2 (drop=success drop);
    length Adobe         $50
           Client        $50
           testindicator $6;
    set adobe_to_clients_final;
    if upcase(delivery_code) = "TEST"
        then Adobe = "TEST";
    else if delivery_code ne ""
        then Adobe = "Loaded";
    else
        Adobe = drop_reason;

    if upcase(delivery_code) = "TEST"
        then Client = "TEST";
    else if upcase(distribution_status) = "SENT"
        then Client = "Sent to Client";
    else if upcase(distribution_status) = "SENT TO THE SERVICE PROVIDER"
        then Client = "Sent to Provider";
    else if upcase(distribution_status) = "PENDING"
        then Client = "Pending";
    else if upcase(distribution_status) = "DELIVERY CANCELED"
        then Client = "Delivery Canceled";
    else
        Client = drop_reason;
run;

proc sql;
    create table adobe_delivery_test as
    select distinct cust_no, date_loaded, product_code,
                    "TEST" as testindicator
    from adobe_to_clients_step2
    where upcase(delivery_code) = "TEST";
quit;

proc sql;
    create table adobe_final_new as
    select a.*, b.testindicator
    from adobe_to_clients_step2 a
    left join adobe_delivery_test b
        on  a.cust_no      = b.cust_no
        and a.date_loaded  = b.date_loaded
        and a.product_code = b.product_code;
quit;

data adobe_final_table_clients;
    length testindicator $6;
    set adobe_final_new;
    if strip(testindicator) = "TEST" then do;
        testindicator = "TEST";
        Adobe         = "TEST";
        Client        = "TEST";
    end;
    else testindicator = "Actual";
    rename cust_no = cust_no2;
run;

proc sql noprint;
    select count(*) into :final_rows trimmed
    from adobe_final_table_clients;
quit;

%put Adobe final table rows: &final_rows;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 15: FINAL JOIN - OPTIMISE + ADOBE
   ─ Window is NOW 2 DAYS (changed from 60)
   ═══════════════════════════════════════════════════════════════════════════ */

proc sql;
    create table joining as
    select *
    from campaigns_to_adobe_renamed a
    left join adobe_final_table_clients b
        on  a.cust_no               = b.cust_no2
        and a.product_code_to_adobe  = b.product_code
        and (b.date_loaded between a.date_to_adobe and a.date_to_adobe + 2);
        /*  ^^^ 2-DAY WINDOW (was 60) ^^^ */
quit;

data APN_POT_Step1
    (drop=Time product_code mucn mucn_to_adobe
          success_to_adobe drop_to_adobe);
    length Adobe  $50
           Client $50;
    set joining;

    if missing(cust_no2) and Optimize = "Sent"
        then Adobe = "Not loaded into Adobe within 2 days";
    if missing(cust_no2) and Optimize = "Sent"
        and intck('day', date_to_adobe, today()) <= 2
        and missing(Date_loaded)
        then Adobe = "Sending to Adobe";

    date_Diff = intck('day', date_to_adobe, date_loaded);
run;

proc sort data=APN_POT_Step1;
    by cust_no product_code_to_adobe date_to_adobe descending date_loaded;
run;

proc sort data=APN_POT_Step1 nodupkey
    out=APN_POT_Final;
    by cust_no product_code_to_adobe date_to_adobe;
run;

proc sql noprint;
    select count(*) into :pot_rows trimmed
    from APN_POT_Final;
quit;

%put APN_POT_Final rows before target capping: &pot_rows;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 15B: DISTINCT CUSTOMERS LOADED INTO ADOBE
   ═══════════════════════════════════════════════════════════════════════════ */

proc sql;
    create table cust_loaded_summary as
    select
        Campaign_Name_to_adobe,
        product_code_to_adobe,
        date_to_adobe                        as Batch_Date,
        count(distinct cust_no)              as Loaded_Adobe
                                             label = "Distinct Customers Loaded into Adobe"
    from APN_POT_Final
    where Adobe = "Loaded"
    group by Campaign_Name_to_adobe, product_code_to_adobe, date_to_adobe;
quit;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 15C: TARGET CAPPING AND TRACKING
   ─ Joins target from Excel config onto every lead
   ─ Ranks leads within Campaign + Product + Batch by date (earliest first)
   ─ Flags each lead as Within_Target / Over_Target / No_Target
   ─ Derives Target_Status shown in Power BI
   ═══════════════════════════════════════════════════════════════════════════ */

/* Step 1 – attach target from config lookup */
proc sql;
    create table APN_POT_Targeted as
    select  a.*,
            coalesce(b.Target_Leads, 0) as Target_Leads
                    label = "Target Leads (from Config)"
                    format = comma12.
    from APN_POT_Final a
    left join target_lookup b
        on  upcase(a.Campaign_Name_to_adobe) contains upcase(b.Campaign_Code)
        and upcase(a.product_code_to_adobe)  = upcase(b.Product_Code);
quit;

/* Step 2 – sort so earliest batch / lowest cust_no is ranked first */
proc sort data=APN_POT_Targeted;
    by Campaign_Name_to_adobe product_code_to_adobe date_to_adobe cust_no;
run;

/* Step 3 – rolling count of "Sent to Client" per Campaign + Product + Batch
             determines whether each lead falls inside or outside the target   */
data APN_POT
    (drop=_sent_count);
    length Within_Target  8
           Target_Status  $40;
    set APN_POT_Targeted;
    by Campaign_Name_to_adobe product_code_to_adobe date_to_adobe;

    /* Reset counter at start of each Campaign + Product + Batch group */
    retain _sent_count 0;
    if first.date_to_adobe then _sent_count = 0;

    /* Increment only for actual sends to client */
    if Client = "Sent to Client" then _sent_count + 1;

    /* Determine target flag */
    if Target_Leads <= 0 then do;
        Within_Target = .;
        Target_Status = "No Target Set";
    end;
    else if Client ne "Sent to Client" then do;
        Within_Target = .;
        Target_Status = "Not a Client Send";
    end;
    else if _sent_count <= Target_Leads then do;
        Within_Target = 1;
        Target_Status = "Within Target";
    end;
    else do;
        Within_Target = 0;
        Target_Status = "Over Target";
    end;

    label Within_Target = "Within Target Flag (1=Yes 0=No)"
          Target_Status = "Target Status";
run;

proc sql noprint;
    select count(*) into :pot_rows trimmed
    from APN_POT;
quit;

%put APN_POT rows after target capping: &pot_rows;

title "DEBUG 5 - APN_POT: Distribution by Campaign and Status";
proc sql;
    select Campaign_Name_to_adobe   as Campaign,
           Optimize,
           Adobe,
           Client,
           count(*) as Row_Count
    from APN_POT
    group by Campaign_Name_to_adobe, Optimize, Adobe, Client
    order by Campaign_Name_to_adobe, Optimize, Row_Count desc;
quit;
title;

title "DEBUG 5B - Target Tracking Summary by Campaign and Product";
proc sql;
    select Campaign_Name_to_adobe   as Campaign   length=60,
           product_code_to_adobe    as Product    length=30,
           date_to_adobe                          format=date9. as Batch_Date,
           max(Target_Leads)        as Target,
           sum(case when Client = "Sent to Client"
                    then 1 else 0 end) as Total_Sent,
           sum(case when Target_Status = "Within Target"
                    then 1 else 0 end) as Sent_Within_Target,
           sum(case when Target_Status = "Over Target"
                    then 1 else 0 end) as Sent_Over_Target,
           case when max(Target_Leads) > 0
                then calculated Sent_Within_Target
                               / max(Target_Leads) * 100
                else .
           end                                    format=8.1
                                                  as Pct_of_Target
    from APN_POT
    where Target_Leads > 0
    group by Campaign_Name_to_adobe, product_code_to_adobe, date_to_adobe
    order by Campaign_Name_to_adobe, product_code_to_adobe, date_to_adobe;
quit;
title;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 16: SUMMARY TABLE FOR POWER BI
   ─ Includes all original metrics PLUS target tracking columns
   ═══════════════════════════════════════════════════════════════════════════ */

proc sql;
    create table APN_POT_SUMMARY as
    select
        Campaign_Name_to_adobe                              as Campaign_Name
                                                            length = 100
                                                            label  = "Campaign Name",
        product_code_to_adobe                               as Product_Code
                                                            length = 29
                                                            label  = "Product Code",
        date_to_adobe                                       as Batch_Date
                                                            format = date9.
                                                            label  = "Batch Date",
        Optimize,
        Adobe,
        Client,
        testindicator,
        max(Target_Leads)                                   as Target_Leads
                                                            format = comma12.
                                                            label  = "Target Leads",

        count(*)                                            as Record_Count
                                                            label = "Record Count",

        sum(case when Optimize  = "Sent"
                 then 1 else 0 end)                         as Passed_Optimise
                                                            label = "Passed Optimise",
        sum(case when Optimize ne "Sent"
                 then 1 else 0 end)                         as Dropped_Optimise
                                                            label = "Dropped Optimise",

        sum(case when Adobe in ("ADB_NoConsent","ADB_NoChannel",
                                "ADB_NotInSegment","ADB_NoBrand",
                                "NO CHANNEL","INCORRECT SEGMENT")
                 then 1 else 0 end)                         as Dropped_Adobe
                                                            label = "Dropped by Adobe",
        sum(case when Adobe = "Sending to Adobe"
                 then 1 else 0 end)                         as Sending_to_Adobe
                                                            label = "Sending to Adobe",
        sum(case when Adobe contains "Not loaded"
                 then 1 else 0 end)                         as Not_Loaded
                                                            label = "Not Loaded (2d)",

        sum(case when Client = "Sent to Client"
                 then 1 else 0 end)                         as Sent_to_Client
                                                            label = "Sent to Client",
        sum(case when Client = "Sent to Provider"
                 then 1 else 0 end)                         as Sent_to_Provider
                                                            label = "Sent to Provider",
        sum(case when Client = "Pending"
                 then 1 else 0 end)                         as Pending_Client
                                                            label = "Pending",
        sum(case when Client = "Delivery Canceled"
                 then 1 else 0 end)                         as Delivery_Canceled
                                                            label = "Delivery Canceled",

        /* ── Target tracking columns ─────────────────────────────── */
        sum(case when Target_Status = "Within Target"
                 then 1 else 0 end)                         as Sent_Within_Target
                                                            label = "Sent to Client (Within Target)",
        sum(case when Target_Status = "Over Target"
                 then 1 else 0 end)                         as Sent_Over_Target
                                                            label = "Sent to Client (Over Target)",
        case when max(Target_Leads) > 0
             then sum(case when Target_Status = "Within Target"
                           then 1 else 0 end)
                  / max(Target_Leads) * 100
             else .
        end                                                 as Target_Pct_Achieved
                                                            format = 8.1
                                                            label  = "% of Target Achieved",
        case when max(Target_Leads) > 0
             then max(Target_Leads)
                  - sum(case when Target_Status = "Within Target"
                             then 1 else 0 end)
             else .
        end                                                 as Target_Remaining
                                                            format = comma12.
                                                            label  = "Leads Still Needed to Hit Target",
        /* ── Open tracking ───────────────────────────────────────── */
        sum(case when Client = "Sent to Client"
                 and answer is not null
                 and strip(answer) ne ""
                 then 1 else 0 end)                         as Total_Opened
                                                            label = "Opened",
        sum(case when Client = "Sent to Client"
                 then 1 else 0 end)                         as Sent_to_Client_Count
                                                            label = "Sent to Client Count",

        min(date_loaded)                                    as First_Date_Loaded
                                                            format = date9.
                                                            label  = "First Date Loaded",
        max(date_loaded)                                    as Last_Date_Loaded
                                                            format = date9.
                                                            label  = "Last Date Loaded",
        min(date_Diff)                                      as Min_Days_to_Adobe
                                                            label  = "Min Days to Adobe",
        max(date_Diff)                                      as Max_Days_to_Adobe
                                                            label  = "Max Days to Adobe",
        mean(date_Diff)                                     as Avg_Days_to_Adobe
                                                            format = 8.1
                                                            label  = "Avg Days to Adobe"

    from APN_POT
    group by
        Campaign_Name_to_adobe,
        product_code_to_adobe,
        date_to_adobe,
        Optimize,
        Adobe,
        Client,
        testindicator
    order by
        Campaign_Name_to_adobe,
        product_code_to_adobe,
        date_to_adobe;
quit;

/* Open Rate */
data APN_POT_SUMMARY;
    set APN_POT_SUMMARY;
    if Sent_to_Client_Count > 0
        then Open_Rate = (Total_Opened / Sent_to_Client_Count) * 100;
    else Open_Rate = .;
    format Open_Rate 8.2;
    label  Open_Rate = "Open Rate (%)";
run;

/* Join distinct customer counts */
proc sql;
    create table APN_POT_SUMMARY_FINAL as
    select
        a.*,
        coalesce(b.Loaded_Adobe, 0) as Loaded_Adobe
                 label = "Distinct Customers Loaded into Adobe"
    from APN_POT_SUMMARY a
    left join cust_loaded_summary b
        on  a.Campaign_Name = b.Campaign_Name_to_adobe
        and a.Product_Code  = b.product_code_to_adobe
        and a.Batch_Date    = b.Batch_Date;
quit;

proc sql noprint;
    select count(*) into :summary_rows trimmed
    from APN_POT_SUMMARY_FINAL;
quit;

%put APN_POT_SUMMARY_FINAL rows: &summary_rows;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 16B: TARGET TRACKING TABLE
   ─ One row per Campaign + Product + Batch – purpose-built for Power BI
   ─ target visuals (gauges, progress bars, over/under indicators)
   ═══════════════════════════════════════════════════════════════════════════ */

proc sql;
    create table TARGET_TRACKING as
    select
        Campaign_Name_to_adobe                          as Campaign_Name
                                                        length = 100
                                                        label  = "Campaign Name",
        product_code_to_adobe                           as Product_Code
                                                        length = 29
                                                        label  = "Product Code",
        date_to_adobe                                   as Batch_Date
                                                        format = date9.
                                                        label  = "Batch Date",
        max(Target_Leads)                               as Target_Leads
                                                        format = comma12.
                                                        label  = "Target Leads",
        sum(case when Client = "Sent to Client"
                 then 1 else 0 end)                     as Total_Sent_to_Client
                                                        format = comma12.
                                                        label  = "Total Sent to Client",
        sum(case when Target_Status = "Within Target"
                 then 1 else 0 end)                     as Sent_Within_Target
                                                        format = comma12.
                                                        label  = "Sent Within Target",
        sum(case when Target_Status = "Over Target"
                 then 1 else 0 end)                     as Sent_Over_Target
                                                        format = comma12.
                                                        label  = "Sent Over Target",
        case when max(Target_Leads) > 0
             then max(Target_Leads)
                  - sum(case when Target_Status = "Within Target"
                             then 1 else 0 end)
             else .
        end                                             as Target_Remaining
                                                        format = comma12.
                                                        label  = "Leads Still Needed",
        case when max(Target_Leads) > 0
             then sum(case when Target_Status = "Within Target"
                           then 1 else 0 end)
                  / max(Target_Leads) * 100
             else .
        end                                             as Target_Pct_Achieved
                                                        format = 8.1
                                                        label  = "% of Target Achieved",
        case
            when max(Target_Leads) <= 0
                then "No Target"
            when sum(case when Target_Status = "Within Target"
                          then 1 else 0 end)
                 >= max(Target_Leads)
                then "Target Met"
            when sum(case when Target_Status = "Within Target"
                          then 1 else 0 end)
                 >= max(Target_Leads) * 0.8
                then "On Track (>=80%)"
            when sum(case when Target_Status = "Within Target"
                          then 1 else 0 end)
                 >= max(Target_Leads) * 0.5
                then "At Risk (50-79%)"
            else "Behind (<50%)"
        end                                             as Target_RAG
                                                        length = 30
                                                        label  = "Target RAG Status",
        today()                                         as Run_Date
                                                        format = date9.
                                                        label  = "Run Date"

    from APN_POT
    where Target_Leads > 0
    group by Campaign_Name_to_adobe,
             product_code_to_adobe,
             date_to_adobe
    order by Campaign_Name_to_adobe,
             product_code_to_adobe,
             date_to_adobe;
quit;

proc sql noprint;
    select count(*) into :track_rows trimmed
    from TARGET_TRACKING;
quit;

%put TARGET_TRACKING rows: &track_rows;

title "DEBUG 6 - Target Tracking RAG Summary";
proc print data=TARGET_TRACKING noobs label; run;
title;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 17: LOAD TO PRODUCTION
   ═══════════════════════════════════════════════════════════════════════════ */

%macro LoadTable(Table=, Target=);
    %if %sysfunc(exist(&Table.)) %then %do;

        proc sql noprint;
            select count(*) into :row_count trimmed
            from &Table.;
        quit;

        %if &row_count = 0 %then %do;
            %put ERROR: &Table. has ZERO rows. Load ABORTED.;
            %abort cancel;
        %end;
        %else %do;
            %put NOTE: &Table. has &row_count rows. Loading to STI_PBI.&Target.;
            proc sql;
                drop table STI_PBI.&Target.;
                create table STI_PBI.&Target. as
                select * from &Table.;
            quit;
            %put NOTE: STI_PBI.&Target. loaded successfully.;
        %end;

    %end;
    %else %do;
        %put ERROR: Work table &Table. does not exist. Cannot load.;
        %abort cancel;
    %end;
%mend;

%LoadTable(Table=APN_POT,               Target=APN_POT);
%LoadTable(Table=APN_POT_SUMMARY_FINAL, Target=APN_POT_SUMMARY);
%LoadTable(Table=TARGET_TRACKING,       Target=APN_TARGET_TRACKING);


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 18: CAPTURE POST-RUN STATE
   ═══════════════════════════════════════════════════════════════════════════ */

proc sql noprint;
    select max(date_to_adobe) format date9.
    into   :New_date trimmed
    from   APN_POT;
quit;

proc sql noprint;
    select max(time_created_to_adobe) format time9.
    into   :New_time trimmed
    from   APN_POT
    where  date_to_adobe = "&New_date."d;
quit;

proc sql noprint;
    select count(cust_no)
    into   :New_records trimmed
    from   APN_POT;
quit;

%put Post-run state: &New_date &New_time  Records: &New_records;

%let Diff_Records = %sysevalf(&New_records - &Old_records);
%put Records added this run: &Diff_Records;

/* Target summary for email */
proc sql noprint;
    select count(*)
    into   :camps_met trimmed
    from   TARGET_TRACKING
    where  Target_RAG = "Target Met";

    select count(*)
    into   :camps_behind trimmed
    from   TARGET_TRACKING
    where  Target_RAG = "Behind (<50%)";

    select count(*)
    into   :camps_total trimmed
    from   TARGET_TRACKING;
quit;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 19: EMAIL NOTIFICATION
   ─ Now includes target achievement summary
   ═══════════════════════════════════════════════════════════════════════════ */

%macro EMAIL;

    %if &Old_date = &New_date and &Old_time = &New_time %then %do;

        FILENAME EML EMAIL
            to   = "Morris.Nkomo@fnb.co.za"
            cc   = "dlfnbstioperationalanalytics@fnb.co.za"
            from = 'dlfnbstioperationalanalytics@fnb.co.za';
        DATA _NULL_;
            FILE EML;
            PUT "Hi,";
            PUT " ";
            PUT "The APN POT script ran with no table update,";
            PUT "please check log for any possible failure(s).";
            PUT " ";
            PUT "Max Date in table before run: &Old_date";
            PUT "Max Time in table before run: &Old_time";
            PUT "Max Date in table after run:  &New_date";
            PUT "Max Time in table after run:  &New_time";
            PUT " ";
            PUT "Adobe match window: 2 days";
            PUT " ";
            PUT "The APN Dashboard does not require refreshing.";
            PUT " ";
            PUT "Kind Regards";
            PUT "Morris";
        RUN;

    %end;

    %else %if &Old_date ne &New_date or &Old_time ne &New_time %then %do;

        FILENAME EML EMAIL
            to   = "Morris.Nkomo@fnb.co.za"
            cc   = "dlfnbstioperationalanalytics@fnb.co.za"
            from = 'dlfnbstioperationalanalytics@fnb.co.za';
        DATA _NULL_;
            FILE EML;
            PUT "Hi,";
            PUT " ";
            PUT "APN POT script ran with a table update.";
            PUT " ";
            PUT "Max Date in table before run: &Old_date";
            PUT "Max Time in table before run: &Old_time";
            PUT "Max Date in table after run:  &New_date";
            PUT "Max Time in table after run:  &New_time";
            PUT "Records added this run:       &Diff_Records";
            PUT " ";
            PUT "Adobe match window: 2 days";
            PUT " ";
            PUT "─── Target Achievement Summary ───────────────────────";
            PUT "Campaign-product batches tracked: &camps_total";
            PUT "Targets met:                      &camps_met";
            PUT "Targets behind (<50%):            &camps_behind";
            PUT "See APN_TARGET_TRACKING table for full detail.";
            PUT " ";
            PUT "The APN Dashboard can be refreshed.";
            PUT " ";
            PUT "Kind Regards";
            PUT "Morris";
        RUN;

    %end;

    %else %if %sysfunc(exist(STI_PBI.APN_POT)) = 0 %then %do;

        FILENAME EML EMAIL
            to      = "Morris.Nkomo@fnb.co.za"
            cc      = "dlfnbstioperationalanalytics@fnb.co.za"
            from    = 'dlfnbstioperationalanalytics@fnb.co.za'
            subject = "Table Missing";
        DATA _NULL_;
            FILE EML;
            PUT "Good Day,";
            PUT " ";
            PUT "Kindly note that the APN_POT table is missing, currently investigating.";
            PUT " ";
            PUT "Kind Regards,";
            PUT "Morris";
        RUN;

    %end;

%mend email;
%email;
