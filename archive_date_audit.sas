/* ============================================================
   ARCHIVE DATE RANGE AUDIT
   How far back do archive tables go?
   Covers: Pass6 (passed_phase1) and Drop6 (dropped_phase1)
   ============================================================ */

libname Pass6 "/data/fnb/clb/archive/5_optimise/passed_phase1";
libname Drop6 "/data/fnb/clb/archive/5_optimise/dropped_phase1";


/* ============================================================
   STEP 1: FIND ALL MATCHING TABLES IN BOTH ARCHIVE LIBS
   ============================================================ */

proc sql;
    create table ARCH_TABLES as
    select
        libname                             as Library,
        memname                             as Table_Name,
        crdate                              as SAS_Create_DT
                                            format = datetime20.
                                            label  = "SAS Catalog Create DT",
        datepart(crdate)                    as SAS_Create_Date
                                            format = date9.
                                            label  = "SAS Catalog Create Date"
    from dictionary.tables
    where libname in ('PASS6','DROP6')
      and (
          memname like 'CMA09319%' or
          memname like 'CMA09320%' or
          memname like 'CMA10184%' or
          memname like 'CMA10251%' or
          memname like 'CMA10252%'
      )
    order by Library, Table_Name;
quit;

%put Tables found in archive: ;
proc sql noprint;
    select count(*) into :n_arch trimmed from ARCH_TABLES;
quit;
%put &n_arch total archive tables;


/* ============================================================
   STEP 2: PARSE DATE & TIME FROM TABLE NAME
   Table name format examples:
     CMA09319_20250115_1430   -> date=20250115 time=1430
     CMA0931920250115         -> date embedded at pos 9 (no underscore)
   ============================================================ */

data ARCH_TABLES_PARSED;
    set ARCH_TABLES;

    length Campaign_Label $40  Name_Date_Raw $8  Name_Time_Raw $4;

    /* Campaign label */
    if      substr(Table_Name,1,8) = 'CMA09319' then Campaign_Label = 'Instruct APN (AIP)';
    else if substr(Table_Name,1,8) = 'CMA09320' then Campaign_Label = 'Device Insurance';
    else if substr(Table_Name,1,8) = 'CMA10184' then Campaign_Label = 'eBucks Flight VP';
    else if substr(Table_Name,1,8) = 'CMA10251' then Campaign_Label = 'Start the Year Right - CAR';
    else if substr(Table_Name,1,8) = 'CMA10252' then Campaign_Label = 'Start the Year Right - LOC';

    /* Parse date from table name */
    if index(Table_Name,'_') > 0 then do;
        /* underscore-delimited: last-2 token is YYYYMMDD, last token is HHMM */
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
        /* no underscore: date starts at position 9 */
        Name_Date_Raw = substr(Table_Name, 9, 8);
        Name_Time_Raw = '';
        if notdigit(compress(Name_Date_Raw)) = 0
            then Name_Date = input(Name_Date_Raw, YYMMDD8.);
        else Name_Date = .;
        Name_Time = .;
    end;

    format Name_Date date9.  Name_Time time9.;
    label
        Name_Date = "Date Parsed from Table Name"
        Name_Time = "Time Parsed from Table Name";
run;


/* ============================================================
   STEP 3: SUMMARY - HOW FAR BACK DOES ARCHIVE GO?
   By library, and by campaign
   ============================================================ */

/* Overall range per library */
proc sql;
    create table ARCH_RANGE_BY_LIB as
    select
        Library,
        count(*)            as Table_Count          label = "# Tables",
        min(Name_Date)      as Earliest_By_Name     format = date9. label = "Earliest (from table name)",
        max(Name_Date)      as Latest_By_Name       format = date9. label = "Latest (from table name)",
        min(SAS_Create_Date)as Earliest_By_CrDate   format = date9. label = "Earliest (SAS create date)",
        max(SAS_Create_Date)as Latest_By_CrDate     format = date9. label = "Latest (SAS create date)",
        intck('month',
              min(Name_Date),
              max(Name_Date))                        as Span_Months  label = "Span (months)",
        intck('day',
              min(Name_Date),
              max(Name_Date))                        as Span_Days    label = "Span (days)"
    from ARCH_TABLES_PARSED
    group by Library
    order by Library;
quit;

/* Range per campaign, per library */
proc sql;
    create table ARCH_RANGE_BY_CAMP as
    select
        Library,
        Campaign_Label,
        count(*)            as Table_Count          label = "# Tables",
        min(Name_Date)      as Earliest             format = date9. label = "Earliest (table name)",
        max(Name_Date)      as Latest               format = date9. label = "Latest (table name)",
        intck('day',
              min(Name_Date),
              max(Name_Date))                        as Span_Days    label = "Span (days)"
    from ARCH_TABLES_PARSED
    group by Library, Campaign_Label
    order by Library, Campaign_Label;
quit;


/* ============================================================
   STEP 4: FULL TABLE LISTING (sorted oldest to newest)
   ============================================================ */

proc sort data=ARCH_TABLES_PARSED out=ARCH_TABLE_LIST;
    by Library Campaign_Label Name_Date Name_Time;
run;


/* ============================================================
   STEP 5: PRINT REPORTS
   ============================================================ */

title1 "Archive Date Range Audit — How Far Back Do Tables Go?";

title2 "Overall Range by Library";
proc print data=ARCH_RANGE_BY_LIB noobs label;
    var Library Table_Count
        Earliest_By_Name Latest_By_Name
        Earliest_By_CrDate Latest_By_CrDate
        Span_Months Span_Days;
run;

title2 "Range by Campaign and Library";
proc print data=ARCH_RANGE_BY_CAMP noobs label;
    var Library Campaign_Label Table_Count Earliest Latest Span_Days;
run;

title2 "Full Archive Table Listing (Oldest to Newest)";
proc print data=ARCH_TABLE_LIST noobs label;
    var Library Campaign_Label Table_Name
        Name_Date Name_Time
        SAS_Create_Date;
run;

title;

%put ======================================================;
%put ARCHIVE AUDIT COMPLETE;
%put Check: ARCH_RANGE_BY_LIB   - overall date spans;
%put Check: ARCH_RANGE_BY_CAMP  - per-campaign spans;
%put Check: ARCH_TABLE_LIST     - every table oldest to newest;
%put ======================================================;
