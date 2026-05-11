/* ============================================================
   ARCHIVE LIBRARY AUDIT — ALL TABLES
   See everything that exists in the archive libs,
   how far back they go, and what campaigns are present.
   ============================================================ */

libname Pass6 "/data/fnb/clb/archive/5_optimise/passed_phase1";
libname Drop6 "/data/fnb/clb/archive/5_optimise/dropped_phase1";


/* ============================================================
   STEP 1: PULL EVERY TABLE IN BOTH ARCHIVE LIBS
   No name filter — see everything
   ============================================================ */

proc sql;
    create table ALL_ARCH_TABLES as
    select
        libname                         as Library,
        memname                         as Table_Name,
        nobs                            as Row_Count             label = "Row Count",
        datepart(crdate)                as SAS_Create_Date
                                        format = date9.
                                        label  = "SAS Catalog Create Date",
        crdate                          as SAS_Create_DT
                                        format = datetime20.
                                        label  = "SAS Catalog Create DT"
    from dictionary.tables
    where libname in ('PASS6','DROP6')
    order by Library, Table_Name;
quit;

proc sql noprint;
    select count(*) into :n_total trimmed from ALL_ARCH_TABLES;
quit;
%put Total tables found across both archive libs: &n_total;


/* ============================================================
   STEP 2: EXTRACT CAMPAIGN PREFIX + PARSE DATE FROM NAME
   Assumes table names start with an 8-char campaign code
   e.g. CMA09319_20250115_1430  or  CMA0931920250115
   ============================================================ */

data ALL_ARCH_PARSED;
    set ALL_ARCH_TABLES;

    length Campaign_Prefix $8  Name_Date_Raw $8  Name_Time_Raw $4;

    /* First 8 chars = campaign code */
    Campaign_Prefix = substr(Table_Name, 1, 8);

    /* Parse date from table name */
    if index(Table_Name, '_') > 0 then do;
        Name_Date_Raw = scan(Table_Name, -2, '_');
        Name_Time_Raw = scan(Table_Name, -1, '_');

        if lengthn(Name_Date_Raw) = 8 and notdigit(compress(Name_Date_Raw)) = 0
            then Name_Date = input(Name_Date_Raw, YYMMDD8.);
        else Name_Date = .;

        if lengthn(Name_Time_Raw) = 4 and notdigit(compress(Name_Time_Raw)) = 0
            then Name_Time = input(
                                cats(substr(Name_Time_Raw,1,2),':',
                                     substr(Name_Time_Raw,3,2),':00'),
                             HHMMSS8.);
        else Name_Time = .;
    end;
    else do;
        Name_Date_Raw = substr(Table_Name, 9, 8);
        Name_Time_Raw = '';
        if notdigit(compress(Name_Date_Raw)) = 0
            then Name_Date = input(Name_Date_Raw, YYMMDD8.);
        else Name_Date = .;
        Name_Time = .;
    end;

    format Name_Date date9.  Name_Time time9.;
    label
        Campaign_Prefix = "Campaign Prefix (first 8 chars)"
        Name_Date       = "Date from Table Name"
        Name_Time       = "Time from Table Name";
run;


/* ============================================================
   STEP 3: SUMMARY — EVERY UNIQUE CAMPAIGN PREFIX FOUND
   One row per campaign prefix, shows full date range
   ============================================================ */

proc sql;
    create table ARCH_CAMPAIGN_SUMMARY as
    select
        Library,
        Campaign_Prefix,
        count(*)                as Table_Count   label = "# Tables",
        sum(Row_Count)          as Total_Rows    label = "Total Rows",
        min(Name_Date)          as Earliest      format = date9. label = "Earliest (table name)",
        max(Name_Date)          as Latest        format = date9. label = "Latest (table name)",
        intck('day',
              min(Name_Date),
              max(Name_Date))   as Span_Days     label = "Span (days)",
        min(SAS_Create_Date)    as First_Created format = date9. label = "First SAS Create Date",
        max(SAS_Create_Date)    as Last_Created  format = date9. label = "Last SAS Create Date"
    from ALL_ARCH_PARSED
    group by Library, Campaign_Prefix
    order by Library, Earliest;
quit;


/* ============================================================
   STEP 4: OVERALL LIBRARY RANGE
   ============================================================ */

proc sql;
    create table ARCH_LIB_SUMMARY as
    select
        Library,
        count(*)                as Table_Count   label = "# Tables",
        min(Name_Date)          as Earliest      format = date9. label = "Earliest Table (by name)",
        max(Name_Date)          as Latest        format = date9. label = "Latest Table (by name)",
        intck('month',
              min(Name_Date),
              max(Name_Date))   as Span_Months   label = "Span (months)",
        intck('day',
              min(Name_Date),
              max(Name_Date))   as Span_Days     label = "Span (days)"
    from ALL_ARCH_PARSED
    group by Library
    order by Library;
quit;


/* ============================================================
   STEP 5: PRINT
   ============================================================ */

title1 "Archive Library Audit — All Tables, No Filter";

title2 "Overall Library Date Range";
proc print data=ARCH_LIB_SUMMARY noobs label;
    var Library Table_Count Earliest Latest Span_Months Span_Days;
run;

title2 "Every Campaign Prefix Found (sorted oldest to newest)";
proc print data=ARCH_CAMPAIGN_SUMMARY noobs label;
    var Library Campaign_Prefix Table_Count Total_Rows
        Earliest Latest Span_Days
        First_Created Last_Created;
run;

title2 "Full Table Listing (sorted oldest to newest)";
proc print data=ALL_ARCH_PARSED noobs label;
    var Library Campaign_Prefix Table_Name
        Name_Date Name_Time Row_Count SAS_Create_Date;
run;

title;

%put =======================================================;
%put ARCHIVE AUDIT COMPLETE;
%put ARCH_LIB_SUMMARY      - overall date range per lib;
%put ARCH_CAMPAIGN_SUMMARY - every campaign prefix found;
%put ALL_ARCH_PARSED       - every single table, oldest first;
%put =======================================================;
