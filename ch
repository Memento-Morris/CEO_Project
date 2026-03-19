/* ============================================================================
   STI CA Servicing Advisor Remuneration Calculation
   
   Purpose : Calculates monthly incentive pay for Servicing Advisors across
             LOC and COMP teams, incorporating QA scores, performance bonuses,
             and sales bonuses.

   Parts:
     1. Weekly scorecard scores over the OBR period
     2. Monthly earn before and after QA adjustment
     3. Performance and sales bonuses
     4. Final earn with manual adjustments and export
   ============================================================================ */

%include "/data/fnbins/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Automation/STI_CA_2/Libnames.sas";


/* ============================================================================
   PART 1: AGENT SCORES OVER THE OBR PERIOD
   ============================================================================ */

/* ----------------------------------------------------------------------------
   Step 1.1 - Define OBR and Scorecard Date Ranges
   
   *** USER INPUT REQUIRED - update all date values below before each run ***
   
   OBR period:   Use the first Monday to last Sunday of the month.
                 For 2026, shift back by one week due to processing timelines.
   
   Scorecard dates (Step 1.4): Use the four Mondays within the OBR period.
   ---------------------------------------------------------------------------- */

/* *** USER INPUT: First day of the OBR cycle *** */
%let OBR_Month_start_date = ;

/* *** USER INPUT: Last day of the OBR cycle *** */
%let OBR_Month_end_date = ;

/* *** USER INPUT: Date of the first scorecard run in this OBR period *** */
%let current_obr_period_start_date = ;

/* *** USER INPUT: Date of the last scorecard run in this OBR period *** */
%let current_obr_period_end_date = ;


/* ----------------------------------------------------------------------------
   Step 1.2 - Load QA Period Calendar and Derive Sheet Name for This Period
   ---------------------------------------------------------------------------- */

data Periods;
    set sti_meta.qa_loc_periods;
    character_month = put(QA_Period, monyy7.);
run;

data _null_;
    set Periods;
    call symput('sheet', character_month);
    where QA_Period = "&OBR_Month_start_date"d;
run;

%put -------> &sheet;


/* ----------------------------------------------------------------------------
   Step 1.3 - Load Historical Scores and Filter to Active Agents
   
   Source: OBR PBI Input Sheet (Operations OBR data tab).
   *** USER INPUT: Verify the file path and sheet name are current before running ***
   ---------------------------------------------------------------------------- */

PROC IMPORT
    DATAFILE="\\lfe-rbgfs01\FNB_Insure\FSR STI Corporate Actuarial\Dashboards\Operational\OBR_Records\run\Input_Files\OBR PBI Input Sheet.xlsx"
    OUT=OBR_History
    DBMS=excelcs
    REPLACE;
    SHEET="Operations OBR data";
    SERVER='lfe-rbgfs01';
    PORT=9621;
RUN;

/* Retain only Servicing division records and convert OpsYM (YYYYMM) to end-of-month date */
DATA Historical_Scores;
    SET OBR_History;
    IF Division = 'Servicing';
    KEEP Fnumber UserName Team Score OpsYM DateVar;
    Year  = INT(OpsYM / 100);
    Month = MOD(OpsYM, 100);
    DateVar = INTNX('month', MDY(Month, 1, Year), 0, 'E');
    FORMAT DateVar DATE9.;
RUN;

/* Keep only agents that appear in the current active employee list */
proc sql;
    create table Leave_Score as
    select a.*, b.EmployeeNumber as EmployeeNumber2
    from Historical_Scores a
    inner join STI_PBI.STI_Servicing_Agents b
    on a.Fnumber = b.EmployeeNumber;
quit;


/* ----------------------------------------------------------------------------
   Step 1.4 - Calculate Each Agent's 3-Month Average Score
   
   The window covers the 3 full calendar months immediately before the OBR
   start month (BOM minus 3 months through EOM of the prior month).
   This average is used as a substitute score when an agent was on leave.
   ---------------------------------------------------------------------------- */

proc sql;
    create table Leave_Score_2 as
    select UserName,
           EmployeeNumber2 as employeenumber,
           round(mean(Score), 0.01) as three_month_score
    from Leave_Score
    where DateVar between intnx('month', "&OBR_Month_start_date"d, -3, 'b')
                      and intnx('month', "&OBR_Month_start_date"d, -1, 'e')
    group by UserName, EmployeeNumber2;
quit;

/* Restrict to currently active agents only */
proc sql;
    create table Leave_Score_2 as
    select a.*
    from Leave_Score_2 a
    where a.EmployeeNumber in (select EmployeeNumber
                               from STI_PBI.STI_Servicing_Agents
                               where Active = 1);
quit;


/* ----------------------------------------------------------------------------
   Step 1.5 - Load Leave Records
   
   The 3-month average score substitution only applies when an agent had
   5 or more leave days in the affected scorecard week.
   
   *** USER INPUT: Confirm the leave template file and path are current ***
   ---------------------------------------------------------------------------- */

PROC Import
    DATAFILE="\\lfe-rbgfs01\FNB_Insure\FSR STI Corporate Actuarial\Dashboards\Operational\OBR_Records\Leave_Template.xlsx"
    OUT=Leave_Template
    DBMS=excelcs
    REPLACE;
    server='lfe-rbgfs01';
    PORT=9621;
    sheet="&sheet";   /* Double quotes required — single quotes prevent macro resolution */
RUN;

data Leave_Template;
    set Leave_Template;
    rename 'Scorecard_Affected_Date(Which Mo'n = Score_Affected_Date;
run;

/* Only populate the affected scorecard date when leave days reach the 5-day threshold */
data Leave_Template2;
    set Leave_Template;
    IF 'Leave Days'n >= 5 THEN Scorecard_Day_affected2 = Score_Affected_Date;
    format Scorecard_Day_affected2 date9.;
run;


/* ----------------------------------------------------------------------------
   Step 1.6 - Pull Weekly Scorecard Scores for the OBR Period
   
   Scorecards capture the preceding 7 days, so we include all Monday run dates
   from current_obr_period_start_date through current_obr_period_end_date.
   Only the latest SQL export for each agent and run date is retained.
   ---------------------------------------------------------------------------- */

proc sql;
    create table Servicing_Scores as
    select *
    from STI_SC.Servicing_Scores b
    where sql_export_day = (select max(sql_export_day)
                            from STI_SC.Servicing_Scores c
                            where b.run_date = c.run_date
                              and b.EmployeeNumber = c.EmployeeNumber)
      and run_date >= "&current_obr_period_start_date"d
      and run_date <= "&current_obr_period_end_date"d
      and weekday(run_date) = 2    /* Mondays only */
      and active = 1
    order by EmployeeNumber;
quit;

/* Restrict to active agents */
proc sql;
    create table Servicing_Scores as
    select a.*
    from Servicing_Scores a
    where a.EmployeeNumber in (select EmployeeNumber
                               from STI_PBI.STI_Servicing_Agents
                               where Active = 1);
quit;

/* Rebuild full_name from the employee master to avoid any name inconsistencies */
data Servicing_Scores;
    set Servicing_Scores;
    drop full_name;
run;

proc sql;
    create table Servicing_Scores as
    select catx(' ', b.Name, b.Surname) as full_name,
           a.*
    from Servicing_Scores a
    left join STI_PBI.STI_Servicing_Agents b
    on a.EmployeeNumber = b.EmployeeNumber;
quit;

/* Verification check: confirm expected run dates are present */
proc sql;
    select distinct run_date
    from Servicing_Scores;
quit;


/* ----------------------------------------------------------------------------
   Step 1.7 - Apply Leave Adjustment: Substitute 3-Month Score Where Applicable
   ---------------------------------------------------------------------------- */

proc sql;
    create table Servicing_Scores_WLeave as
    select a.*,
           b.three_month_score,
           c.Scorecard_Day_affected2
    from Servicing_Scores a
    left join Leave_Score_2 b
        on a.EmployeeNumber = b.employeenumber
    left join Leave_Template2 c
        on (a.EmployeeNumber = c.F_Number and a.run_date = c.Scorecard_Day_affected2);
quit;

/* Manual correction: override team assignment for a specific agent */
Data Servicing_Scores_WLeave;
    Set Servicing_Scores_WLeave;
    IF EmployeeNumber = 'F5485428' THEN line = 'Comp 1';
run;


/* ----------------------------------------------------------------------------
   Step 1.8 - Split into LOC and COMP Servicing Tables
   
   Where an agent was on qualifying leave and their actual scorecard is below
   their 3-month average, the average is used instead.
   ---------------------------------------------------------------------------- */

data LOC_Servicing_Remm COMP_Servicing_Remm;
    set Servicing_Scores_WLeave (
        keep = Full_Name line EmployeeNumber run_date Active scorecard
               three_month_score Scorecard_Day_affected2
        rename = (EmployeeNumber = Employee_Number)
    );

    if Scorecard_Day_affected2 ne '' and scorecard < three_month_score then
        scorecard = three_month_score;

    if line in ("LOC 1", "LOC 2") then output LOC_Servicing_Remm;
    else output COMP_Servicing_Remm;
run;


/* ============================================================================
   PART 2: EARN CALCULATION (PRE- AND POST-QA)
   ============================================================================ */

/* ----------------------------------------------------------------------------
   Step 2.1 - Import Earn Metrics Tables
   
   *** USER INPUT: Verify the metrics file path reflects the current period ***
   ---------------------------------------------------------------------------- */

%macro importing(output, sheet);
    proc import
        datafile="/data/fnbinsurance/Corporate_Actuarial/Short_Term/LOC/All_teams_metrics.xlsx"
        dbms=xlsx replace
        out=&output;
        sheet=&sheet;
    quit;
%mend;

%importing(LOC_Earn_Metrics,  LOC_Servicing_Earn);
%importing(COMP_Earn_Metrics, COMP_Servicing_Earn);
%importing(QA_factors,        QA_Factor);


/* ----------------------------------------------------------------------------
   Step 2.2 - Calculate Weekly Earn Before QA Adjustment
   
   Joins each weekly scorecard score to the earn metrics lookup using the
   run date and scorecard score bands.
   ---------------------------------------------------------------------------- */

%macro Remuneration(Office_Remuneration, Office_Monday_Score, Office_Earn_Metrics,
                    Office_Scorecard_Total, LB_score, UP_Score);
    proc sql;
        create table &Office_Remuneration as
        select a.*,
               b.Earn as Earn_before_QA
        from   &Office_Monday_Score a
        left join &Office_Earn_Metrics b
            on  (a.run_date between b.start_date and end_date)
            and (a.&Office_Scorecard_Total between b.&LB_score and b.&UP_Score)
        order by a.Employee_Number;
    quit;
%mend;

%Remuneration(LOC_Servicing_Earn,  LOC_Servicing_Remm,  LOC_Earn_Metrics,
              ScoreCard, LB_LOC_Servicing_Score, UP_LOC_Servicing_Score);
%Remuneration(COMP_Servicing_Earn, COMP_Servicing_Remm, COMP_Earn_Metrics,
              ScoreCard, LB_COMP_Servicing_Score, UP_COMP_Servicing_Score);

/* Remove any duplicate weekly earn rows */
%macro SORTING_REMUNERATION(TABLE1, TABLE2);
    proc sort data=&TABLE1 out=&TABLE2 noduprecs;
        by _all_;
    run;
%mend;

%SORTING_REMUNERATION(LOC_Servicing_Earn,  LOC_Servicing_Earn);
%SORTING_REMUNERATION(COMP_Servicing_Earn, COMP_Servicing_Earn);


/* ----------------------------------------------------------------------------
   Step 2.3 - Aggregate to Monthly Earn Before QA
   
   Weekly earns are summed within each QA calendar period.
   The run_date window is offset by 7 days at the start to align with how
   scorecards capture the prior week's activity.
   ---------------------------------------------------------------------------- */

%macro ALL_OFFICE_MONTHLY_EARN(Office_Name, From_Office_Remm);
    proc sql;
        create table &Office_Name as
        select a.Full_Name,
               a.line,
               a.Employee_Number,
               round(avg(ScoreCard), 0.01) as Monthly_Score,
               sum(a.Earn_before_QA)       as Monthly_Earn_before_QA,
               a.active,
               b.QA_Period
        from   &From_Office_Remm a
        inner join Periods b
            on (a.run_date between b.Start_Date + 7 and b.End_date + 1)
        group by a.Full_Name, a.Employee_Number, a.line, a.active, b.QA_Period;
    quit;
%mend;

%ALL_OFFICE_MONTHLY_EARN(LOC_SER_Monthly_Earn_PreQA,  LOC_Servicing_Earn);
%ALL_OFFICE_MONTHLY_EARN(COMP_SER_Monthly_Earn_PreQA, COMP_Servicing_Earn);


/* ----------------------------------------------------------------------------
   Step 2.4 - Calculate QA Scores for the Scorecard Period
   ---------------------------------------------------------------------------- */

/* Load raw QA data and set evaluation count to 0 where score is missing */
%macro QA(Tablename, from);
    data &Tablename;
        set &from;
        Evaluations2 = Evaluations;
        by descending Date_stamp;
        if score = . then evaluations = 0;
    run;
%mend;

%QA(Service_QA_Raw, sti_pbi.Service_QA_Final)

proc sort data=Service_QA_Raw;
    by employee_number;
run;

/* Aggregate QA scores to period level */
proc sql;
    create table QA_Score as
    select a.Employee_number,
           b.QA_Period,
           b.Start_Date,
           b.End_date,
           SUM(Score_M)                           as QA_Score,
           sum(Evaluations2)                       as QA_Evaluations,
           round(SUM(Score_M) / sum(Evaluations), 0.01) as QA_Score_Perc
    from   Service_QA_Raw a
    inner join Periods b
        on (a.date_stamp between b.Start_Date and b.End_date)
    group by a.Employee_number, b.QA_Period, b.Start_Date, b.End_date;
quit;

/* Join QA incentive multiplication factors */
proc sql;
    create table QA_FINAL as
    select *
    from   QA_Score a
    left join QA_factors b
        on  (a.QA_Score_Perc between b.LB_QA and b.UP_QA)
        and (a.End_date between b.Start_date and b.End_date)
    order by a.End_date desc;
quit;

/* Agents with no QA evaluations default to 100% (factor = 1) */
data QA_FINAL;
    set QA_FINAL;
    if QA_Score_Perc = . then QA_Score_Perc = 100 and Incentive_Factor_To_Be_Paid = 1;
run;


/* ----------------------------------------------------------------------------
   Step 2.5 - Calculate Monthly Earn After QA Adjustment
   ---------------------------------------------------------------------------- */

%macro Final_Earn(Earn_Table, from_earn, QA);
    proc sql;
        create table &Earn_Table as
        select a.*,
               b.start_date,
               b.end_date,
               b.QA_Evaluations,
               b.QA_Score_Perc,
               b.Incentive_Factor_To_Be_Paid,
               a.Monthly_Earn_before_QA * b.Incentive_Factor_To_Be_Paid as Monthly_Earn_after_QA
        from   &from_earn a
        left join &QA b
            on (a.Employee_Number = b.Employee_Number and a.QA_Period = b.QA_Period)
        order by a.QA_Period desc;
    quit;
%mend;

%Final_Earn(COMP_Final_Monthly_Earn, COMP_SER_Monthly_Earn_PreQA, QA_FINAL);
%Final_Earn(LOC_Final_Monthly_Earn,  LOC_SER_Monthly_Earn_PreQA,  QA_FINAL);

data Sum_Earns_With_QA;
    set COMP_Final_Monthly_Earn LOC_Final_Monthly_Earn;
run;


/* ============================================================================
   PART 3: BONUSES
   ============================================================================ */

/* ----------------------------------------------------------------------------
   Step 3.1 - Performance Bonus
   
   Criteria: An agent scores >= 4.3 in at least 3 consecutive weeks within
             a single month. Qualifying agents receive R1 000 per eligible week.
   ---------------------------------------------------------------------------- */

/* Build working copy and attach period context */
proc sql;
    create table Servicing_Score_Months_Pre as
    select * from Servicing_Scores_WLeave;
quit;

proc sql;
    create table Servicing_Score_Months as
    select a.Full_name,
           a.line,
           a.EmployeeNumber,
           a.run_date,
           a.scorecard,
           b.QA_Period,
           b.Weeks_in_Month,
           b.start_date
    from   Servicing_Score_Months_Pre a
    left join Periods b
        on (a.run_date between b.Start_Date and b.End_date)
    order by a.run_date, a.employeeNumber;
quit;

proc sort data=Servicing_Score_Months;
    by _all_;
run;

/* Capture the earliest run date in the period to use as the QA period anchor */
proc sql;
    select min(run_date) format date9.
    into :min_date
    from Servicing_Score_Months;
quit;

/* Flag each week where score >= 4.3 and calculate its position within the cycle */
data Servicing_Performance_Incentive (drop=Weeks_in_Month start_date);
    set Servicing_Score_Months;
    QA_Period = "&min_date"d;
    if Scorecard >= 4.3 then count = 1;
    else count = 0;
    Monday_of_the_period = abs(intck('day', "&min_date"d, run_date) / 7) + 1;
run;

/* Deduplicate at agent-period level */
proc sort data=Servicing_Performance_Incentive noduprecs;
    by EmployeeNumber QA_Period;
run;

/* Accumulate a running count of qualifying weeks per agent per period */
data Servicing_Performance_count;
    set Servicing_Performance_Incentive;
    by EmployeeNumber QA_Period;
    retain sum_of_count;
    if first.QA_Period then sum_of_count = count;
    else sum_of_count + count;
run;

/* Assign R1 000 incentive for each eligible week within a qualifying consecutive run */
data Servicing_Incentive_Earn;
    set Servicing_Performance_count;
    if (Monday_of_the_period in (1,2,3) and Scorecard >= 4.3) or
       (Monday_of_the_period in (2,3,4) and Scorecard >= 4.3) or
       (Monday_of_the_period in (3,4,5) and Scorecard >= 4.3)
    then Perfomance_Incentive = 1000;
    else Perfomance_Incentive = 0;
run;

/* Retain only agents who achieved 3 or more qualifying weeks */
data Servicing_Incentive_Earn;
    set Servicing_Incentive_Earn;
    where sum_of_count in (3,4,5)
      and Scorecard >= 4.3
      and QA_Period >= "&min_date"d;
run;

proc sql;
    create table Performance_bonus as
    select Full_name, EmployeeNumber, line, QA_Period, Perfomance_Incentive
    from Servicing_Incentive_Earn;
quit;

proc sort data=Performance_bonus noduprecs;
    by _all_;
run;


/* ----------------------------------------------------------------------------
   Step 3.2 - Sales Bonus
   
   *** USER INPUT: Update the Servicing_Sales.xlsx file with current sales data ***
   ---------------------------------------------------------------------------- */

PROC Import
    DATAFILE="\\lfe-rbgfs01\FNB_Insure\FSR STI Corporate Actuarial\Dashboards\Operational\OBR_Records\Servicing_Sales.xlsx"
    OUT=Sales_Incentive
    DBMS=excelcs
    REPLACE;
    server='lfe-rbgfs01';
    PORT=9621;
    sheet="&sheet";   /* Double quotes required — single quotes prevent macro resolution */
RUN;

/* Match sales records to agents by first name */
proc sql;
    create table sales_incentives_serv as
    select a.*, b.EmployeeNumber
    from Sales_Incentive a
    left join sti_pbi.service_employee b
        on upcase(scan(a.name, 1)) = upcase(b.Name);
quit;


/* ============================================================================
   PART 4: FINAL EARN AND ADJUSTMENTS
   ============================================================================ */

/* ----------------------------------------------------------------------------
   Step 4.1 - Combine LOC and COMP; Default Missing Post-QA Earn to Pre-QA
   ---------------------------------------------------------------------------- */

DATA SERVICING_PREFINAL;
    SET COMP_Final_Monthly_Earn LOC_Final_Monthly_Earn;
    if Monthly_Earn_after_QA = . then Monthly_Earn_after_QA = Monthly_Earn_before_QA;
RUN;


/* ----------------------------------------------------------------------------
   Step 4.2 - Join Performance and Sales Bonuses; Calculate Total Incentive
   ---------------------------------------------------------------------------- */

PROC SQL;
    CREATE TABLE SERVICING_MONTHLY_INCENTIVE AS
    SELECT a.*,
           b.Perfomance_Incentive,
           c.Amount   as Sales_Incentive,
           SUM(a.Monthly_Earn_after_QA, b.Perfomance_Incentive, c.Amount) AS Total_incentive
    FROM   SERVICING_PREFINAL a
    LEFT JOIN Performance_bonus      b ON (a.Employee_Number = b.EmployeeNumber and a.line = b.line)
    LEFT JOIN sales_incentives_serv  c ON  a.Employee_Number = c.EmployeeNumber;
quit;

proc sort data=SERVICING_MONTHLY_INCENTIVE noduprecs;
    by Full_Name QA_Period;
run;


/* ----------------------------------------------------------------------------
   Step 4.3 - Manual Adjustments: Secure Chat Agents
   
   Agents on the Secure Chat platform receive a flat earn of R3 000.
   *** USER INPUT: Cross-check this list against Secure_Chat_Agents (Active = 1,
       Platform_Chat = 1 in STI_PBI.STI_Servicing_Agents) before each run ***
   ---------------------------------------------------------------------------- */

data SERVICING_MONTHLY_INCENTIVE;
    set SERVICING_MONTHLY_INCENTIVE;

    if Employee_Number = 'F5324823' then Monthly_Earn_after_QA = 3000; /* Nqobile Magani     */
    if Employee_Number = 'F5330246' then Monthly_Earn_after_QA = 3000; /* Lesego Motala       */
    if Employee_Number = 'F5530563' then Monthly_Earn_after_QA = 3000; /* Chase Moses         */
    if Employee_Number = 'F4903773' then Monthly_Earn_after_QA = 3000; /* Tarryn Fredricks    */
    if Employee_Number = 'F8872893' then Monthly_Earn_after_QA = 3000; /* Sevushen Thaver     */
    if Employee_Number = 'F3446921' then Monthly_Earn_after_QA = 3000; /* Stacey Thomas       */
    if Employee_Number = 'F5663393' then Monthly_Earn_after_QA = 3000; /* Thenjiwe Mnikathi   */

    /* Default nulls to neutral values before totalling */
    if Perfomance_Incentive = . then Perfomance_Incentive = 0;
    if QA_Score_Perc        = . then QA_Score_Perc        = 100;
    if Sales_Incentive      = . then Sales_Incentive      = 0;

    Total_incentive = Monthly_Earn_after_QA + Perfomance_Incentive + Sales_Incentive;
run;


/* ----------------------------------------------------------------------------
   Step 4.4 - Split Final Earn into LOC and COMP
   ---------------------------------------------------------------------------- */

data LOC_Monthly_Earn COMP_Monthly_Earn;
    set SERVICING_MONTHLY_INCENTIVE;
    if line in ('LOC 2', 'LOC 1') then output LOC_Monthly_Earn;
    else output COMP_Monthly_Earn;
run;


/* ----------------------------------------------------------------------------
   Step 4.5 - Export Results to CSV
   
   *** USER INPUT: Update the output file name to reflect the current OBR month
       and run number, e.g. Serv_Output_MAR2026_run1.csv ***
   ---------------------------------------------------------------------------- */

ods excel file='/data/fnbinsurance/Corporate_Actuarial/Short_Term/Servicing/Serv_Output_MMMYYYY_runN.csv'
    options(sheet_name='COMP Final_Earns');
    proc print data=COMP_Monthly_Earn noobs; run;
ods excel options(sheet_name='LOC FinalEarns');
    proc print data=LOC_Monthly_Earn noobs; run;
ods excel options(sheet_name='COMP_WeeklyEarns_before_QA');
    proc print data=COMP_Servicing_Earn noobs; run;
ods excel options(sheet_name='LOC_WeeklyEarns_before_QA');
    proc print data=LOC_Servicing_Earn noobs; run;
ods excel options(sheet_name='Performance_Incentive');
    proc print data=Performance_bonus noobs; run;
ods excel options(sheet_name='Sales_Incentive');
    proc print data=sales_incentives_serv noobs; run;
ods excel close;


/* ----------------------------------------------------------------------------
   Step 4.6 - Reference: Active Agent List (used for cross-checks above)
   ---------------------------------------------------------------------------- */

Data Secure_Chat_Agents;
    Set STI_PBI.STI_Servicing_Agents;
    IF Active = 1;
Run;
