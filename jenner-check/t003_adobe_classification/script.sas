/* APN POT pipeline — Section 14: Adobe / Client classification.
   The job maps each record's delivery_code + distribution_status into the
   Adobe and Client status labels, then flags TEST sends with a self-join
   so test rows can be carried through separately from production rows.
   The upstream input (adobe_to_clients_final, itself built from live Adobe
   feeds) is replaced here with a small inline sample exercising every
   branch: a TEST delivery, a sent-to-client row, a provider hand-off, a
   pending row, a cancellation, and a dropped record. */

data adobe_to_clients_final;
    length cust_no 8 date_loaded 8 product_code $10
           delivery_code $20 distribution_status $43 drop_reason $50;
    format date_loaded date9.;
    infile datalines dsd truncover;
    input cust_no date_loaded :date9. product_code $
          delivery_code $ distribution_status $ drop_reason $;
    datalines;
3001,05JAN2026,FNR001,TEST,SENT,
3002,05JAN2026,FNR001,DELIVERED,SENT,
3003,06JAN2026,LIF010,DELIVERED,SENT TO THE SERVICE PROVIDER,
3004,06JAN2026,LIF010,DELIVERED,PENDING,
3005,07JAN2026,FNR002,DELIVERED,DELIVERY CANCELED,
3006,07JAN2026,FNR002,,,No Consent
;
run;

/* SECTION 14: ADOBE CLASSIFICATION */
data adobe_to_clients_step2;
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

title "Adobe / Client classification result";
proc print data=adobe_final_table_clients noobs; run;
title;
