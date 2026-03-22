
%put TAG:JobName1=Short Term sales Tables load to SQL; /* 1st Level of the Job Name --> Max 64 Chars */
%put TAG:JobName2=JobSubName; /* Optional Second Level of the Job Name (used for sub dividing Jobs if needed) --> Max 64 Chars */
%put TAG:JobCategory=ETL; /* ETL, Model, NON-MODEL --> Max 16 Chars */
%put TAG:JobPurpose=Operational; /* Regulatory Reporting, Internal Reporting, Operational, Leads/Campaigns --> Max 64 Chars */
%put TAG:JobPriority=Critical; /* Low (multiple runs can fail without rerun), Medium (one run can fail without rerun), High (cannot fail without rerun but we won’t incur any penalty), Critical (cannot fail without rerun & has to complete before known time else we will suffer financial loss or penalties) --> Max 8 Chars */
%put TAG:JobStatus=Prod;


/*********************************************************************************************************/
/* Sales table code: 
	Inputs: 
		- Monthly API
		- Business Days in a month
		- Risks sold for the month
		- Policies Sold for the month
		- Quotes done in a day
		- Cancellation %
		- QA score
*/
/*********************************************************************************************************/

%include "/data/fnbins/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Automation/STI_CA_2/Libnames.sas";

%include '/data/fnbinsurance/Warehouse/00 Metadata/SAS Enhanced Libnames.sas';
%include '/data/fnbinsurance/Warehouse/00 Metadata/SAS Raw Data Libnames.sas';


/*********************************************************************************************************/



%let date =%SYSFUNC(intnx('month',%SYSFUNC(today()),-18,'e'));
%let start_date_pre = %SYSFUNC(intnx(MONTH,%SYSFUNC(today()),-18,S),date9.);
%let start_date = %sysfunc(translate(&start_date_pre, , ));
%PUT &start_date.;
/*%let start_date = '01MAR2024'd;*/
%let end_date ='09MAR2025'd ;

%let start_date_sql = %SYSFUNC(intnx(MONTH,%SYSFUNC(today()),-14,S),yymmdd10.);
%put &start_date_sql.;
/*%let start_date_sql = 2024-03-01;*/
%let end_date_sql = 2025-03-09;


%let today_sql = %sysfunc(putn(%sysfunc(today()), yymmdd10.));
%put &today_sql;

%let today_date = %sysfunc(putn(%sysfunc(today()), date9.));
%let formatted_date = %sysfunc(translate(&today_date, , ));
%put &formatted_date;

%let yesterday = %sysfunc(putn(%sysfunc(intnx(day, %sysfunc(today()), -1)), yymmdd10.));
%put &yesterday;

%let CurrentDateTime = %sysfunc(today(),yymmddn8.)%sysfunc(time(),time8.);
%put &CurrentDateTime;

/*Get the latest data in SQL*/

/*Agent allocation to desk, team leader and manager*/
proc sql;
create table SalesTeamStructure as 
select distinct FNumber
FROM STI_SL.SalesTeamStructure
/*Where datepart(EndDate)>= "&formatted_date"d*/
;quit;

/*Agent inputs - SaleYM, workdays, business days, QA, Comment category*/
proc sql;
create table agentinputs as 
select * 
FROM STI_SL.SalesAgentInputs 
;quit;

data SalesFnumbers;
    length FNumber $8;                 /* Define attributes first */
    set SalesTeamStructure;
    FNumber = substr(FNumber, 1, 8);   /* Truncate to 8 */
run;

proc sql;
select quote(FNumber)
into :Sales_Agents separated by ','
from SalesFnumbers
;quit;
%put &Sales_Agents;

/*Look for max date in sql table*/
proc sql;
create table sqldates as 
select distinct date
FROM STI_SL.agent_stats_daily_hist
;quit;

/*********************************************************************************************************/
/* API, Risks sold and policies sold */
proc sql;
create table salesonly as select *,datepart(salesdate)as salesdate2 format date9.
,case when covername in ('Motor Third party, Fire & Theft','Motor Third Party Only','Caravan Comprehensive','Pleasure craft Comprehensive','Trailer Comprehensive') then 'Motor_Non_Comprehensive'
when covername in ('Motor Vaps','Temporary Transport','Take Home Service','Unspecified Portables','Credit Shortfall','Scratch and Dent','Tyre and Rim') then 'Motor_VAPs'
when covername in ('Caravan Contents','Caravan Comprehensive','Motor Comprehensive','Motor cycle Comprehensive','Motorcycle Third Party Only','Motorcycle Third party, Fire & Theft','Motor Comprehensive','Pleasure craft Contents') then 'Motor'
when covername contains "Buildings" then 'Buildings'
when covername in('Buildings Comprehensive','Buildings Combined','Water Heating System Wear and Tear Cover','Power Surge - Additional')then 'Buildings'
	when covername in('Accidental Damage','Accidental Damage (Buy Up)','Power Surge (Buy-Up)') then 'Home_Contents'
	when covername in ('Accidental Damage (Buy Up)','Home Content Comprehensive') then 'Home_Contents'
		when covername like '%Portable Po%' then 'Portable_Possessions'
	when covername like '%Personal%' then 'Personal_Liability'
when PARENTLOB like '%Owner%' then 'Buildings'
when  ParentLOB like '%Home Contents%' then 'Home_Contents'
else ParentLOB end as covername2 
, api/1.15 as API_new
,case when covername = 'Portable Possession Comprehensive' then PolicyID
		when covername NOT IN ('Personal Liability','Water Heating System Wear and Tear Cover')
						and  (datepart(salesdate)) > &date and parentlobinb=1 then OriginalAssetID
	 	end as ItemCountVar
from WH_SS.SS_SALES
where coverpremium > 0 and parentLOB not in ( 'Sasria','Business Cashflow'
											,'Outstanding Debt Protection'
/*											,'Money Protect Plus'*/
											)
and covername not contains 'Sasria'
and covername not contains 'Business CashFlow Cover' and calculated covername2 ne 'Motor Vaps'
/*and saleym>202206 */
and producttype not contains 'Comm' 
/*and pointofsale not contains 'Ren'*/
and salesind=1
/*and covername not contains 'Water'*/
and saleym>202401
and datepart(salesdate)>= "&start_date"d
and datepart(salesdate) <=  "&formatted_date"d
order by policyid, covername,itemid,versionid
;quit;

proc sql;
create table salesummary as
Select PolicyNumber
		,UCN
		,SalesDate as SalesDateTime
		,datepart(SalesDate) as SalesDate format=date9.
		,SaleYM
		,upcase(SalesUser) as SalesUser
		,SalesUserName
		,case 
				when upcase(SalesUser) in (Select distinct FNumber FROM SalesTeamStructure) then "Sales Agent"
				when (SalesUser = 'SVCACCMANINSPROD' and datepart(SalesDate) >= '05Nov2025'd) then "STP Process"
				else 'Other'
				end as SalesUserClassification
		,PointOfSale
		,count(distinct ItemCountVar) as ItemCount
		,sum(CoverPremium) as CoverPremium
		,sum(API) as API
		,sum(API_new) as API_ExVAT

		,count(distinct case when covername2 = 'Buildings' then  ItemCountVar end) as Buildings_count
		,count(distinct case when covername2 = 'Home_Contents' then  ItemCountVar end) as Home_Contents_count
		,count(distinct case when covername2 = 'Motor' then  ItemCountVar end) as Motor_count
		,count(distinct case when covername2 = 'Motor_Non_Comprehensive' then  ItemCountVar end) as Motor_Non_Comprehensive_count
		,count(distinct case when covername2 = 'Motor_VAPs' then  ItemCountVar end) as Motor_VAPs_count
		,count(distinct case when covername2 = 'Personal_Liability' then  ItemCountVar end) as Personal_Liability_count
		,count(distinct case when covername2 = 'Portable_Possessions' then  ItemCountVar end) as Portable_Possessions_count

		,sum(case when covername2 = 'Buildings' then  API_new end) as Buildings_API
		,sum(case when covername2 = 'Home_Contents' then  API_new end) as Home_Contents_API
		,sum(case when covername2 = 'Motor' then  API_new end) as Motor_API
		,sum(case when covername2 = 'Motor_Non_Comprehensive' then  API_new end) as Motor_Non_Comprehensive_API
		,sum(case when covername2 = 'Motor_VAPs' then  API_new end) as Motor_VAPs_API
		,sum(case when covername2 = 'Personal_Liability' then  API_new end) as Personal_Liability_API
		,sum(case when covername2 = 'Portable_Possessions' then  API_new end) as Portable_Possessions_API
FROM salesonly
/*Where datepart(SalesDate) = '10MAR2025'd*/
GROUP BY PolicyNumber
		,UCN
		,SalesDateTime
		,SalesDate
		,SaleYM
		,SalesUser
		,SalesUserName
		,PointOfSale
		,case when upcase(SalesUser) in (Select distinct FNumber FROM SalesTeamStructure) then "Sales Agent"
				when SalesUser = 'SVCACCMANINSPROD' then "STP Process"
				else 'Other'
				end 
ORDER BY SalesDate desc
;quit;

proc sql;
create table salesummary_hist as
Select PolicyNumber
		,UCN
		,SalesDate as SalesDateTime
		,datepart(SalesDate) as SalesDate format=date9.
		,SaleYM
		,upcase(SalesUser) as SalesUser	
		,SalesUserName
		,PointOfSale
		,case when upcase(SalesUser) in (Select distinct FNumber FROM SalesTeamStructure) 
				then "Sales Agent"
				when SalesUser = 'SVCACCMANINSPROD' then "STP Process"
				else 'Other'
				end as SalesUserClassification
		,count(distinct ItemCountVar) as ItemCount
		,sum(CoverPremium) as CoverPremium
		,sum(API) as API
		,sum(API_new) as API_ExVAT

		,count(distinct case when covername2 = 'Buildings' then  ItemCountVar end) as Buildings_count
		,count(distinct case when covername2 = 'Home_Contents' then  ItemCountVar end) as Home_Contents_count
		,count(distinct case when covername2 = 'Motor' then  ItemCountVar end) as Motor_count
		,count(distinct case when covername2 = 'Motor_Non_Comprehensive' then  ItemCountVar end) as Motor_Non_Comprehensive_count
		,count(distinct case when covername2 = 'Motor_VAPs' then  ItemCountVar end) as Motor_VAPs_count
		,count(distinct case when covername2 = 'Personal_Liability' then  ItemCountVar end) as Personal_Liability_count
		,count(distinct case when covername2 = 'Portable_Possessions' then  ItemCountVar end) as Portable_Possessions_count

		,sum(case when covername2 = 'Buildings' then  API_new end) as Buildings_API
		,sum(case when covername2 = 'Home_Contents' then  API_new end) as Home_Contents_API
		,sum(case when covername2 = 'Motor' then  API_new end) as Motor_API
		,sum(case when covername2 = 'Motor_Non_Comprehensive' then  API_new end) as Motor_Non_Comprehensive_API
		,sum(case when covername2 = 'Motor_VAPs' then  API_new end) as Motor_VAPs_API
		,sum(case when covername2 = 'Personal_Liability' then  API_new end) as Personal_Liability_API
		,sum(case when covername2 = 'Portable_Possessions' then  API_new end) as Portable_Possessions_API
FROM salesonly
GROUP BY PolicyNumber
		,UCN
		,SalesDateTime
		,SalesDate
		,SaleYM
		,SalesUser
		,SalesUserName
		,PointOfSale
		,case when upcase(SalesUser) in (Select distinct FNumber FROM SalesTeamStructure) then "Sales Agent"
				when SalesUser = 'SVCACCMANINSPROD' then "STP Process"
				else 'Other'
				end
ORDER BY SalesDate desc
;quit;


proc sql;
create table salesummary_hist_long as
Select PolicyNumber
		,UCN
		,SalesDate as SalesDateTime
		,datepart(SalesDate) as SalesDate format=date9.
		,SaleYM
		,upcase(SalesUser) as SalesUser	
		,SalesUserName
		,PointOfSale
		,case when upcase(SalesUser) in (Select distinct FNumber FROM SalesTeamStructure) then "Sales Agent"
				when SalesUser = 'SVCACCMANINSPROD' then "STP Process"
				else 'Other'
				end as SalesUserClassification
		,covername2 as LOB
		,Covername
		,count(distinct ItemCountVar) as ItemCount
		,sum(CoverPremium) as CoverPremium
		,sum(API) as API
		,sum(API_new) as API_ExVAT

FROM salesonly
GROUP BY PolicyNumber
		,UCN
		,SalesDateTime
		,SalesDate
		,SaleYM
		,SalesUser
		,SalesUserName
		,PointOfSale
		,case when upcase(SalesUser) in (Select distinct FNumber FROM SalesTeamStructure) then "Sales Agent"
				when SalesUser = 'SVCACCMANINSPROD' then "STP Process"
				else 'Other'
				end
		,covername2
		,covername
ORDER BY SalesDate desc
;quit;


/*********************************************************************************************************/
/*Quotes*/

proc sql;
	CONNECT TO ODBC (DSN='RBIDTPRDSS1_SMARTSTORE' USER="fnbjnb01\&svc_User" PASSWORD="&svc_Pwd");


	Create Table  QuoteSQL as 
	Select ProductType,ProductCode ,scan(PolicyNumberStep,1,'/') as PolicyNumber 
			,PolicyID
			,VersionID	
			,CoverID
			,ItemID	
			,OriginalAssetID
			,policy_asset_nr
			,ContactID
			,CoverName
              , CASE WHEN CoverName IN ( 'Buildings Comprehensive',"Water Heating System Wear and Tear Cover",'Business CashFlow Cover',
						'Motor Third Party Only','Motor Third party, Fire & Theft','Motor Comprehensive','Motor cycle Comprehensive',
						'Motorcycle Third Party Only',"Motorcycle Third party, Fire & Theft",'Pleasure craft Comprehensive','Caravan Comprehensive'
						,'Caravan Contents','Trailer Comprehensive', 'Home Content Comprehensive', 'Portable Possession (Specified)','Portable Possession Comprehensive',
						 'Personal Liability','Sasria - Motor','Sasria -Fire Domestic','Sasria -Non Motor'
						 /*new from here */
						,'Sasria - Material Damage','Fire','Buildings Combined','Office Contents','Commercial Umbrella Protection (CUP)'
						/*till here*/
                                                 ) THEN 1
                      ELSE 0
                END AS ParentLOBINB /*this needs to Parent_LOB_Count_IND correspond to in SS_cover*/
			,ParentLOB
/*CHANGE HERE 20230921*/			
/*				,ProductLOBFull*/
				,case when ParentLOB contains 'Invisible' then 'Invisible'
					when ProductLOBFull="Business CashFlow Cover (BCC)" then  'BCC'
					when ProductLOBFull='Liability' and  ProductType='FNB Insure Commercial' then 'CLI'	
					when ProductLOBFull='Motor' and  ProductType='FNB Insure Commercial' then 'CVE'
					when ProductLOBFull='Property' then 'CBU'
					when ProductLOBFull='Sasria' then 'SRS'
					when ProductLOBFull='Building' then 'BUI'
					when ProductLOBFull='Home Content' then 'CON'
					when ProductLOBFull='Liability' and  ProductType='FNB Insure Retail' then 'LIA'
					when ProductLOBFull='Motor' and  ProductType='FNB Insure Retail' then 'VEH'
					when ProductLOBFull='Portable Possession' then 'POR'
					when ProductLOBFull='Trailer, caravan and Pleasure craft' then 'TCP'
					else 'NeedCode' end as ProductLOB /*this needs to ProductLOB correspond to in SS_cover and ss_new claim*/
/*end change*/
			,SumInsured format 30.2
			,INSURED_ITEM_DESC
			,OWNER_ENTITY_ID
			,PolicyholderSurname 
			,PolicyholderName
			,IDNUmber
			,CustomerIDType
			,UCN
			,case when EVENT_TYPE_DSC in ('New policy', 'New policy BCC') then 'New policy'
			when EVENT_TYPE_DSC like 'Active Policy Updated' 
				or EVENT_TYPE_DSC like '%Active Policy is updated%' then 'Endorsement'
			when EVENT_TYPE_DSC like 'New proposal Finalised for the reason Accepted but not Active'
				or EVENT_TYPE_DSC like 'Proposal Updated for the reason Accepted but not Active' then 'ABNA'	
			when EVENT_TYPE_DSC like 'Renewal Proposal Updated' then 'Renewal endorsement' end as PointOfSale
/*			,EVENT_TYPE_DSC*//* this holds the original description */
			,SalesUser	
			,SalesUserName
			,CREATION_DATE as ProposalDate
			,START_TIME as SalesDate
			,datepart(ASSET_START_DATE) as CoverStartDate format date9.
			,year(datepart(START_TIME))*100+month(datepart(START_TIME)) as SaleYM
			,CoverPremium format 30.2
			,API format 30.2 
			,OriginalDiscountUser
			,OriginalDiscountUserName
		,case when PREVIOUS_PREMIUM_ADJUST=. and  CURRENT_PREMIUM_ADJUST=. then 0
		when PREVIOUS_PREMIUM_ADJUST=. then CURRENT_PREMIUM_ADJUST
		else PREVIOUS_PREMIUM_ADJUST  end as OriginalAppliedDiscountPct
		,  SalesCompletePriority
		,EVENT_TYPE_DSC
		,EVENT_NR
	FROM CONNECTION TO ODBC
 	( SELECT pp.POLICY_HEADER_ID [PolicyID]
      				,PC.[ENDORSMENT_ID] [VersionIDe]
	  				,PC.[ID] [CoverID]
					,GI.CONTRACT_INSURED_ITEM_ID as ItemID
	  				,ee.CLIENT	[ContactID]
	  				,pp.EXTERNAL_POLICY_NUMBER	
					,pp.EXTERNAL_PROPOSAL_NUMBER
					,pp.CREATION_DATE
					,case when pp.EXTERNAL_PROPOSAL_NUMBER is null
						then pp.EXTERNAL_POLICY_NUMBER
						else pp.EXTERNAL_PROPOSAL_NUMBER end as PolicyNumberStep
 					,PC.PARENT_COVER_ID  
					,gi.INSURED_ITEM_DESC
  					,PC.ASSET_ID	
					,PC.INS_AMN as SumInsured
	      			,TPLO.[DESCRIPTION] as CoverName
					,case when GI.PARENT_GENINS_CVG_ID<>'' then GI2.COVERAGE_TYPE_DESC
						else GI.COVERAGE_TYPE_DESC end as ParentLOB
					,gcvl.LOB_DESC as ProductLOBFull 
					,ppla.ORIGINAL_LOB_ASSET_ID
					,ppla.policy_asset_nr
					,ppla.ASSET_START_DATE
 					,case when ppla.ORIGINAL_LOB_ASSET_ID<>'' then ppla.ORIGINAL_LOB_ASSET_ID
						else PC.ASSET_ID end as OriginalAssetID
		  			,tet.EVENT_TYPE_DSC
					,TU.NAME_OF_USER [SalesUser]
					,UD.USER_NAME [SalesUserName]
					,ee.START_TIME
					,ee.EVENT_DATE
					,ee.UPDATE_DATE
		  			,cast(PCE.BSC_YEAR_PREM_AMN as NUMERIC(38,5)) [CoverPremiumOld]
		  			,cast(pce.DAY_PREM_AMN_SYS as NUMERIC(38,5)) [CoverPremium]
		  			,pce.DAY_PREM_AMN_SYS*12*1.15 [API]
		  			,PCE.DAYS_PER_TERM
					,tcs.[DESCRIPTION] as cover_status
					,gcv.OWNER_ENTITY_ID
					,gcv.PRODUCT_DESC           as  ProductType 
					,gcv.CONTRACT_VERSION_NUM   as VersionID
					,gcv.PRODUCT_CD           as ProductCode
					,ed.ENTITY_PREF_INDENTIFIER_NUM  as IDNumber
					,ed.ENTITY_PREF_IDENTIFIER_DESC  as CustomerIDType

					,convert(varchar(50),edf.UCN,40 ) as UCN
					,UPPER(LEFT(i.ENTITY_FIRST_NM,1))+LOWER(RIGHT(i.ENTITY_FIRST_NM,LEN(i.ENTITY_FIRST_NM)-1))       as PolicyholderName
					,UPPER(LEFT(i.ENTITY_LAST_NM,1))+LOWER(RIGHT(i.ENTITY_LAST_NM,LEN(i.ENTITY_LAST_NM)-1))       as PolicyholderSurname
	
					,pplaf.PREVIOUS_PREMIUM_ADJUST	
					,pplaf.CURRENT_PREMIUM_ADJUST
					,pplaf.PREMIUM_ADJUST_USER_ID

					,TU.NAME_OF_USER [OriginalDiscountUser]
					,UD.USER_NAME [OriginalDiscountUserName]
					,EVENT_NR
					,case when (tet.EVENT_TYPE_DSC like 'New policy' 
						or EVENT_TYPE_DSC like 'Active Policy Updated'
						or EVENT_TYPE_DSC like 'New proposal Finalised for the reason Accepted but not Active'
						or EVENT_TYPE_DSC like '%Active Policy is updated%'
						or EVENT_TYPE_DSC like 'Renewal Proposal Updated'
						or EVENT_TYPE_DSC like 'Proposal Updated for the reason Accepted but not Active'
						or EVENT_TYPE_DSC like 'New policy BCC') then 0 else 1 end as SalesCompletePriority

 			FROM [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[P_POLICY] as pp     
			left join [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[P_COVER] as PC
  				on PC.ENDORSMENT_ID=PP.ID
			left join [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[E_EVENT] as EE
	  			on EE.POLICY=pp.ID
			left join [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[T_EVENT_TYPE] as TET
	  			on ee.EVENT_TYPE=tet.EVENT_TYPE
  			left join [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[T_USER] as TU
				on TU.USERID=EE.INSERT_USER
  			left join [FNB_SMARTSTORE_PROD].[SI_CORE_DWH].[USER_DETAILS] as UD
				on UD.USER_NUM=EE.INSERT_USER
			left join [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[T_PRODUCT_LINE_OPTION] as TPLO
				on PC.[PRODUCT_OPTION_ID]=TPLO.[ID]
  			left join [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[P_POLICY_LOB_ASSET] as ppla 
				on PC.[ASSET_ID] = ppla.[ID]
  			left join [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[P_POLICY_LOB_ASSET_FNB] as pplaf 
				on PC.[ASSET_ID] = pplaf.[ID]
  			left join [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[T_USER] as TU2
				on TU2.USERID=pplaf.PREMIUM_ADJUST_USER_ID
  			left join [FNB_SMARTSTORE_PROD].[SI_CORE_DWH].[USER_DETAILS] as UD2
				on UD2.USER_NUM=pplaf.PREMIUM_ADJUST_USER_ID
			LEFT JOIN (Select *,ROW_NUMBER() Over (Partition By COVER_ID Order By EXT_NR DESC)  AS RN 
							from [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[P_COVER_EXT] ) AS PCE 
				ON PC.ID =PCE.COVER_ID AND  PCE.RN=1
			left join [FNB_SMARTSTORE_PROD].[SI_CORE_DWH].[GENINS_INS_ITM_SEC_CVG] as GI
				on PC.[ID]=GI.COVERAGE_NUM
			left join [FNB_SMARTSTORE_PROD].[SI_CORE_DWH].[GENINS_CONTRACT_VERSION] as GCV
				on gcv.CONTRACT_VERSION_NUM=PC.ENDORSMENT_ID
			left join [FNB_SMARTSTORE_PROD].[SI_CORE_DWH].[GENINS_INS_ITM_SEC_CVG] as GI2
				on GI.PARENT_GENINS_CVG_ID= GI2.COVERAGE_NUM
			left join [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[T_COVER_STATUS] as tcs
  				on ppla.ASSET_STATUS=tcs.[ID]
			left join FNB_SMARTSTORE_PROD.SI_CORE_DWH.ENTITY_Details as ed
				on gcv.OWNER_ENTITY_ID = ed.ENTITY_ID
			left join FNB_SMARTSTORE_PROD.SI_CORE_DWH.ENTITY_DETAILS_FNB as edf 
				on gcv.OWNER_ENTITY_ID = edf.ENTITY_ID
			left join FNB_SMARTSTORE_PROD.SI_CORE_DWH.INDIVIDUAL as I 
				on gcv.OWNER_ENTITY_ID = i.INDI_ENTITY_ID		
						left join [FNB_SMARTSTORE_PROD].[SI_CORE_DWH].[GENINS_CON_VER_LOB] as gcvl
							on gcvl.CONTRACT_LOB_ID=GI.CONTRACT_LOB_ID
			where  pce.DAY_PREM_AMN_SYS<>0 /*remove all rideres that are standard*/
					and ee.START_TIME >= %bquote('&start_date_sql.')
					and ee.START_TIME <= %bquote('&today_sql.')
					and TU.NAME_OF_USER in (&Sales_Agents)
												)		
	
	;disconnect from odbc
;quit;

proc sql;
create table quotes as 
select distinct PolicyNumber
		,EVENT_TYPE_DSC as QuoteStatus
		,SalesDate as StatusStartTime
		,UCN
		,ProposalDate
		,SaleYM
		,SalesUser
		,SalesUserName
		,CoverPremium	
		,OriginalAppliedDiscountPct
from QuoteSQL
;quit;

proc sql;
create table quotetable_hist as 
Select PolicyNumber
		,UCN
		,datepart(StatusStartTime) format = date9. as QuoteStatusDate
		,StatusStartTime as QuoteStatusDateTime
		,QuoteStatus
		,upcase(SalesUser) as SalesUser
		,SalesUserName
		,CoverPremium	
		,OriginalAppliedDiscountPct
from quotes
ORDER BY 2 desc
;quit;

proc sql;
create table quotetable_hist_summary as 
Select intnx('Month',datepart(StatusStartTime),0,'E') format = date9. as QuoteMonth
		,upcase(SalesUser) as SalesUser
		,count(distinct PolicyNumber) as QuoteCount
from quotes
Where SalesUser in (select distinct Fnumber 
					FROM STI_SL.SalesTeamStructure 
					Where Team in ('CMB','Elite','Inbound and switch','Instruct'))
GROUP BY 1,2
ORDER BY 2 desc
;quit;

/*********************************************************************************************************/
/*Cancellations*/

PROC SQL;
CONNECT TO ODBC (DSN='RBIDTPRDSS1_SMARTSTORE' USER="fnbjnb01\&svc_User" PASSWORD="&svc_Pwd");
CREATE TABLE Billing AS
SELECT      SUBSTR(EXTERNAL_NUM,1,FIND(EXTERNAL_NUM,"/")-1) AS Policy_Number,
            put(PolicyID,8.) as PolicyID,
            CASE WHEN UPCASE(COMPRESS(StatusDesc)) IN ('PAID','PARTIALLYPAID') THEN 'S'
            WHEN UPCASE(COMPRESS(StatusDesc)) IN ('PAYMENTREJECTED') THEN 'F'
            WHEN UPCASE(COMPRESS(StatusDesc)) IN ('PENDING') THEN 'P'
            WHEN UPCASE(COMPRESS(StatusDesc)) IN ('CANCELLED') THEN 'C'
            END AS Status,
            *
FROM CONNECTION TO ODBC (
SELECT   i.CONTRACT_ID                      AS PolicyID
        ,i.INSTALLMENT_NUM                  AS Inst_Num
        ,t.TRANSACTION_ID                   AS Trns_ID
        ,CONVERT(numeric,i.CONSOLIDATED_INSTALLMENT_NRT)    AS Bank_Key
        ,CONVERT(DATE,i.INSTALLMENT_DUE_DT) AS Due_Dt
        ,CONVERT(DATE,ACI.ORIGINAL_COLLECTION_DATE) AS ORIGINAL_COL_DT
        ,CONVERT(DATE,i.INSTALLMENT_END_DT) AS End_Dt
        ,CONVERT(DATE,t.TRANSACTION_PAID_DT) AS Paid_Dt
        ,CONVERT(DATE,i.COLLECTION_DT)      AS Col_Dt
        ,CONVERT(DATE,ACI.START_PERIOD)     AS START_PERIOD
        ,CONVERT(DATE,ACI.END_PERIOD)       AS END_PERIOD 
        ,CONVERT(money,i.ESTIMATED_FEES_AMOUNT_TRAN_CUR)        AS Total_Amount
        ,CONVERT(money,ROUND(-1*COALESCE(i.PAID_AMOUNT_HOME_CUR,0.01),2)) AS Paid_Amount
        ,i.COLLECTION_METHOD_DESC               AS Method
        ,CONVERT(NUMERIC,CN.ACCOUNT_NR) AS ACCOUNT_NR
        ,COALESCE(h.EXTERNAL_POLICY_NUMBER,h.EXTERNAL_PROPOSAL_NUMBER) AS EXTERNAL_NUM
        ,i.INSTALLMENT_TYPE_DESC            AS Inst_Cycle
        ,i.INSTALLMENT_STATUS_DESC          AS StatusDesc
        ,ACS.DESCRIPTION AS INST_STATUS_DESC 
        ,I.PAYER_ID
        ,E.ENTITY_NUM 
        ,CN.ID AS CN_ID
        ,cv.PRODUCT_DESC 
        ,cv.CONTRACT_STATUS_DESC
        ,cv.CONTRACT_STATUS_REASON_DESC
        
        ,CONVERT(money,i.INSTALLMENT_AMOUNT_TRAN_CUR)       AS Net_Vat
        ,CONVERT(money,i.INSTALLMENT_TAX_AMOUNT_HOME_CUR)   AS Vat
        ,CONVERT(money,TOTAL_ANNUAL_PREMIUM_HOME_CUR)       AS ContractPremium 
        ,cv.Premium_Due_Day
        ,CONVERT(DATE,T.TRANSACTION_ENTRY_DT) AS Entry_Dt
        ,CONVERT(DATE,i.INSTALLMENT_START_DT)   AS Start_Dt
        ,E.ENTITY_PREF_INDENTIFIER_NUM  AS IDNO
        ,E.PREF_BANK_ACCOUNT_NUM AS ACCTNO
        ,CONVERT(DATE,CN.UPDATE_DATE) AS CN_UPDATE_DATE
        ,CONVERT(DATE,CN.DISCONTINUE_DATE) AS CN_DISCONTINUE_DATE
        ,CN.BANK_ACCOUNT_EXTERNAL_NUMBER
        ,E.ENTITY_FULL_NM AS FULL_NAME
        
 FROM       SI_CORE_DWH.CONTRACT_VERSION_INST(nolock)  AS i 
 LEFT JOIN  SI_CORE_DWH.TRANSACTION_DETAILS(nolock)  AS t 
 ON         i.INSTALLMENT_NUM = t.TRANSACTION_NUM
 LEFT JOIN  SI_CORE_DWH.ENTITY_DETAILS(nolock) AS E 
 ON         E.ENTITY_ID = I.PAYER_ID
 LEFT JOIN  SI_CORE_IDIT_ODS.AC_INSTALLMENT(nolock) ACI
 ON ACI.ID=I.INSTALLMENT_NUM    
 LEFT JOIN SI_CORE_IDIT_ODS.T_INSTALLMENT_STATUS_TYPE ACS
    ON ACS.ID=ACI.INSTALLMENT_STATUS
 LEFT JOIN  SI_CORE_IDIT_ODS.CN_CONTACT_BANK_ACCOUNT CN
 ON         CN.ID = ACI.CONTACT_BANK_ACCOUNT_ID
/* AND      CN.UPDATE_DATE <= COALESCE(I.INSTALLMENT_END_DT,I.DUE_DT)*/
 LEFT JOIN  SI_CORE_DWH.GENINS_CONTRACT_VERSION(nolock) cv
ON          cv.CONTRACT_VERSION_ID = i.CONTRACT_VERSION_ID
LEFT JOIN  SI_CORE_IDIT_ODS.P_POLICY (nolock) h
ON ACI.POLICY_ID = h.ID
/*WHERE         i.INSTALLMENT_STATUS_DESC <> 'Cancelled'*/
ORDER BY i.CONTRACT_ID,I.INSTALLMENT_NUM,CN.ID DESC
;)
;Disconnect from ODBC;
QUIT;

PROC SORT DATA= Billing nodupkey ;
BY Policy_Number Inst_Num;
RUN;

proc sql;
connect to ODBC (dsn='RBIDTPRDSS1_SMARTSTORE' USER="fnbjnb01\&svc_User" PASSWORD="&svc_Pwd");
Create Table T_REJECTIONS AS
SELECT *
FROM CONNECTION TO odbc (

    SELECT   IR.INSTALLMENT_ID
            ,CONVERT(DATE,IR.REJECT_DATE) AS REJECT_DATE
            ,IR.REJECT_NUMBER
            ,RT.DESCRIPTION AS REJECT_TYPE
            ,RC.DESCRIPTION AS REJECT_DESC
            ,RC.EXTERNAL_CODE AS REJECT_CODE
            
    FROM SI_CORE_IDIT_ODS.AC_INSTALLMENT_REJECT IR
    LEFT JOIN SI_CORE_IDIT_ODS.T_PMNT_REJECT_TYPE RT 
        ON RT.ID = IR.REJECT_TYPE_ID
    LEFT JOIN SI_CORE_IDIT_ODS.T_PMNT_REJECT_CODE RC
        ON RC.ID = IR.REJECT_CODE_ID
);
;Disconnect from ODBC;
QUIT;

PROC SQL ;
CREATE TABLE WH_Policy AS 
SELECT  a.ProductType,
        a.UCN,
        a.PolicyNumber,
        a.ContractID,
        a.CustomerID,
        a.PolicyNumberVersion,
        a.ContractVersionID,
        a.PolicyPermium as PolicyPremium,
        DATEPART(a.InceptionDate) AS InceptionDate ,
        a.Origin,  
        a.SalesChannel,
        a.UserName,
        DATEPART(a.SalesDate) AS SalesDate FORMAT date9.,
        INTNX("MONTH",DATEPART(a.SalesDate),0,"E") AS SalesMonth format date9. ,
        a.LoadDate,
        INTNX("MONTH",a.LoadDate,0,"E") AS LoadMonth format date9. ,
        DATEPART(VersionStartDate) AS VersionStartDate FORMAT date9.,
        VersionStartDate as VStart,
        DATEPART(VersionEndDate) AS VersionEndDate FORMAT date9.,
        DATEPART(ContractVersionStartDate) AS ContractVersionStartDate FORMAT date9.,
        ContractVersionendDate,
        b.PrimaryStatus as PolicyStatus
FROM    wh_ss.ss_Policy a
LEFT JOIN WH_SS.SS_Product b
ON a.PolicyNumber = b.PolicyNumber
WHERE VersionEndDate = .
; QUIT;

PROC SORT DATA= WH_Policy ;
BY PolicyNumber descending VStart;
RUN;

PROC SORT DATA= WH_Policy nodupkey;
BY PolicyNumber;
RUN;

proc sql;
connect to ODBC (dsn='RBIDTPRDSS1_SMARTSTORE' USER="fnbjnb01\&svc_User" PASSWORD="&svc_Pwd");
Create Table GENINS_CONTRACT_VERSION_REASON AS
SELECT *
FROM CONNECTION TO odbc (

    SELECT  CV.CONTRACT_VERSION_ID,CV.CONTRACT_STATUS_DESC,
            VR.REASON_DESC,
            CV.CANCELLED_BY_DESC,
            CONVERT(DATE,cv.LAST_UPDATE_DATE) AS LAST_UPDATE_DATE
    FROM    SI_CORE_DWH.GENINS_CONTRACT_VERSION CV 
    LEFT JOIN SI_CORE_DWH.GENINS_CONTRACT_VERSION_REASON vr
        ON VR.CONTRACT_VERSION_ID =CV.CONTRACT_VERSION_ID
    WHERE CV.CONTRACT_STATUS_DESC='Cancelled Policy'
);
;Disconnect from ODBC;
QUIT;

PROC SQL ;
CREATE TABLE PolicyCancellations AS 
SELECT  PolicyNumber,
        VersionStartDate,
        LAST_UPDATE_DATE,
        PolicyStatus,
        CANCELLED_BY_DESC,
        REASON_DESC,
        c.*

FROM    WH_Policy c
LEFT JOIN GENINS_CONTRACT_VERSION_REASON VR 
    ON VR.CONTRACT_VERSION_ID=C.ContractVersionID
WHERE PolicyStatus='Cancelled'
ORDER BY PolicyNumber,ContractVersionID
; QUIT;

PROC SQL ;
CREATE TABLE BILLING_R AS 
SELECT  B.Policy_Number,
        B.Inst_Num,
        CASE WHEN REJECT_DATE>0 THEN "F" ELSE B.STATUS END AS STATUS,
        B.STATUS AS STATUS_OLD,
        B.TOTAL_AMOUNT,
        b.DUE_DT,
        R.REJECT_DATE,
        B.END_DT,
        b.START_PERIOD,
        B.END_PERIOD,
        R.REJECT_TYPE,
        REJECT_CODE,
        *
FROM BILLING B 
LEFT JOIN T_REJECTIONS R 
    ON B.INST_NUM = R.INSTALLMENT_ID
WHERE B.STATUS IN ('F','S','C')
AND B.POLICY_NUMBER IN (SELECT POLICYNUMBER FROM PolicyCancellations 
                        )
ORDER BY B.Policy_Number, B.Due_Dt, B.Inst_Num, REJECT_NUMBER DESC
; QUIT;

PROC SQL ;
DELETE FROM BILLING_R
WHERE (STATUS='C' AND REJECT_DATE<0) OR Total_Amount = 0
; QUIT;

PROC SORT DATA= BILLING_R nodupkey ;
BY Policy_Number Due_Dt Inst_Num;
RUN;

DATA    BILLING_T_ARREARS BILLING_T_ARREARS_L;
SET     BILLING_R;
BY Policy_Number;
FAIL_IND = IFN(STATUS='F',1,0);
IF FIRST.POLICY_NUMBER THEN ARREARS=FAIL_IND; 
ELSE ARREARS+FAIL_IND;
IF FAIL_IND = 0 THEN ARREARS=0;
IF FIRST.Policy_Number THEN CYCLE=1; ELSE CYCLE+1;

IF LAST.Policy_Number then output BILLING_T_ARREARS_L;
if FAIL_IND IN (0,1) THEN OUTPUT BILLING_T_ARREARS;
KEEP Policy_Number Bank_Key ACCOUNT_NR Due_Dt Col_Dt End_Dt
     Status FAIL_IND ARREARS start_period end_period Inst_Num 
        Inst_Cycle Total_Amount  CYCLE
        reject_code reject_date reject_desc reject_type STATUS_OLD;
RUN;

DATA Billing_T_LAG  ;
FORMAT PREVIOUS_DT PREV_END_DT DATE9.;
SET BILLING_T_ARREARS   ;
BY Policy_Number;
Previous_Status = LAG(Status);
IF  FIRST.Policy_Number THEN Previous_Status = '';
Previous_DT = IFN(FIRST.Policy_Number,.,LAG(DUE_DT));
PREV_END_DT = IFN(FIRST.Policy_Number,.,LAG(END_DT));

RUN;

PROC SORT DATA= Billing_T_LAG ;
BY Policy_Number DESCENDING Due_Dt;
RUN;
DATA Billing_T_LEAD ;
SET Billing_T_LAG   ;
BY Policy_Number;
Next_Status = LAG(Status);
IF  FIRST.Policy_Number THEN Next_Status = '';
NEXT_DT = IFN(FIRST.Policy_Number,.,LAG(DUE_DT));
NEXT_END_DT = IFN(FIRST.Policy_Number,.,LAG(END_DT));

FORMAT NEXT_DT NEXT_END_DT DATE9. ;
RUN;

PROC SQL ;
CREATE TABLE Cancel_Class01 AS 
SELECT  A.PolicyNumber,
        A.CANCELLED_BY_DESC,
        REASON_DESC,
        a.VersionStartDate,
        a.ContractVersionStartDate,
        b.Reject_Date,
        b.REJECT_TYPE,
        b.REJECT_CODE,
        b.Due_dt,
        Cycle,
        Arrears,
        A.PolicyStatus,
        *
FROM    PolicyCancellations a
left join Billing_T_LEAD b on a.PolicyNumber = b.Policy_Number
    and 0<=(a.VersionStartDate-B.REJECT_DATE)
/*  AND NEXT_DT= .*/
ORDER BY A.PolicyNumber,ContractVersionID,b.Reject_Date DESC
; QUIT;

PROC SORT DATA= Cancel_Class01 nodupkey ;
BY Policy_Number ContractVersionID;
RUN;

PROC SQL ;
CREATE TABLE Cancel_Class AS 
SELECT  CASE 
            WHEN CANCELLED_BY_DESC = 'Policyholder' AND a.VersionStartDate <= a.InceptionDate THEN "NTU-CAN"
			WHEN CANCELLED_BY_DESC = 'Carrier' THEN 'CANCELLED-C'
            WHEN CANCELLED_BY_DESC = 'Policyholder' THEN 'CANCELLED-P'
            WHEN ARREARS=1 AND CYCLE=1 THEN "NTU-NP" 
            WHEN REASON_DESC IN ("",'Cancel due to non-payment') AND CYCLE > 1 AND ARREARS not in (0,.) THEN 'LAPSED'
            ELSE "CANCELLED-P" END AS POL_STATUS
            ,a.*,c.PolicyNumber as PolicyNumber2,
			CASE WHEN c.PolicyNumber = "" THEN "Legit Cancel" ELSE "Possible Clone" END as CloneIND
FROM    Cancel_Class01 a
LEFT JOIN WH_SS.SS_POLICY c
ON a.PolicyNumber <> c.PolicyNumber
AND a.VersionStartDate = DATEPART(c.VersionStartDate)
AND a.UserName = c.SalesUserName
AND a.UCN = c.UCN
AND a.UCN <> ""
AND c.PolicyStatus = 'Active'
; QUIT;

PROC SORT DATA= Cancel_Class out=CancelClass;
BY PolicyNumber descending VersionStartDate;
RUN;

PROC SORT DATA= CancelClass  out=Cancellation_BASE dupout=dups nodupkey ;
BY PolicyNumber;
RUN;
*****************************************************************************************************;
/*[RETAIL AGENT SALES STAT]*/
	
/* [ EXTRACTING & CALCULATING AVERAGE DISCOUNTS ] */
%let AssumedDiscountPct= 0.05;

Data RETAG_DISCOUNT1;
	set WH_SS.SS_Sales (where=(ProductType='FNB Insure Retail'));

	ActualAPI=CoverPremium*12;
	OriginalAppliedDiscountPct1 = OriginalAppliedDiscountPct*-1;
	ExpectedAPI = ActualAPI/(1-(OriginalAppliedDiscountPct1/100));

	If OriginalAppliedDiscountPct1 > 5 then
		ExpectedAPI1=ExpectedAPI*(1-&AssumedDiscountPct.);
	else ExpectedAPI1=ExpectedAPI;
	SalesPeriod = year(datepart(SalesDate))*100 + month(datepart(SalesDate));

	If CoverName in ("Sasria -Non Motor","Sasria -Fire Domestic","Sasria - Motor", "Water Heating System Wear and Tear Cover") then
		delete;

	If ParentLOBINB=1 and PointOfSale in ("ABNA","Endorsement","New policy") then
		output;
run;

proc sql;
	create table RETAG_DISCOUNT_BSE as 
		select *
			,ActualAPI as TotalActualAPIexclVAT
			,ExpectedAPI1 as TotalExpectedAPIexclVAT
			,ExpectedAPI as TotalActAPIexclVATND
			,TotalActualAPIexclVAT/TotalActAPIexclVATND as PSR
			,round((1-calculated PSR)*100,0.01) as AverageDiscountPct 

		from RETAG_DISCOUNT1 

	;
quit;

proc sql;
update RETAG_DISCOUNT_BSE
set AverageDiscountPct=0
where AverageDiscountPct=.
;quit;

/* [ EXTRACT & SUMMARISE RETAIL AGENT SALES BASE] */ 

DATA WORK.RETAG_SS_SALES;
	SET WH_SS.SS_SALES;
	WHERE ProductType = 'FNB Insure Retail'
		AND ParentLOB not contains 'Sasria' and salesind=1
/*		AND channel IN ('VIP','STI Internal' , 'Premium Insurance')*/
;
	KEEP PolicyNumber	OriginalAssetID	policy_asset_nr	versionid 
        coverid itemid CoverName	ParentLOBINB	
		ParentLOB	SumInsured	INSURED_ITEM_DESC	IDNumber	UCN	PointOfSale	
		SalesUser	SalesUserName	ProposalDate	SalesDate	CoverStartDate	
		SaleYM	CoverPremium	API	EVENT_TYPE_DSC	SalesInd	Channel;
RUN;

proc sql;
update RETAG_SS_SALES
set ParentLOB='Other'
where ParentLOB in ('Trailer Comprehensive','Pleasure craft Comprehensive','Caravan Comprehensive')
;quit;


**********************************************************************************************************;

/*[Mapping AverageDiscountPct]*/

proc sql;
	create table RETAG_BSE2 as select a.*,b.AverageDiscountPct
		from RETAG_SS_SALES a
			left join RETAG_DISCOUNT_BSE b
				on a.policynumber=b.policynumber and a.versionid=b.versionid and 
                   a.coverid=b.coverid and a.itemid=b.itemid and a.saleym=b.SalesPeriod
				   ;quit;

data RETAG_BSE3;
set RETAG_BSE2;
format PARENTLOB_tst $50.;
if ParentLOB in ('Personal Liability') then PARENTLOB_tst ='T_Personal Liability';else
PARENTLOB_tst = ParentLOB;
run;

/*sorting the base*/
proc sort data=RETAG_BSE3 out=RETAG_BSE4;
by PolicyNumber PARENTLOB_tst
;quit;

/*Creating a table for only first parentlob against each policy*/

data RETAG_BSE5;
set RETAG_BSE4;
by policynumber ;
if first.policynumber;
run;


proc sql;
create table RETAG_BSE6 as select a.*,b.PARENTLOB_tst as PLOB1,b.OriginalAssetID as OASID1 from RETAG_BSE4 a
left join RETAG_BSE5 b
on a.policynumber=b.policynumber;
quit;

data SALES_BASE_final(drop=PLOB1 OASID1) ;
set RETAG_BSE6;
format ParentLOB_1 $50. OriginalAssetID_1 15.;
if ParentLOB in ('Personal Liability') 
then ParentLOB_1 = PLOB1;
else ParentLOB_1 = ParentLOB ;
if ParentLOB in ('Personal Liability') 
then OriginalAssetID_1=OASID1;
else OriginalAssetID_1 = OriginalAssetID
;run;

/*Mapping Cancellation details on sales base*/

proc sql;
create table ttst as select a.*,b.POL_STATUS,b.CANCELLED_BY_DESC,b.REASON_DESC,b.VersionStartDate as Cancellation_date
,year(b.VersionStartDate)*100+month(b.VersionStartDate) as Cancellation_Yearmonth
,intck('month',datepart(a.Salesdate),b.VersionStartDate) as Month_Diff
from SALES_BASE_final a left join Cancellation_BASE b 
on a.policynumber=b.policynumber
;quit;


data ttst_1;
set ttst;
format Canncellation_Flag $8.;
if (Month_Diff) >= 2 then Canncellation_Flag = 'Existing';
else Canncellation_Flag = 'New';
if POL_STATUS = '' then Canncellation_Flag = '';
run; 
/*314 415*/

proc sql;
create table cancellations_NTUs as 
select SaleYM 
        ,SalesUser
        ,SalesUserName
		,count(distinct PolicyNumber) as PolicyCount
		,sum(API) as Total_API
		,count(distinct case when POL_STATUS = 'NTU-CAN' then PolicyNumber end) as NTU_Count
		,sum(case when POL_STATUS = 'NTU-CAN' then API else 0.00 end) as NTU_API
from ttst_1
WHERE SaleYM >= 202401
GROUP BY SaleYM 
        ,SalesUser
        ,SalesUserName
;quit;

/* 3 month average cancellations */

proc sort data=cancellations_NTUs;
    by SalesUser SaleYM; /* Assuming you have a date variable */
run;

proc expand data=cancellations_NTUs out=API3month_rolling_avg;
    by SalesUser;
    id SaleYM;
    convert Total_API=TotalAPI_rolling_sum / transformout=(movsum 3);
    convert NTU_API=NTU_API_rolling_sum / transformout=(movsum 3);
    convert POlicyCount=Total_pol_rolling_sum / transformout=(movsum 3);
    convert NTU_Count=NTU_count_rolling_sum / transformout=(movsum 3);
run;

data apicancellationstatspre;
   set API3month_rolling_avg;
   if abs(NTU_API_rolling_sum) < 1 then NTU_API_rolling_sum = 0;
   if abs(NTU_Count_rolling_sum) < 1 then NTU_API_rolling_sum = 0;
   API_Perc_Cancelled = NTU_API_rolling_sum / TotalAPI_rolling_sum;
   Policy_perc_cancelled = NTU_count_rolling_sum/Total_pol_rolling_sum;
run;

data apicancellationstats;
   set apicancellationstatspre;
   if abs(Policy_perc_cancelled) < 0.00001 then Policy_perc_cancelled = 0;
run;

/**********************************************************************************************************************/
/* Combined monitoring Table*/

/*1. Aggregate the detail tables*/

/*API, Policies and Items*/

proc sql;
create table sales_stats as 
select SaleYM
		,upcase(SalesUser) as SalesUser	
		,SalesUserName
		,SalesUserClassification
		,count(distinct PolicyNumber) as PolicyCount
		,sum(ItemCount) as ItemCount
		,sum(API) as API
from salesummary
GROUP by SaleYM
		,SalesUser	
		,SalesUserName
		,SalesUserClassification
;quit;

/*Quotes*/

proc sql;
create table quotes_stats as 
select SaleYM
		,upcase(SalesUser) as SalesUser
		,SalesUserName
		,count(distinct PolicyNumber) as QuoteCount
from quotes
GROUP BY SaleYM 
        ,SalesUser
        ,SalesUserName
;quit;

/*Cancellations*/

proc sql;
create table cancellation_stats as 
select SaleYM 
        ,upcase(SalesUser) as SalesUser
        ,SalesUserName
		,sum(NTU_Count) as NTU_policy_count
		,sum(NTU_API) as NTU_API
from cancellations_NTUs
GROUP BY SaleYM 
        ,SalesUser
        ,SalesUserName
;quit;
proc sql;
create table apicancellationstats as 
select cs.SaleYM
		,upcase(cs.SalesUser) as SalesUser	
		,cs.SalesUserName
		,cs.NTU_API_rolling_sum
		,cs.TotalAPI_rolling_sum
		,cs.API_Perc_Cancelled
		,cs.Total_pol_rolling_sum
		,cs.NTU_count_rolling_sum
		,cs.Policy_perc_cancelled
from apicancellationstats as cs
GROUP BY SaleYM 
        ,SalesUser
        ,SalesUserName
;quit;


/*2. Join the aggregated tables*/

proc sql;
create table agent_stats_hist as 
select s.SaleYM
		,s.SalesUser	
		,s.SalesUserName
		,s.SalesUserClassification
		,s.PolicyCount
		,s.ItemCount
		,s.API
		,q.QuoteCount
		,c.NTU_policy_count
		,c.NTU_API
		,cs.NTU_API_rolling_sum
		,cs.TotalAPI_rolling_sum
		,cs.API_Perc_Cancelled
		,cs.Total_pol_rolling_sum
		,cs.NTU_count_rolling_sum
		,cs.Policy_perc_cancelled
		,"&CurrentDateTime." as LoadDateTime
from sales_stats as s
	left join quotes_stats q 
		on s.SaleYM = q.SaleYM
			and s.SalesUser	= q.SalesUser
			and s.SalesUserName = q.SalesUserName
	left join cancellation_stats c 
		on s.SaleYM = c.SaleYM
			and s.SalesUser = c.SalesUser	
			and s.SalesUserName = c.SalesUserName
	left join apicancellationstats cs
		on s.SaleYM = cs.SaleYM
			and s.SalesUser = cs.SalesUser	
			and s.SalesUserName = cs.SalesUserName
	
;quit;

/**********************************************************************************************************************/
/* Combined monitoring Table Daily tool*/

/*1. Aggregate the detail tables*/

/*API, Policies and Items*/

proc sql;
create table sales_stats_daily as 
select SalesDate
		,SaleYM
		,SalesUser	
		,SalesUserName
		,SalesUserClassification 
		,count(distinct PolicyNumber) as PolicyCount
		,sum(ItemCount) as ItemCount
		,sum(API) as API
from salesummary
GROUP by SalesDate
		,SaleYM
		,SalesUser	
		,SalesUserName
		,SalesUserClassification
ORDER BY 1 DESC
;quit;

/*Quotes*/

proc sql;
create table quotes_stats_daily as 
select datepart(StatusStartTime) format date9. as StatusDate
		,SaleYM
		,Upcase(SalesUser) as SalesUser
		,SalesUserName
		,count(distinct PolicyNumber) as QuoteCount
from quotes
GROUP BY datepart(StatusStartTime)
		,SaleYM 
        ,SalesUser
        ,SalesUserName
ORDER BY 1 desc
;quit;

/*Cancellations*/

proc sql;
create table dailyNTUs as 
select Cancellation_date
		,SaleYM 
        ,SalesUser
        ,SalesUserName
		,count(distinct case when POL_STATUS = 'NTU-CAN' then PolicyNumber end) as NTU_Count
		,sum(case when POL_STATUS = 'NTU-CAN' then API else 0.00 end) as NTU_API
from ttst_1
WHERE SaleYM > 202401
		and POL_STATUS = 'NTU-CAN'
GROUP BY Cancellation_date
		,SaleYM 
        ,SalesUser
        ,SalesUserName
;quit;

proc sql;
create table dailyNTUs_hist as 
select Cancellation_date
		,SaleYM 
        ,SalesUser
        ,SalesUserName
		,PolicyNumber
		,count(distinct case when POL_STATUS = 'NTU-CAN' then PolicyNumber end) as NTU_Count
		,sum(case when POL_STATUS = 'NTU-CAN' then API else 0.00 end) as NTU_API
from ttst_1
WHERE SaleYM > 202401
		and POL_STATUS = 'NTU-CAN'
GROUP BY Cancellation_date
		,SaleYM 
        ,SalesUser
        ,SalesUserName
		,PolicyNumber
;quit;

/*2. Join the aggregated tables*/

data MonthDays;
input DateYM 6. Total_days 3. Business_days 3. Week_days 3.;
cards;
202501 31 22 23
202502 28 20 20
202503 31 20 21
202504 30 19 22
202505 31 21 22
202506 30 20 21
202507 31 23 23
202508 31 21 21
202509 30 21 22
202510 31 23 23
202511 30 20 20
202512 31 20 23
202601 31 21 22
202602 28 20 20
202603 31 21 22
202604 30 20 22
202605 31 21 21
202606 30 21 21
202607 31 23 23
202608 31 21 21
202609 30 21 22
202610 31 23 23
202611 30 20 21
202612 31 21 23
;
run;

data date_table;
    format date date9.;
    do date = "&start_date"d to "&formatted_date"d;
        /* Unique Key for the date */
        key + 1; 
        output;
    end;
run;

proc sql;
create table agent_stats_daily_hist as 
select d.Date
		,s.SaleYM
		,s.SalesUser	
		,s.SalesUserName
		,s.SalesUserClassification
		,s.PolicyCount
		,s.ItemCount
		,s.API
		,q.QuoteCount
		,c.NTU_count
		,c.NTU_API
		,cs.NTU_API_rolling_sum
		,cs.TotalAPI_rolling_sum
		,cs.API_Perc_Cancelled
		,cs.Total_pol_rolling_sum
		,cs.NTU_count_rolling_sum
		,cs.Policy_perc_cancelled
		,md.Total_days
		,md.Week_days
		,md.Business_days
		,"&CurrentDateTime." as LoadDateTime
from date_table d 
left join sales_stats_daily as s
	on d.date = s.SalesDate
	left join quotes_stats_daily q 
		on d.date = q.StatusDate
			and s.SaleYM = q.SaleYM
			and s.SalesUser	= q.SalesUser
			and s.SalesUserName = q.SalesUserName
	left join dailyNTUs c 
		on d.date = c.Cancellation_date
			and s.SaleYM = c.SaleYM
			and s.SalesUser = c.SalesUser	
			and s.SalesUserName = c.SalesUserName
	left join apicancellationstats cs
		on s.SaleYM = cs.SaleYM
			and s.SalesUser = cs.SalesUser	
			and s.SalesUserName = cs.SalesUserName /* 15 762*/
	left join MonthDays md 
		on md.DateYM = s.SaleYM
ORDER BY Date desc
;quit;

/*Agent Progress*/
proc sql;
create table salesdays as 
Select SaleYM 
		,SalesUser
		,SalesUserName
		,avg(Business_days) as Business_days
		,count(*) as DateCount
		,sum(case when weekday(Date) not in (1,7) then 1 end ) as WeekdayCount
		,sum(PolicyCount) as PolicyCount
		,sum(ItemCount) as ItemCount
		,sum(QuoteCount) as QuoteCount
		,sum(API) as API
		,sum(case when weekday(Date) not in (1,7) then API end ) as WeekdayAPI
FROM agent_stats_daily_hist
WHERE SalesUserClassification = 'Sales Agent'
GROUP BY SaleYM 
		,SalesUser
		,SalesUserName
ORDER BY SaleYM desc
;quit;

proc sql;
    select max(Date) into :max_date
    from agent_stats_daily_hist;
quit;

/* Define South African public holidays for 2025 */
data holidays;
    format holiday date9.;
    input holiday :date9.;
    datalines;
01JAN2025 /* New Year's Day */
21MAR2025 /* Human Rights Day */
18APR2025 /* Good Friday */
21APR2025 /* Family Day */
27APR2025 /* Freedom Day */
28APR2025 /* Freedom Day Holiday */
01MAY2025 /* Workers' Day */
16JUN2025 /* Youth Day */
24SEP2025 /* Heritage Day */
16DEC2025 /* Day of Reconciliation */
25DEC2025 /* Christmas Day */
26DEC2025 /* Day of Goodwill */
01JAN2026 /* New Year's Day */
21MAR2026 /* Human Rights Day */
03APR2026 /* Good Friday */
06APR2026 /* Family Day */
27APR2026 /* Freedom Day */
01MAY2026 /* Workers' Day */
16JUN2026 /* Youth Day */
10AUG2026 /* National Women's Day (observed) */
24SEP2026 /* Heritage Day */
16DEC2026 /* Day of Reconciliation */
25DEC2026 /* Christmas Day */
26DEC2026 /* Day of Goodwill */
;
run;

/* Create a dataset with all dates from max_date to the last day of the month */
data all_dates;
    format date date9.;
    do date = &max_date to intnx('month', &max_date, 0, 'end');
        output;
    end;
run;

/* Merge all_dates with holidays to flag holidays */
proc sql;
    create table all_dates_with_holidays as
    select a.date, 
           case when b.holiday is not null then 1 else 0 end as holiday_flag
    from all_dates as a
    left join holidays as b
    on a.date = b.holiday;
quit;

/* Calculate business days left excluding weekends and holidays */
data _null_;
    set all_dates_with_holidays end=last;
    retain business_days_left 0;
    if weekday(date) not in (1, 7) and holiday_flag = 0 then business_days_left + 1;
    if last then call symputx('business_days_left', business_days_left);
run;
/**/
/*proc sql;*/
/*    select max(Date) into :max_date*/
/*    from agent_stats_daily_hist;*/
/*quit;*/
/**/
/*data _null_;*/
/*    last_day_of_month = intnx('month', &max_date, 0, 'end');*/
/*    business_days_left = 0;*/
/*    */
/*    do date = &max_date to last_day_of_month;*/
/*        if weekday(date) not in (1, 7) then business_days_left + 1;*/
/*    end;*/
/*    */
/*    call symputx('business_days_left', business_days_left);*/
/*run;*/

data agent_obr_stats;
set salesdays;
ppd = round(PolicyCount/DateCount,0.1);
rpp = round(ItemCount/PolicyCount,0.1);
rpd = round(ItemCount/DateCount,0.1);
qpd = round(QuoteCount/DateCount,0.1);
daily_api = round(WeekdayAPI/WeekdayCount,0.1);
daily_api_act = round(api/DateCount,0.1);

business_days_left = &business_days_left;

projected_api = (daily_api* &business_days_left+API);
projected_policies = PolicyCount + (ppd * &business_days_left);
projected_risks = (rpd * &business_days_left + ItemCount);
projected_quotes = (qpd* &business_days_left + QuoteCount);

projected_rpp = round((projected_risks/projected_policies),0.1);
projected_rpd = round(projected_risks/business_days,0.1);
projected_qpd = round(projected_quotes/business_days,0.1);
projected_daily_api = round((projected_api)/business_days,0.1);
run;

proc sql;
create table ODPSales as 
select SaleYM 
		,SalesDate
		,PolicyNumber
		,ParentLOB
		,CoverName
		,'ODP' as Product
		,CoverPremium
		,API
from WH_SS.SS_SALES
Where Covername = 'Outstanding Debt Protection'
		and CoverPremium > 0 
		and salesind = 1
		and saleym>202401
;quit;

proc sql;
create table ProductTableFeatures as 
Select PolicyNumber
		,UCN
		,PrimaryStatus	
		,SecondaryStatus
		,SalesChannel
		,ZipCdeProvince
		,HyperSegment
		,SubSegment
		,Segment
FROM WH_SS.SS_PRODUCT
Where PolicyNumber in (Select distinct PolicyNumber FROM STI_SL.vw_salesummary_hist_long)
;quit;

%macro Loadtable(Table);
%if %sysfunc(exist(&table.)) %then %do;
proc sql;
drop table STI_SL.&Table.;
create table STI_SL.&Table.
as select * from &Table.;
quit;
%end;
%mend;


/* Calling the macro function */
%Loadtable(agent_stats_hist);
%Loadtable(agent_stats_daily_hist);
%Loadtable(salesummary_hist);
%Loadtable(quotetable_hist);
%Loadtable(quotetable_hist_summary);
%Loadtable(dailyNTUs_hist);
%Loadtable(agent_obr_stats);
%Loadtable(salesummary_hist_long);
%Loadtable(ODPSales);
%Loadtable(ProductTableFeatures);

proc sql;
create table SalesTeams as 
Select Fnumber
		,substr(Fnumber, 2) as EmployeeNumber
		,NameSurname
		,Team
		,datepart(StartDate) as StartDate format=date9.
		,datepart(EndDate) as EndDate format=date9. 
FROM STI_SL.SalesTeamStructure
Where Team in ('Inbound and switch', 'Elite','Instruct')
;quit;


PROC SQL ;
CREATE TABLE InboundCalls AS
SELECT Agent
		,Fullname
		,CallDate
		,count(distinct CallID) as CallCount
		,"&CurrentDateTime." as LoadDateTime
FROM STI_COM.CALL_RECORDS
Where Agent in (Select distinct EmployeeNumber FROM SalesTeams)
GROUP BY Agent
		,Fullname
		,CallDate
;QUIT;


%Loadtable(InboundCalls);


/*proc printto log="/data/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Logs/BGA/SQL_Sales_Log.log" new;*/
/*run;*/
