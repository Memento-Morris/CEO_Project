/* APN POT pipeline — Section 6: %build_campaign_filter.
   This macro is the table-discovery engine of the job. For a given library
   it queries dictionary.tables and dynamically assembles an OR filter, one
   "memname like '<campaign>%'" term per active campaign code, so only the
   tables belonging to live campaigns are picked up. The macro body is the
   author's original; the only change is that the library being scanned is
   WORK (seeded in the autoexec) rather than the production PASS6 library. */

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

%build_campaign_filter(libref=WORK, outds=campaign_tables)

proc sql noprint;
    select count(*) into :found trimmed
    from campaign_tables;
quit;

%put Campaign tables discovered: &found;

title "Tables matched by %nrstr(%build_campaign_filter)";
proc sql;
    select libname, memname
    from campaign_tables
    order by memname;
quit;
title;
