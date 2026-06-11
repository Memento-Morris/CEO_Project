/* APN POT pipeline — Section 16: the Power BI summary table.
   This is the reporting heart of the job: one grouped PROC SQL that rolls
   APN_POT up by campaign / product / batch-date / status and emits the
   passed-vs-dropped, sent / provider / pending / cancelled, and opened
   counts that feed the dashboard, followed by the open-rate DATA step.
   APN_POT (built upstream from the optimise + Adobe join) is supplied here
   as a small inline sample so the full aggregation runs standalone. */

data APN_POT;
    length cust_no 8
           Campaign_Name_to_adobe $100
           product_code_to_adobe  $29
           Optimize $50 Adobe $50 Client $50 testindicator $6
           answer $815;
    format date_to_adobe date9. date_loaded date9.;
    infile datalines dsd truncover;
    input cust_no Campaign_Name_to_adobe $ product_code_to_adobe $
          date_to_adobe :date9. Optimize $ Adobe $ Client $
          testindicator $ date_loaded :date9. date_Diff answer $;
    datalines;
1001,APN_FUNERAL,FNR001,01JAN2026,Sent,Loaded,Sent to Client,Actual,03JAN2026,2,opened
1002,APN_FUNERAL,FNR001,01JAN2026,Sent,Loaded,Sent to Client,Actual,03JAN2026,2,
1003,APN_FUNERAL,FNR001,01JAN2026,Sent,Loaded,Sent to Provider,Actual,04JAN2026,3,
1004,APN_FUNERAL,FNR001,01JAN2026,No Consent,ADB_NoConsent,No Consent,Actual,.,.,
1005,APN_LIFE,LIF010,03JAN2026,Sent,Loaded,Sent to Client,Actual,05JAN2026,2,opened
1006,APN_LIFE,LIF010,03JAN2026,Sent,Loaded,Pending,Actual,06JAN2026,3,
1007,APN_LIFE,LIF010,03JAN2026,Sent,Sending to Adobe,Pending,Actual,.,.,
1008,APN_LIFE,LIF010,03JAN2026,No Channel,NO CHANNEL,No Channel,Actual,.,.,
;
run;

/* SECTION 16: SUMMARY TABLE FOR POWER BI */
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

        sum(case when Client = "Sent to Client"
                 then 1 else 0 end)                         as Sent_to_Client
                                                            label = "Sent to Client",
        sum(case when Client = "Sent to Provider"
                 then 1 else 0 end)                         as Sent_to_Provider
                                                            label = "Sent to Provider",
        sum(case when Client = "Pending"
                 then 1 else 0 end)                         as Pending_Client
                                                            label = "Pending",

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

/* Calculate Open Rate */
data APN_POT_SUMMARY;
    set APN_POT_SUMMARY;
    if Sent_to_Client_Count > 0
        then Open_Rate = (Total_Opened / Sent_to_Client_Count) * 100;
    else Open_Rate = .;
    format Open_Rate 8.2;
    label  Open_Rate = "Open Rate (%)";
run;

proc sql noprint;
    select count(*) into :summary_rows trimmed
    from APN_POT_SUMMARY;
quit;

%put APN_POT_SUMMARY rows: &summary_rows;

title "APN_POT_SUMMARY - Power BI feed";
proc print data=APN_POT_SUMMARY noobs label; run;
title;
