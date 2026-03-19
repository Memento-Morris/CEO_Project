/* Code for calculating Remuneration for Servicing Advisors */

%include "/data/fnbins/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Automation/STI_CA_2/Libnames.sas";

/* ---------------------------------------------------------------------------
   Part 1: Calculating the scores of the agents over the OBR period
--------------------------------------------------------------------------- */

/* ---------------------------------------------------------------------------
   Deciding time frames
--------------------------------------------------------------------------- */

/* QA Date Range */
data Periods;
    set sti_meta.qa_loc_periods;
    character_month = put(QA_Period, monyy7.);
run;

/* IMPORTANT: VERIFY MONTH FOR OBR
   Adjust offset in intnx():
   - 0 = current month
   - -1 = previous month
*/
/*%let OBR_Month_start_date = %SYSFUNC(intnx(month, %SYSFUNC(today()), 0, b), date9.);*/

/*%put *******************************************************;*/
/*%put *** CHECK: OBR_Month_start_date = &OBR_Month_start_date ***;*/
/*%put *******************************************************;*/

/* Periods as defined (before shifts) */
data _null_;
    set Periods;
    call symput('sheet', character_month);
    where QA_Period = "&OBR_Month_start_date"d;
run;

%put -------> &sheet;

/* Hardcode option here - first day of OBR cycle*/
%let OBR_Month_start_date = '24FEB2026' ;
%let OBR_Month_end_date = '30MAR2026' ; 
/*
Decide the OBR period: Use first Monday to last Sunday of the month, (For 2026, we have shifted back by one week due to timelines).  

For Feb 2026: 27 Jan – 23 Feb 2026 

Decide the Mondays (scorecards):  

For Feb2026, you'll use 02, 09, 16, 23 Feb 2026 

You’ll hardcode these four dates in the script in Step 5. 
/****** NB: STORING DATES OF FIRST AND LAST SCORECARD TAKEN ******/

/* First Scorecard*/
%let current_obr_period_start_date = '02MAR2026';
%put &current_obr_period_start_date;

/* Last Scorecard*/
%let current_obr_period_end_date = '30MAR2026';
%put &current_obr_period_end_date;


/* ---------------------------------------------------------------------------
   Calculating 3 month scores
--------------------------------------------------------------------------- */

/* Getting historical scores
   NOTE: Update file from previous OBR (Copy and Paste most recent file)
*/

PROC IMPORT 
    DATAFILE="\\lfe-rbgfs01\FNB_Insure\FSR STI Corporate Actuarial\Dashboards\Operational\OBR_Records\run\Input_Files\OBR PBI Input Sheet.xlsx"    
    OUT=OBR_History
    DBMS=excelcs 
    REPLACE;
    SHEET="Operations OBR data";
    SERVER='lfe-rbgfs01';
    PORT=9621; 
RUN;

DATA Historical_Scores;
    SET OBR_History;

    IF Division = 'Servicing';
    KEEP Fnumber UserName Team Score OpsYM DateVar;

    /* Convert OpsYM (YYYYMM) to EOM date */
    Year = INT(OpsYM / 100);          /* Extract year */
    Month = MOD(OpsYM, 100);          /* Extract month */
    DateVar = INTNX('month', MDY(Month, 1, Year), 0, 'E'); /* End of month */
    FORMAT DateVar DATE9.;            /* Format as DDMMMYYYY */
RUN;

proc sql;
    create table Leave_Score as
    select a.*, b.EmployeeNumber as EmployeeNumber2
    from Historical_Scores a
/*    inner join sti_pbi.service_employee b*/
	inner join STI_PBI.STI_Servicing_Agents b /*migrating over to new employee list */
    on a.Fnumber = b.EmployeeNumber;
quit;

/* --- These are our current agents 3 month scores --- */
proc sql; 
    create table Leave_Score_2 as
    select UserName,
           EmployeeNumber2 as employeenumber,
           round(mean(Score), 0.01) as three_month_score
    from Leave_Score

/* Calculate scores for the 3 full months before the current month: start = BOM 3 months ago, end = EOM of prior month */

/*    where DateVar between intnx('month', "&OBR_Month_start_date"d, -3, 's')*/
/*                      and "&OBR_Month_start_date"d*/
	where DateVar between intnx('month', "&OBR_Month_start_date"d, -3, 'b')
                  and intnx('month', "&OBR_Month_start_date"d, -1, 'e') 

    group by UserName, EmployeeNumber2;

proc sql;
	create table Leave_Score_2 
    as select a.*
	from Leave_Score_2 a 
	where a.EmployeeNumber in (select EmployeeNumber 
                               from STI_PBI.STI_Servicing_Agents
							   where Active = 1);
quit;


/* ---------------------------------------------------------------------------
   Getting leave records
   NOTE: 3 month score will only taken if leave days >= 5 
--------------------------------------------------------------------------- */

/*NOTE: Copy and Paste most recent file in location*/

PROC Import 
    DATAFILE="\\lfe-rbgfs01\FNB_Insure\FSR STI Corporate Actuarial\Dashboards\Operational\OBR_Records\Leave_Template.xlsx"
    OUT=Leave_Template
    DBMS=excelcs 
    REPLACE;
    server= 'lfe-rbgfs01';
    PORT=9621;    
	sheet='&sheet';
RUN;

data Leave_Template;
set Leave_Template;
rename 'Scorecard_Affected_Date(Which Mo'n = Score_Affected_Date;
run;

data Leave_Template2;
set Leave_Template;
/*Scorecard_Day_affected2= input(Score_Affected_Date, mmddyy10.);*/
IF 'Leave Days'n >= 5 THEN Scorecard_Day_affected2= Score_Affected_Date;
format Scorecard_Day_affected2 date9.;   /*This variable defines if 3 month average is used */
run;


/* ---------------------------------------------------------------------------
   Pulling in weekly scores from scorecards 
--------------------------------------------------------------------------- */

/* Note that because the scorecards capture the previosu 7 days, we take everything after the start date up until and including the end date */
proc sql;
create table Servicing_Scores as
select *
from STI_SC.Servicing_Scores b
where sql_export_day = (select max(sql_export_day) 
							from STI_SC.Servicing_Scores c
							 where b.run_date = c.run_date and b.EmployeeNumber = c.EmployeeNumber)
and run_date >= "&current_obr_period_start_date"d and run_date <= "&current_obr_period_end_date"d
and weekday(run_date) = 2
and active =1
order by EmployeeNumber
;quit;

proc sql;
	create table Servicing_Scores 
    as select a.*
	from Servicing_Scores a 
	where a.EmployeeNumber in (select EmployeeNumber 
                               from STI_PBI.STI_Servicing_Agents
							   where Active = 1);
quit;

/* extra precaution to make sure there no duplicate names */

data Servicing_Scores;
Set Servicing_Scores;
drop full_name;

run;

proc sql; 
	create table Servicing_Scores as 
	select catx(' ', b.Name, b.Surname) as full_name
		  ,a.*
	from Servicing_Scores a
	left join STI_PBI.STI_Servicing_Agents b
	on a.EmployeeNumber = b.EmployeeNumber;
quit;


/**** Check: OBR Dates ****/
proc sql;
	select distinct
		run_date 
		from Servicing_Scores;
quit;


/* ---------------------------------------------------------------------------
   Adjusting for 3 month scores for leave <= 5 days 
--------------------------------------------------------------------------- */ 

proc sql;
create table Servicing_Scores_WLeave as
select     a.*,  
           b.three_month_score,
		   c.Scorecard_Day_affected2
from Servicing_Scores a
left join Leave_Score_2 b
on a.EmployeeNumber = b.employeenumber
left join Leave_Template2 c
on (a.EmployeeNumber = c.F_Number and a.run_date = c.Scorecard_Day_affected2)
;quit;

/*** Adjusting for name discrepency found ***/

Data Servicing_Scores_WLeave;
Set Servicing_Scores_WLeave;

IF EmployeeNumber = 'F5485428' THEN line = 'Comp 1';

run;


/* --- Splitting Servicing Teams --- */

data LOC_Servicing_Remm COMP_Servicing_Remm;
set Servicing_Scores_WLeave (keep=Full_Name line EmployeeNumber run_date Active scorecard three_month_score Scorecard_Day_affected2 rename=(EmployeeNumber=Employee_Number));

if Scorecard_Day_affected2 ne '' and scorecard < three_month_score then 
    scorecard = three_month_score;

if line in ("LOC 1", "LOC 2") then output LOC_Servicing_Remm;
else output COMP_Servicing_Remm;

run;



/*======================================================================
	Part 2: Calculating the Earn based off metrics and scores 
======================================================================*/

/* ---------------------------------------------------------------------------
   Importing team metrics used for score calculations
--------------------------------------------------------------------------- */

%macro importing(output,sheet);
proc import 
datafile="/data/fnbinsurance/Corporate_Actuarial/Short_Term/LOC/All_teams_metrics.xlsx"
dbms=xlsx replace
out=&output;
sheet= &sheet;
quit;
%mend;
%importing(LOC_Earn_Metrics,LOC_Servicing_Earn);
%importing(COMP_Earn_Metrics,COMP_Servicing_Earn);
%importing(QA_factors,QA_Factor);

Data test;
set LOC_Servicing_Remm;
run;


/* ---------------------------------------------------------------------------
   Calculating Earn Before QA 
--------------------------------------------------------------------------- */
%macro Remuneration(Office_Remuneration,Office_Monday_Score,Office_Earn_Metrics,Office_Scorecard_Total,LB_score,UP_Score);
proc sql;
create table 		&Office_Remuneration as
select 				A.*, 
					b.Earn as Earn_before_QA 
from 				&Office_Monday_Score a
left join 			&Office_Earn_Metrics b 
on 					(a.run_date between b.start_date and end_date)
and 				(a.&Office_Scorecard_Total between b.&LB_score and b.&UP_Score)
order by 			a.Employee_Number
;
quit;
%MEND;
%Remuneration(LOC_Servicing_Earn,LOC_Servicing_Remm,LOC_Earn_Metrics,ScoreCard,LB_LOC_Servicing_Score,UP_LOC_Servicing_Score);
%Remuneration(COMP_Servicing_Earn,COMP_Servicing_Remm,COMP_Earn_Metrics,ScoreCard,LB_COMP_Servicing_Score,UP_COMP_Servicing_Score);

/* --- Earns per week (pre QA) --- */
%macro SORTING_REMUNERATION(TABLE1,TABLE2);
proc sort data=&TABLE1 out=&TABLE2 noduprecs;
by _all_;
run;
%mend;
%SORTING_REMUNERATION(LOC_Servicing_Earn,LOC_Servicing_Earn);
%SORTING_REMUNERATION(COMP_Servicing_Earn,COMP_Servicing_Earn);


/* --- Final Earn: Pre-QA --- */
%MACRO ALL_OFFICE_MONTHLY_EARN(Office_Name,From_Office_Remm,QA_Periods);
proc sql;
create table 		&Office_Name as
select 				a.Full_Name,
					a.line, 
					a.Employee_Number,
					round(avg(ScoreCard),0.01) as Monthly_Score,
					sum(a.Earn_before_QA) as Monthly_Earn_before_QA ,
					a.active ,
					b.QA_Period
from 				&From_Office_Remm A
inner join 			Periods B
on 				    (A.run_date between b.Start_Date+7 and b.End_date+1)
group by 			a.Full_Name, a.Employee_Number, a.line, a.active, b.QA_Period;
quit;
%MEND;
%ALL_OFFICE_MONTHLY_EARN(LOC_SER_Monthly_Earn_PreQA,LOC_Servicing_Earn);
%ALL_OFFICE_MONTHLY_EARN(COMP_SER_Monthly_Earn_PreQA,COMP_Servicing_Earn);


/* ---------------------------------------------------------------------------
   Manual Adjustments and corrections 

   Has since been removed as Active = 0 in Employee list once left 
--------------------------------------------------------------------------- */

/*data COMP_Servicing_Earn;*/
/*set  COMP_Servicing_Earn;*/
/**/
/*if Employee_Number in ( 'F5554020',  /*TL Ajay*/*/
/*                        'F5216893',  /*TL Jenise*/*/
/*/*						'F5493552',  /*Sivesh TL*/*/
/*						'F5493919',  /*Nomaswazi left - must change active to 0*/*/
/*						'F5584817',  /*Jod-Ash Left*/*/
/*						'F8877187'   /*'Nkosingiphile left*/*/
/*													) then delete; */
/*run;*/
;


/* ---------------------------------------------------------------------------
   Calculating QA scores 
--------------------------------------------------------------------------- */

/* QA scores from scorecard run*/
%macro QA(Tablename,from);
data &Tablename;
set &from;
Evaluations2 = Evaluations;
by descending Date_stamp ;
if score=. then evaluations = 0;
run;
%Mend;
%QA(Service_QA_Raw,sti_pbi.Service_QA_Final)

proc sort data=Service_QA_Raw;
by employee_number;
run;

/* Caluclating QA for scorecard period*/
proc sql;
create table 	QA_Score as
SELECT 			a.Employee_number,
				b.QA_Period,
				b.Start_Date,
				b.End_date,
	   			SUM(Score_M) as QA_Score,
	   			sum(Evaluations2) as QA_Evaluations,
       			round(SUM(Score_M)/sum(Evaluations),0.01) as QA_Score_Perc
from 			Service_QA_Raw A
inner join 		Periods B
on 				(A.date_stamp between b.Start_Date and b.End_date)
group by 	    a.Employee_number,  b.QA_Period, b.Start_Date, b.End_date;
quit;


/* joining QA score with the incentive multiplication factors*/
proc sql;
create table 	QA_FINAL as 
select *
from 			QA_Score a
left join 		QA_factors b on (a.QA_Score_Perc between b.LB_QA and b.UP_QA )
and 			(a.End_date between b.Start_date and b.End_date)
order by 		A.End_date desc;
;
quit;

/* fixing conditions for those who do not have a qa score percentage, assign 100*/ 
data QA_FINAL;
set QA_FINAL;
if QA_Score_Perc = . then QA_Score_Perc = 100 and Incentive_Factor_To_Be_Paid =1;
run;

/* ---------------------------------------------------------------------------
   Calculating Earn: After QA 
--------------------------------------------------------------------------- */


%Macro Final_Earn(Earn_Table,from_earn,QA);
proc sql;
create table 			&Earn_Table as 
select 					a.*,
						b.start_date,
						b.end_date,
						b.QA_Evaluations,
						b.QA_Score_Perc,
						b.Incentive_Factor_To_Be_Paid,
						a.Monthly_Earn_before_QA * b.Incentive_Factor_To_Be_Paid as Monthly_Earn_after_QA
from &from_earn a
left join &QA b 		on (a.Employee_Number = b.Employee_Number and
							a.QA_Period = b.QA_Period)
order by a.QA_Period desc
;
quit;
%Mend;
%Final_Earn(COMP_Final_Monthly_Earn,COMP_SER_Monthly_Earn_PreQA,QA_FINAL);
%Final_Earn(LOC_Final_Monthly_Earn,LOC_SER_Monthly_Earn_PreQA,QA_FINAL);

data Sum_Earns_With_QA;
set COMP_Final_Monthly_Earn LOC_Final_Monthly_Earn;
run;


/* ---------------------------------------------------------------------------
   Part 3: Incorporating Bonuses
--------------------------------------------------------------------------- */


/* ---------------------------------------------------------------------------
  Performance Bonus: An agents scores >= 4.3 in 3 consecutive weeks for a single month
--------------------------------------------------------------------------- */

/* Create a working copy of the input source table */
proc sql;
create table Servicing_Score_Months_Pre as
select *
from Servicing_Scores_WLeave
;quit;


/* Join scores to calendar periods to attach period context */
proc sql;
create table Servicing_Score_Months  as
select             a.Full_name , 
                a.line,
                a.EmployeeNumber,
                a.run_date,
                a.scorecard,
                b.QA_Period,
                b.Weeks_in_Month,
                b.start_date
from             Servicing_Score_Months_Pre a
left join         Periods b
on              (A.run_date between b.Start_Date and b.End_date)
order by         a.run_date , a.employeeNumber;
quit;

proc sort data=Servicing_Score_Months;
by _all_;
run;

/* Capture the earliest run_date for use as a reference QA period */
proc sql;
select min(run_date) format date9.
into :min_date 
from Servicing_Score_Months
;quit;

/* 5) Compute flags (=1) for each week that the score >= 4.3  */
data Servicing_Performance_Incentive(drop=Weeks_in_Month start_date);
set Servicing_Score_Months;
QA_Period = "&min_date"d;
if Scorecard >= 4.3 then count=1;
else count = 0;
Monday_of_the_period = abs(intck('day',"&min_date"d,run_date)/7)+1;
run;

/* Deduplicate at EmployeeNumber x QA_Period level */
proc sort data=Servicing_Performance_Incentive noduprecs;
by  EmployeeNumber QA_Period ; 
run;

/* Retain a running total of qualifying weeks (sum_of_count) per EmployeeNumber x QA_Period */
data Servicing_Performance_count;
set Servicing_Performance_Incentive;
by EmployeeNumber QA_Period ;
retain sum_of_count;
if ( first.QA_Period) then sum_of_count = count;
else sum_of_count + count;
/*where Employee_Number = "F5079667";*/
run;

/* Compute the incentive */
data Servicing_Incentive_Earn;
set Servicing_Performance_count;
        if (Monday_of_the_period in (1,2,3) and Scorecard >= 4.3 ) or 
        (Monday_of_the_period in (2,3,4) and Scorecard >= 4.3 ) or
        (Monday_of_the_period in (3,4,5) and Scorecard >= 4.3 )
        then Perfomance_Incentive = 1000;
        else Perfomance_Incentive = 0;

run;        


/*filting for 3 or more weeks, having score greater than 4.3*/
data Servicing_Incentive_Earn;
set Servicing_Incentive_Earn;
where sum_of_count in (3,4,5) and Scorecard>= 4.3 AND QA_Period >= "&min_date"D;
run;

/* Produce final bonus table with essential columns */
proc sql;
create table Performance_bonus as
select Full_name,EmployeeNumber,line, QA_Period, Perfomance_Incentive
from Servicing_Incentive_Earn;
/*group by Names,office,QA_Period,Perfomance_Incentive,Employee_Number;*/
quit;

/* Remove any remaining duplicate records */
proc sort data=Performance_bonus noduprecs;
by _all_;
run;


/* ---------------------------------------------------------------------------
  Calculating Sales Bonus 
--------------------------------------------------------------------------- */

/*NOTE: Update file with current sales numbers*/

/*servicing - importing sales incentive*/
PROC Import 
    DATAFILE="\\lfe-rbgfs01\FNB_Insure\FSR STI Corporate Actuarial\Dashboards\Operational\OBR_Records\Servicing_Sales.xlsx"
    OUT=Sales_Incentive
    DBMS=excelcs 
    REPLACE;
    server= 'lfe-rbgfs01';
    PORT=9621;
    sheet= '&sheet' ;
RUN;

data chec;
set Sales_Incentive;
run;

proc sql;
create table sales_incentives_serv as
select a.* , b.EmployeeNumber
from chec a
left join sti_pbi.service_employee b
on upcase(scan(a.name,1)) = upcase(b.Name)
;quit;



/* ---------------------------------------------------------------------------
   Part 4: Final Earn and Final Adjustments 
--------------------------------------------------------------------------- */

DATA SERVICING_PREFINAL;
SET COMP_Final_Monthly_Earn LOC_Final_Monthly_Earn;
if Monthly_Earn_after_QA = . then Monthly_Earn_after_QA=Monthly_Earn_before_QA;
else Monthly_Earn_after_QA =Monthly_Earn_after_QA;
RUN;


/* --- Joining incentives to post QA earn --- */
PROC SQL;
CREATE TABLE SERVICING_MONTHLY_INCENTIVE AS
SELECT 				A.* ,
					b.Perfomance_Incentive,
					C.Amount as Sales_Incentive, 
					SUM(A.Monthly_Earn_after_QA, b.Perfomance_Incentive, C.Amount) AS Total_incentive
from 				SERVICING_PREFINAL A
LEFT JOIN 			Performance_bonus b ON (A.Employee_Number = B.EmployeeNumber and A.line = B.line ) 
LEFT JOIN 			sales_incentives_serv C on (A.Employee_Number = C.EmployeeNumber )  ;
quit;

proc sort data=SERVICING_MONTHLY_INCENTIVE noduprecs;
by Full_Name  QA_Period;
run; 


/* Getting List of Agents on Secure Chat */
Data Secure_Chat_Agents;
Set  STI_PBI.STI_Servicing_Agents;
IF Platform_Chat = 1;
IF Active = 1;
Run;


/* Manual Adustments: Agents on Secure Chat. Check that all secure agents (above) are on the list (below)*/
data SERVICING_MONTHLY_INCENTIVE;
set SERVICING_MONTHLY_INCENTIVE;

if Employee_Number = 'F5324823' then do; /*Nqobile Magani*/
Monthly_Earn_after_QA = 3000;
end;

if Employee_Number = 'F5330246' then do; /*Lesego Motala*/
Monthly_Earn_after_QA = 3000; 
end;

if Employee_Number = 'F5530563' then do; /* Chase Moses  */
Monthly_Earn_after_QA = 3000; 
end;

if Employee_Number = 'F4903773' then do; /* Tarryn Fredricks  */
Monthly_Earn_after_QA = 3000; 
end;

if Employee_Number = 'F8872893' then do; /* Sevushen Thaver  */
Monthly_Earn_after_QA = 3000; 
end;

if Employee_Number = 'F3446921' then do; /* Stacey Thomas  */
Monthly_Earn_after_QA = 3000; 
end;

if Employee_Number = 'F5663393' then do; /* Thenjiwe Mnikathi    */
Monthly_Earn_after_QA = 3000; 
end;



/*if Employee_Number = 'F5530563' then do; /*Chase Moses*/*/
/*Monthly_Earn_after_QA = 4800;*/
/*end;*/

/*/*if full_name = 'Jod-AshNaicker' then do;*/*/
/*/*Monthly_Earn_after_QA = 2100;*/*/
/*/*end;*/*/
/**/
/*if full_name = 'NqobileMagani' then do;*/
/*Monthly_Earn_after_QA = 3000;*/
/*end;*/
/**/
/*if full_name = 'ChristopherMakhudu' then do;*/
/*Monthly_Earn_after_QA = 3000;*/
/*end;*/
/**/
/**/
/*/*if full_name = 'SiveshManikkam' then do;*/*/
/*/*Monthly_Earn_after_QA = 5500;*/*/
/*/*end;*/*/
/**/
/*if full_name = 'RenechiaJoseph' then do;*/
/*Monthly_Earn_after_QA = 4800;*/
/*end;*/
/**/
/*if full_name = 'TishkaGan' then do;*/
/*Monthly_Earn_after_QA = 5112.50;*/
/*end;*/
/**/
/*/*if full_name = 'SinikiweHlatswayo' then do;*/*/
/*/*Monthly_Earn_after_QA = 4197.14;*/*/
/*/*end;*/*/
/**/
/*/* needs to be added to sheet*/*/
/*if full_name = 'NonhlanhlaMasinga' then do;*/
/*Monthly_Earn_after_QA = 4236.04;*/
/*end;*/
/**/
/*/* needs to be added to sheet*/*/
/*if full_name = 'TarrynFredericks' then do;*/
/*Monthly_Earn_after_QA = 3000;*/
/*end;*/
/**/
/*/* needs to be added to sheet*/*/
/*if Employee_Number = 'F8872893' then do; /*Adding in Suveshen on secure chat*/*/
/*Monthly_Earn_after_QA = 3000;*/
/*end;*/;

if Perfomance_Incentive = . then Perfomance_Incentive = 0;
else Perfomance_Incentive =Perfomance_Incentive;
if QA_Score_Perc = . then QA_Score_Perc=100;
else QA_Score_Perc =QA_Score_Perc;
if Sales_Incentive = . then Sales_Incentive = 0;

Total_incentive = Monthly_Earn_after_QA + Perfomance_Incentive + Sales_Incentive;

run;


/*LOC Monthly earn and COMP Monthly Earn*/
data LOC_Monthly_Earn  COMP_Monthly_Earn;
set SERVICING_MONTHLY_INCENTIVE;
if line in ('LOC 2','LOC 1') then output LOC_Monthly_Earn;
else output COMP_Monthly_Earn;
run;


/*** NOTE: Change File Name to Recent Day  ***/

/* Export to Excel with separate sheets */
ods excel file='/data/fnbinsurance/Corporate_Actuarial/Short_Term/Servicing/Serv_Output_JAN2026_run1.csv' options(sheet_name='COMP Final_Earns');
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

/* NOTE: Kendall Mohammed should only start appearing after Feb's OBR run. 
         @Morris you can manually delete this agent from the sheets          */

/* Getting List of Agents on Secure Chat */
Data Secure_Chat_Agents;
Set  STI_PBI.STI_Servicing_Agents;
IF Active = 1;
Run;
