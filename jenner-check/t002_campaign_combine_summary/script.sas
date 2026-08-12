/* APN POT pipeline — Section 9 + Section 12 (DEBUG 2).
   The job reads per-campaign "pass" and "drop" tables from production
   libraries, stacks them into CAMPAIGNS_TO_ADOBE, then summarises rows by
   campaign and product with passed/dropped counts and the batch-date span.
   Here two small pass/drop tables stand in for the discovered library
   members so the SET-stacking + group-by-with-CASE summary runs intact. */

data _tabpass_1;
    length CUST_NO 8 Product_Code $10 Drop_Reason $50 sub_segment $20
           Campaign_Name $30 Brand $3 MUCN $12;
    format Date_to_adobe date9.;
    infile datalines dsd truncover;
    input CUST_NO Product_Code $ Drop_Reason $ sub_segment $
          Campaign_Name $ Brand $ MUCN $ Date_to_adobe :date9.;
    datalines;
1001,FNR001,,Mass,APN_FUNERAL,FNB,FNB12345678,01JAN2026
1002,FNR001,,Mass,APN_FUNERAL,FNB,FNB12345679,01JAN2026
1003,FNR002,,Affluent,APN_FUNERAL,FNB,FNB12345680,02JAN2026
1004,LIF010,,Mass,APN_LIFE,FNB,FNB12345681,03JAN2026
;
run;

data _tabdrop_1;
    length CUST_NO 8 Product_Code $10 Drop_Reason $50 sub_segment $20
           Campaign_Name $30 Brand $3 MUCN $12;
    format Date_to_adobe date9.;
    infile datalines dsd truncover;
    input CUST_NO Product_Code $ Drop_Reason $ sub_segment $
          Campaign_Name $ Brand $ MUCN $ Date_to_adobe :date9.;
    datalines;
2001,FNR001,No Consent,Mass,APN_FUNERAL,FNB,FNB22345678,01JAN2026
2002,LIF010,No Channel,Mass,APN_LIFE,FNB,FNB22345679,03JAN2026
2003,LIF010,No Channel,Affluent,APN_LIFE,FNB,FNB22345680,04JAN2026
;
run;

/* SECTION 9: COMBINE ALL CAMPAIGN DATA */
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
           min(Date_to_adobe) as First_Batch format=date9.,
           max(Date_to_adobe) as Last_Batch  format=date9.
    from CAMPAIGNS_TO_ADOBE
    group by Campaign_Name, product_code
    order by Campaign_Name, product_code;
quit;
title;

proc sql noprint;
    select put(min(Date_to_adobe), date9.)
    into   :min_date trimmed
    from   CAMPAIGNS_TO_ADOBE;
quit;

%put Min date: &min_date;
