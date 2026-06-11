/* APN POT pipeline — Section 1-2: read campaign config, filter to active
   rows, and build the dynamic macro variables that drive the rest of the
   job. Original reads the "Config" sheet of APN_Campaign_Config.xlsx via
   PROC IMPORT over a network share; here the same columns are supplied
   inline so the filtering + select-into logic runs standalone. */

%put TAG:JobName1=STI_CA_D_APNS_DATA_REBUILD;
%put TAG:JobName2=Daily;
%put TAG:JobCategory=Campaigns;

/* --- stand-in for the imported Config sheet --------------------------- */
data Campaign_Config_Raw;
    length Active $1 Campaign_Code $20 Product_Code $20
           Input_File_Path $500 Input_File_Name $200
           Input_File_Sheet $100 Input_File_Type $10;
    infile datalines dsd truncover;
    input Active $ Campaign_Code $ Product_Code $
          Input_File_Path $ Input_File_Name $
          Input_File_Sheet $ Input_File_Type $;
    datalines;
Y,apn_funeral,fnr001,/share/in/,funeral.xlsx,Sheet1,XLSX
Y,apn_funeral,fnr002,/share/in/,funeral.xlsx,Sheet1,XLSX
Y,apn_life,lif010,/share/in/,life.xlsx,Sheet1,XLSX
N,apn_legacy,leg999,/share/in/,legacy.xlsx,Sheet1,XLSX
Y,,blank001,/share/in/,blank.xlsx,Sheet1,XLSX
Y,apn_motor,mot050,/share/in/,motor.xlsx,Sheet1,XLSX
;
run;

proc sql noprint;
    select count(*) into :config_raw_count trimmed
    from Campaign_Config_Raw;
quit;

%put NOTE: Campaign_Config_Raw imported with &config_raw_count rows. Proceeding.;

/* Filter to active rows + tidy the input-file columns (Fix 6 / Fix 7) */
data Campaign_Config;
    set Campaign_Config_Raw;
    where upcase(strip(Active)) = "Y"
      and strip(Campaign_Code)  ne ""
      and strip(Product_Code)   ne "";
    Campaign_Code = upcase(strip(Campaign_Code));
    Product_Code  = upcase(strip(Product_Code));

    length Full_Input_Path $500;
    Input_File_Path  = strip(Input_File_Path);
    Input_File_Name  = strip(Input_File_Name);
    Input_File_Sheet = strip(Input_File_Sheet);
    Input_File_Type  = upcase(strip(Input_File_Type));
    Full_Input_Path  = cats(Input_File_Path, Input_File_Name);

    row_num = _n_;
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

/* SECTION 2: BUILD DYNAMIC MACRO VARIABLES FROM CONFIG */
proc sql noprint;
    select count(distinct Campaign_Code)
    into   :camp_count trimmed
    from   Campaign_Config;

    select distinct Campaign_Code
    into   :camp_1 - :camp_99
    from   Campaign_Config
    order  by Campaign_Code;

    select distinct cats("'", Product_Code, "'")
    into   :product_list separated by ","
    from   Campaign_Config;
quit;

%put NOTE: &camp_count distinct campaign codes found.;
%put NOTE: Product list: &product_list;
