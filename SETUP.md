%include "/data/fnbinsurance/Growth_Analytics/SASCODE/ACTIVE/BLP/GENERAL/SVC_Libnames.sas";
%put &svc_pwd.;
 
options obs=max; /*get max nobs*/
options validvarname=any; /*upcase all field headings*/
options varlenchk=nowarn;

proc printto log="/data/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Logs/BGA/DCR.log" new;
run;


/*impport LOB data*/
OPTIONS VALIDVARNAME=V7;

PROC IMPORT OUT= WORK.ClaimClassification

DATAFILE= "/data/fnbinsurance/Pricing/Short_Term/ClaimClassification.xlsx"

DBMS=xlsx

REPLACE;

GETNAMES=YES;

RUN;

OPTIONS VALIDVARNAME=V7;

PROC IMPORT OUT= WORK.ClaimLOB202203

DATAFILE= "/data/fnbinsurance/Pricing/Short_Term/ClaimLOB202203.xlsx"

DBMS=xlsx

REPLACE;

GETNAMES=YES;

RUN;










/****************************************************************************************************;*/
/*UCN code*/

libname data '/data/fnbinsurance/Pricing/Short_Term/Claims Ops reports';
%include '/data/fnbinsurance/Warehouse/00 Metadata/SAS Enhanced Libnames.sas';
Libname dims "/data/fnbinsurance/Growth_Analytics/SHARE/DIMENSIONS";
libname LU_SAVE "/data/fnbinsurance/Acquisitions_CVM/Leads Universe";

/*Data Warehouse*/
%include'/data/fnbinsurance/Warehouse/00 Metadata/SAS Enhanced Libnames.sas';
%include'/data/fnbinsurance/Warehouse/00 Metadata/SAS Raw Data Libnames.sas';

%include "/data/fnbinsurance/Growth_Analytics/SASCODE/ACTIVE/BLP/GENERAL/SVC_Libnames.sas";
%put &svc_pwd.;

/*Loc Claims*/
libname Claims '/data/fnbinsurance/Collections/Ops/Excel';


/*Loc Calls from Communix*/
libname communix '/data/fnbinsurance/Users/Neo/Data Sources/communixx';

/*****************************************************************************************************/
/*VIP and IP claims;*/



/*remember to add the extra run for the marco at the begining of every month until we fixed it*/

/*remember to add the extra run for the marco at the begining of every month until we fixed it*/

%include '/data/fnbinsurance/Warehouse/00 Metadata/SAS Enhanced Libnames.sas';
Libname dims "/data/fnbinsurance/Growth_Analytics/SHARE/DIMENSIONS";
libname LU_SAVE "/data/fnbinsurance/Acquisitions_CVM/Leads Universe";


/*Data Warehouse*/
%include'/data/fnbinsurance/Warehouse/00 Metadata/SAS Raw Data Libnames.sas';

/*Loc Claims*/
libname Claims '/data/fnbinsurance/Collections/Ops/Excel';

/*Loc Calls from Communix*/
libname communix '/data/fnbinsurance/Users/Neo/Data Sources/communixx';
******************************************************************************************************/
/*Gauteng CAT claims*/;
proc sql;
create table cat_gp as 
select *
	,year(datepart(Dateofloss))*10000 + month(datepart(Dateofloss))*100 + day(datepart(Dateofloss)) as dt
from wh_ss.ss_Newclaim
where calculated dt = 20231113
	and PerilSubClaim in ('Storm' ,'Flood','Wind','Lightning','Lightning or Thunderbolts','Storm, wind, water, hail or snow','Earthquake & Mining Tremors','Windscreen Repair','Windscreen Replacement',
	'Hail','Nature (earthquake, storm, flood, freezing, snow,Wind)','Acts of Nature','Glass Other')
	or ClaimTypeDescription in ('SOS','Hail','Storm','Impact vehicles or animals or falling trees') and calculated dt = 20231113
group by ClaimCode
having LatestRowRank = min(LatestRowRank)

;quit;

proc sql;
create table cat_gp2 as 
select a.ProductType		
	,a.EntityNum	
	,a.PolicyNumber	
	,a.PolicyID	
	,a.VersionID	
	,a.CoverID	
	,a.ItemID	
	,a.ClaimCode	
	,a.SubClaimCode	
	,a.ContractID	
	,a.PolicyStatus	
	,a.CancelledDate	
	,a.CancelledBy	
	,a.ClaimDescription	
	,a.ClaimTypeDescription	
	,a.PerilSubClaim	
	,a.DamageStatusDescription	
	,a.ClaimStatus	
	,a.status_desc	
	,a.status_update_date	
	,a.InsuredItemDescription	
	,a.SumInsured	
	,a.LOB	
	,a.ParentLOB	
	,a.ClaimHandler	
	,a.ContractInceptionDate	
	,a.DateOfLoss	
	,a.ReportedDate	
	,a.ClaimRegisterationDate	
	,a.ClaimSettlementDate	
	,a.ClaimDeclinedDate	
	,a.DeclinedReason	
	,a.LastClaimUpdatedDate	
	,a.Period	
	,a.SalesChannel	
	,a.SalesChannelType	
	,a.LatestRowRank	
	,a.ReserveReason	
	,a.Remarks1	
	,a.Remarks2	
	,a.ReserveDate	
	,a.ReserveType	
	,a.ClaimTransactionID	
	,a.ReserveID	
	,a.Excess	
	,a.NewEstimate	
	,a.ChangeEstimate
from cat_gp a
left join WH_SS.SS_NEW_RATING_FACTOR b
on a.policynumber=b.policynumber and a.versionId = b.policyversion and a.itemID=b.ItemId and a.coverID = b.coverId
where upper(b.INSURED_ITEM_DESC) contains 'GAUTENG' or ParentLOB contains 'Motor Comprehensive' and ReserveType in ("Payment", "")
;quit;
/******************************************************************************************************/
/*GP hail claims- claim cost*/
proc sql;
	CONNECT TO ODBC (DSN='RBIDTPRDSS1_SMARTSTORE' USER="fnbjnb01\&svc_User" PASSWORD="&svc_Pwd");
	Create Table  AddressSQL as 
	Select *
	FROM CONNECTION TO ODBC
 		(select ID
				,STREET_NAME
				,HOUSE_NR
				,APPARTMENT_NR
				,BUILDING_NAME
				,CITY_NAME
				,COUNTY_NAME
				,PROVINCE_NAME
				,ZIP
		from [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[CN_ADDRESS] 
		)
;quit;

proc sql;
	CONNECT TO ODBC (DSN='RBIDTPRDSS1_SMARTSTORE' USER="fnbjnb01\&svc_User" PASSWORD="&svc_Pwd");
	Create Table  HOCAddressSQL as 
	Select *
	FROM CONNECTION TO ODBC
 		(select cov.ID 
			,pal.ADDRESS_ID	
			,ppla.ID			as ASSET_ID
			,ppla.LOB_ASSET_ID
			,ppla.ORIGINAL_LOB_ASSET_ID
			,cd.ID ID_cd
			,cd.STREET_NAME
			,cd.HOUSE_NR
			,cd.APPARTMENT_NR
			,cd.BUILDING_NAME
			,cd.CITY_NAME as HOCCITY_NAME
			,cd.COUNTY_NAME as HOCCOUNTY_NAME
			,cd.PROVINCE_NAME as HOCPROVINCE_NAME
			,cd.ZIP as HOCZip
		from [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[P_COVER] cov
		left join [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[P_POLICY_LOB_ASSET] ppla 
	       	on ppla.ID = cov.ASSET_ID
		left join [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[P_Policy_Lob_To_Lob_Asset] ppltla
			on ppla.id=ppltla.LOB_ASSET_ID
		left join [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[p_asset_location] pal 
			on pal.id=ppltla.LOCATION_ID
		left join [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[CN_ADDRESS] cd 
			on pal.ADDRESS_ID=cd.id
		left join [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[AS_ASSET] ass 
			on ass.id=ppla.LOB_ASSET_ID
		)
		order by ID 
;quit;

proc sort data=HOCAddressSQL nodupkey out=HOCAddressSQL2;
by ID ;
run;

proc sort data=wh_ss.ss_newclaim out=newclaim2;
by ClaimCOde SubClaimCode LatestRowRank CLAIM_TRANSACTION_ID ReserveType;
run;
proc sort data=newclaim2 nodupkey out=newclaim;
by ClaimCOde SubClaimCode LatestRowRank CLAIM_TRANSACTION_ID ReserveType;
run;

proc sql ;
    create table ClaimsWithProvence as
    select a.*
        ,d.ZipCdeProvince    
        ,d.ZipCdeProvinceRegion
        ,nightAddress.CITY_NAME as MotorCITY_NAME
        ,nightAddress.COUNTY_NAME as MotorCOUNTY_NAME
        ,nightAddress.PROVINCE_NAME as MotorPROVINCE_NAME
        ,nightAddress.ZIP as MotorZIP
        ,c.HOCCITY_NAME
        ,c.HOCCOUNTY_NAME
        ,c.HOCPROVINCE_NAME
        ,c.HOCZip
        ,datepart(DateOfLoss) as LossDate formate date9.
        ,case when b.Parent_LOB in ( "Home Owner's", "Home Contents", "Business CashFlow Cover") then c.HOCPROVINCE_NAME
	        when b.Parent_LOB in ("Motor") then nightAddress.PROVINCE_NAME
	        else d.ZipCdeProvince
	        end as AllProvince
        ,case when b.Parent_LOB in ( "Home Owner's", "Home Contents","Business CashFlow Cover") then c.HOCCOUNTY_NAME
	        when b.Parent_LOB in ("Motor") then nightAddress.COUNTY_NAME
	        else d.ZipCdeProvinceRegion
	        end as AllCOUNTY_NAME
        ,datepart(ApprovalDate) as PaymentApprovalDate formate date9.
		,case when datepart(DateOfLoss)='13Nov2023'd  and calculated AllProvince='Gauteng' then 'Hail' 
			when datepart(DateOfLoss)='13Nov2023'd  and calculated AllCOUNTY_NAME in ('Johannesburg','Midrand','Centurion','Sunninghill Ext 66','Crowthorne Ext 20
			','Randburg','Soshanguve','Lenasia Ext 11','Vosloorus','Sandton','Alberton','Edenvale','Rustenburg','Johannesburg South
			','Roodepoort','Benoni','Pretoria','Krugersdorp','Kempton Park','Kyalami Hills Ext 20','Soweto','Randfontein')then 'Hail' 
			when datepart(DateOfLoss)='13Nov2023'd  and ParentLOB='Motor Comprehensive' then 'Hail' 
			else 'Other' end as HailInd
    from newclaim as a
    left join wh_ss.ss_cover as b
    on a.policyID=b.policyID and a.versionID=b.Policyversion and a.coverID=b.coverID
    left join wh_ss.ss_product as d 
    on a.policyNUmber=d.policynumber
    left join AddressSQL as nightAddress
    on b.NIGHT_LOCATN_ID=nightAddress.ID
    left join HOCAddressSQL2 as c 
    on b.coverID=c.ID
    where Parent_LOB<>'Sasria' and Parent_LOB<>'Personal Liability'
;quit;

proc sql;
    create table GPHailStorms as
    select parentLOB
        ,LOB
        ,sum(case when ReserveType<> 'Recovery' and LatestRowRank=1 then 1 else 0 end) as Count
        ,sum(case when ReserveType<> 'Recovery' and LatestRowRank=1 then NewEstimate else 0 end) as OCR
  	   	,-sum(case when ReserveType='Recovery' and LatestRowRank=1 then NewEstimate else 0 end) as OCR_Salvage
        ,-sum(case when CLAIM_TRANSACTION_ID<>. and ReserveType<> 'Recovery' and PaymentSuccess='Approved' then ChangeEstimate else 0 end) as PaymentAmount
        ,sum(case when CLAIM_TRANSACTION_ID<>. and ReserveType= 'Recovery' and PaymentSuccess='Approved' then ChangeEstimate else 0 end) as SalvageRecieved
		,calculated OCR + calculated PaymentAmount + calculated OCR_Salvage +
		calculated SalvageRecieved as TotalIncurredIncVAT format 15.2
		,calculated TotalIncurredIncVAT/1.15 as TotalIncurredExcVAT format 15.2
		,case when ParentLOB contains 'Motor' then 0.2
			else 0.5 end as QS_treaty format 2.1
		,calculated TotalIncurredExcVAT * calculated QS_treaty As Net_ReinsExcVAT format 15.2
	from ClaimsWithProvence
    where  HailInd='Hail'
   	 	and (PerilSubClaim in ('Storm' ,'Flood','Wind','Lightning','Lightning or Thunderbolts
		','Storm, wind, water, hail or snow','Earthquake & Mining Tremors','Windscreen Repair','Windscreen Replacement',
		'Hail','Nature (earthquake, storm, flood, freezing, snow,Wind)','Acts of Nature','Glass Other')
		or ClaimTypeDescription in ('SOS','Hail','Storm','Impact vehicles or animals or falling trees'))
		and ParentLOB<>''
    group by  parentLOB, LOB
;quit;
proc sql;
    create table GPHailStormsTotal as
    select 'Total' as parentLOB	
		,''as LOB	
		,sum(Count) as Count
		,sum(OCR) as 	OCR
		,sum(OCR_Salvage) as 	OCR_Salvage
		,sum(PaymentAmount) as PaymentAmount
		,sum(SalvageRecieved) as SalvageRecieved
		,sum(TotalIncurredIncVAT) as TotalIncurredIncVAT	
		,sum(TotalIncurredExcVAT) as TotalIncurredExcVAT
		,. as QS_treaty
		,sum(Net_ReinsExcVAT) as Net_ReinsExcVAT
	from GPHailStorms
;quit;

data GPHailStormsAll;
set GPHailStorms GPHailStormsTotal;
drop QS_treaty;
run;
proc sql;
    create table GPHailStormsDamagecode as
    select parentLOB
       	,PerilSubClaim
       	,sum(case when ReserveType<> 'Recovery' and LatestRowRank=1 then 1 else 0 end) as Count
        ,sum(case when ReserveType<> 'Recovery' and LatestRowRank=1 then NewEstimate else 0 end) as OCR
  	   	,-sum(case when ReserveType='Recovery' and LatestRowRank=1 then NewEstimate else 0 end) as OCR_Salvage
        ,-sum(case when CLAIM_TRANSACTION_ID<>. and ReserveType<> 'Recovery' and PaymentSuccess='Approved' then ChangeEstimate else 0 end) as PaymentAmount
        ,sum(case when CLAIM_TRANSACTION_ID<>. and ReserveType= 'Recovery' and PaymentSuccess='Approved' then ChangeEstimate else 0 end) as SalvageRecieved
		,calculated OCR + calculated PaymentAmount + calculated OCR_Salvage +
		calculated SalvageRecieved as TotalIncurredIncVAT format 15.2
		,calculated TotalIncurredIncVAT/1.15 as TotalIncurredExcVAT format 15.2
		,case when ParentLOB contains 'Motor' then 0.2
			else 0.5 end as QS_treaty format 2.1
		,calculated TotalIncurredExcVAT * calculated QS_treaty As Net_ReinsExcVAT format 15.2
	from ClaimsWithProvence
    where  HailInd='Hail'
	    and (PerilSubClaim in ('Storm' ,'Flood','Wind','Lightning','Lightning or Thunderbolts
		','Storm, wind, water, hail or snow','Earthquake & Mining Tremors','Windscreen Repair','Windscreen Replacement',
		'Hail','Nature (earthquake, storm, flood, freezing, snow,Wind)','Acts of Nature','Glass Other')
		or ClaimTypeDescription in ('SOS','Hail','Storm','Impact vehicles or animals or falling trees'))
		 and ParentLOB<>''
	group by  parentLOB, PerilSubClaim
;quit;

proc sql;
    create table GPHailStormsClaimTypeDesc as
    select parentLOB
        ,ClaimTypeDescription 
        ,sum(case when ReserveType<> 'Recovery' and LatestRowRank=1 then 1 else 0 end) as Count
        ,sum(case when ReserveType<> 'Recovery' and LatestRowRank=1 then NewEstimate else 0 end) as OCR
  	   	,-sum(case when ReserveType='Recovery' and LatestRowRank=1 then NewEstimate else 0 end) as OCR_Salvage
        ,-sum(case when CLAIM_TRANSACTION_ID<>. and ReserveType<> 'Recovery' and PaymentSuccess='Approved' then ChangeEstimate else 0 end) as PaymentAmount
        ,sum(case when CLAIM_TRANSACTION_ID<>. and ReserveType= 'Recovery' and PaymentSuccess='Approved' then ChangeEstimate else 0 end) as SalvageRecieved
		,calculated OCR + calculated PaymentAmount + calculated OCR_Salvage +
		calculated SalvageRecieved as TotalIncurredIncVAT format 15.2
		,calculated TotalIncurredIncVAT/1.15 as TotalIncurredExcVAT format 15.2
		,case when ParentLOB contains 'Motor' then 0.2
			else 0.5 end as QS_treaty format 2.1
		,calculated TotalIncurredExcVAT * calculated QS_treaty As Net_ReinsExcVAT format 15.2
 	from ClaimsWithProvence
    where  HailInd='Hail'
    and (PerilSubClaim in ('Storm' ,'Flood','Wind','Lightning','Lightning or Thunderbolts
','Storm, wind, water, hail or snow','Earthquake & Mining Tremors','Windscreen Repair','Windscreen Replacement',
'Hail','Nature (earthquake, storm, flood, freezing, snow,Wind)','Acts of Nature','Glass Other')
or ClaimTypeDescription in ('SOS','Hail','Storm','Impact vehicles or animals or falling trees'))
and ParentLOB<>''
    group by  parentLOB, ClaimTypeDescription
;quit;
data GPHailStormsClaimTypeDesc2;
set GPHailStormsClaimTypeDesc;
drop QS_treaty;
run;
/*****************************************************************************************************/
/*Western Cape Storm*/ 
proc sql;
create table StormClaims as
select p.UCN as UCN
		,c.PolicyNumber
		,c.ClaimCode
		,c.SubClaimCode 
		,c.ClaimDescription
		,c.ClaimTypeDescription
		,c.PerilSubClaim
		,c.status_desc	
		,c.status_update_date
		,c.InsuredItemDescription
		,c.SumInsured	
		,c.LOB	
		,c.ParentLOB
		,c.ClaimHandler
		,c.DateOfLoss	
		,c.ReportedDate	
		,c.ClaimRegisterationDate
		,c.NewEstimate
		,c.BeneficiaryType	
		,c.BeneficiaryName
		,c.CLAIM_TRANSACTION_ID
		,c.PaymentIncludeVAT
from wh_ss.ss_newclaim c
	left join WH_SS.SS_POLICY p 
		on c.PolicyNumber = p.PolicyNumber
		and c.ContractID = p.ContractID
		and c.VersionID = p.VersionID
where (datepart(DateOfLoss)='06Apr2024'd 
		or datepart(DateOfLoss)>='07Apr2024'd)
/*		datepart(DateOfLoss)>='13Jun2023'd */
/*and datepart(DateOfLoss)<='20Jun2023'd**/
and PerilSubClaim in ('Storm' ,'Flood','Wind','Lightning')
and InsuredItemDescription contains 'Western Cape'
and latestRowRank=1
;quit;

/*****************************************************************************************************/
/* OCR fixes*/ 

proc sql ;
create table quickmotor as 
Select ClaimCode
		,SubClaimCode
		,PolicyNumber
		,DateOfLoss
		,ReportedDate
		,intnx('Month',datepart(DateOfLoss),0,'E') format = date9. as LossMonth
		,SumInsured
		,ParentLOB
		,ClaimTypeDescription
		,ClaimDescription
		,PerilSubClaim
		,ClaimTransactionID 
		,PaymentSuccess
		,LatestRowRank
		,ChangeEstimate as ChangeEstimate
		,case when ChangeEstimate = SumInsured then 1 else 0 end as Error_Flag
		,NewEstimate
		,ClaimStatus
		,ReserveType
FROM WH_SS.SS_NEWCLAIM
/*WHERE ParentLOB in ('Motor Comprehensive'*/
/*					,'Motor Third Party Only'*/
/*					,'Motor Third party, Fire & Theft'*/
/*					,'Motor Vaps'*/
/*					)*/
/*		and datepart(DateOfLoss) >= '01APR2023'd*/
ORDER BY DateOfLoss desc 
		,ClaimCode
		,SubClaimCode
		,LatestRowRank
;quit;

proc sql; 
create table OCR_Checks as 
Select datepart(DateOfLoss) as DateOfLoss format date9.
		,datepart(ReportedDate) as ReportedDate format date9.
		,PolicyNumber
		,ParentLOB
		,ClaimCode
		,SubClaimCode
/*		,ClaimDescription*/
		,ClaimTypeDescription
		,PerilSubClaim
		,ClaimStatus
		,SumInsured
		,NewEstimate
FROM quickmotor
Where LatestRowRank = 1
		and Error_Flag = 1
		and ClaimTypeDescription <> 'Theft'
ORDER BY ReportedDate desc, NewEstimate DESC 
;quit;
/****************************************************************
KZN Floods 202306
****************************************************************/
proc sql;
create table StormClaims_KZN as
select p.UCN as UCN
		,c.PolicyNumber
		,c.ClaimCode
		,c.SubClaimCode 
		,c.ClaimDescription
		,c.ClaimTypeDescription
		,c.PerilSubClaim
		,c.status_desc	
		,c.status_update_date
		,c.InsuredItemDescription
		,c.SumInsured	
		,c.LOB	
		,c.ParentLOB
		,c.ClaimHandler
		,c.DateOfLoss	
		,c.ReportedDate	
		,c.ClaimRegisterationDate
		,c.NewEstimate
		,c.BeneficiaryType	
		,c.BeneficiaryName
		,c.CLAIM_TRANSACTION_ID
		,c.PaymentIncludeVAT
from wh_ss.ss_newclaim c
	left join WH_SS.SS_POLICY p 
		on c.PolicyNumber = p.PolicyNumber
		and c.ContractID = p.ContractID
		and c.VersionID = p.VersionID
where datepart(DateOfLoss)>='27Jun2023'd 
and datepart(DateOfLoss)<='30Jun2023'd
and PerilSubClaim in ('Storm' ,'Flood','Wind','Lightning')
and InsuredItemDescription contains 'KwaZulu-Natal'
and latestRowRank=1
;quit;

ODS excel file="/data/fnbinsurance/Short_Term/Claim Report/DailyClaimsReport.xlsx" 
/*OCR_Checks*/
ods excel options(sheet_interval='output'); 
ods exclude all; data _null_;  declare odsout obj(); run; ods select all;
ods excel options(sheet_interval='none' sheet_name='OCR Checks' );
	Proc print data= OCR_Checks;
		title "OCR Checks";
	run;

/*Gauteng CAT claims*/
ods excel options(sheet_interval='output'); 
ods exclude all; data _null_;  declare odsout obj(); run; ods select all;
ods excel options(sheet_interval='none' sheet_name='CAT Claims GP' );
	Proc print data=cat_gp2;
		title 'All GP CAT claims';
	run;
	/*new claim code 11 Dec 2023*/
ods excel options(sheet_interval='output'); 
ods exclude all; data _null_;  declare odsout obj(); run; ods select all;
ods excel options(sheet_interval='none' sheet_name='GP Hail claim cost' );
	title 'Table showing the hail damage by LOB';
	proc print data=GPHailStormsAll;
	run;
	title 'Table showing the hail damage by claim type description';
	proc print data=GPHailStormsClaimTypeDesc2;
	run;
	title '';	

/*CAT*/
ods excel options(sheet_interval='output'); 
ods exclude all; data _null_;  declare odsout obj(); run; ods select all;
ods excel options(sheet_interval='none' sheet_name='CAT Claims' );
	Proc print data=CAT;
		title "All CAT Claims";
	run;

/*excel end code*/
ODS excel close;
run;

/* all motor claim payments*/
%let rd=;

proc sql;
	CONNECT TO ODBC (DSN='RBIDTPRDSS1_SMARTSTORE' USER="fnbjnb01\&svc_User" PASSWORD="&svc_Pwd");
	Create Table  Beneficiary_detail as 
Select *
	FROM CONNECTION TO ODBC
 	(  
		Select a.ID
	        ,a.BENEFICIARY_ID
	        ,a.BENEFICIARY_BANK_ACCOUNT_ID
	        ,b.ENTITY_PAYMENT_PLAN_FNB_NUM
	        ,b.BANK_DESC
	        ,c.BANK_AC_NUM
		FROM [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[C_CLAIM_TRANSACTION] a 
		left join FNB_SMARTSTORE_PROD.[SI_CORE_DWH].[ENTITY_PAYMENT_PLAN_FNB] b 
		    on a.BENEFICIARY_BANK_ACCOUNT_ID = b.ENTITY_PAYMENT_PLAN_FNB_NUM
		left join FNB_SMARTSTORE_PROD.[SI_CORE_DWH].[ENTITY_PAYMENT_PLAN] c 
	    on b.ENTITY_PAYMENT_PLAN_ID = c.ENTITY_PAYMENT_PLAN_ID
	)
;quit;



proc sql;
	create table MotorClaimsPaid&rd as
	select a.PolicyNumber
		,a.ClaimCode
		,a.ClaimTypeDescription
		,a.PerilSubClaim
		,a.DamageStatusDescription	
		,a.ClaimStatus
		,a.LOB	
		,a.ParentLOB
		,a.ClaimHandler
		,datepart(a.DateOfLoss) as DateOfLoss format date9.	
		,datepart(a.ReportedDate ) as ReportedDate format date9.
		,a.Remarks2
		,datepart(ReserveDate) as PaymentDate format date9.
		,a.BeneficiaryType	
		,a.BeneficiaryName	
		,a.BeneficiarySurname
		,b.BANK_DESC as Bank
		,a.PaymentUser
		,a.TypePayment
		,a.PAYMENT_REFERENCE
		,-a.ChangeEstimate as ActualPayment
		,a.PaymentIncludeVAT as 	PaymentIncludeVATandExcess
		,a.PaymentExcludeVAT	
		,a.PaymentVATAmount
		,a.PaymentEstimatedExcess
	from WH_SS.SS_NEWCLAIM&rd as a
	left join Beneficiary_detail b
	on a.ClaimTransactionID = b.ID and a.BeneficiaryID = b.BENEFICIARY_ID
	where a.ParentLOB contains 'Motor'  and BeneficiaryID<>. and a.ReserveType='Payment'
;quit;


PROC EXPORT DATA = MotorClaimsPaid&rd
     OUTFILE = "/data/fnbinsurance/Short_Term/Monitoring/MotorClaimsPaid&rd..xlsx"
     DBMS = xlsx
     REPLACE;
     SHEET="Motor_Claims_Payments";
/*RUN;*/

proc sql;
	create table NonMotorClaimsPaid&rd as
	select a.PolicyNumber
		,a.ClaimCode
		,a.ClaimTypeDescription
		,a.PerilSubClaim
		,a.DamageStatusDescription	
		,a.ClaimStatus
		,a.LOB	
		,a.ParentLOB
		,a.ClaimHandler
		,datepart(a.DateOfLoss) as DateOfLoss format date9.	
		,datepart(a.ReportedDate ) as ReportedDate format date9.
		,a.Remarks2
		,datepart(ReserveDate) as PaymentDate format date9.
		,a.BeneficiaryType	
		,a.BeneficiaryName	
		,a.BeneficiarySurname
		,b.BANK_DESC as Bank
		,a.PaymentUser
		,a.TypePayment
		,a.PAYMENT_REFERENCE
		,-a.ChangeEstimate as ActualPayment
		,a.PaymentIncludeVAT as 	PaymentIncludeVATandExcess
		,a.PaymentExcludeVAT	
		,a.PaymentVATAmount
		,a.PaymentEstimatedExcess
	from WH_SS.SS_NEWCLAIM&rd as a
	left join Beneficiary_detail b
	on a.ClaimTransactionID = b.ID and a.BeneficiaryID = b.BENEFICIARY_ID
	where a.ParentLOB not in ('Motor Comprehensive','Motor cycle Comprehensive'
						 ,'Motor Third Party Only','Caravan Comprehensive'
						 ,'Motor Third party, Fire & Theft','Trailer Comprehensive'
						 ,'Motor Vaps')  
		and BeneficiaryID<>. and a.ReserveType='Payment'
;quit;


PROC EXPORT DATA = NonMotorClaimsPaid&rd
     OUTFILE = "/data/fnbinsurance/Short_Term/Monitoring/NonMotorClaimsPaid&rd..xlsx"
     DBMS = xlsx
     REPLACE;
     SHEET="NonMotor_Claims_Payments";
/*----------------------------------------------------------------------------------------------------------------------------------------------------*/



********************************************************************************************************************/
/*Corporate Actuarial*/
;

PROC EXPORT DATA = claims_TAT
     OUTFILE = "/data/fnbinsurance/Corporate_Actuarial/Short_Term/Dashboards/ClaimsTAT.xlsx" 
     DBMS = xlsx
     REPLACE;
     SHEET="Claims TAT";
RUN;

PROC EXPORT DATA = SLA_table
     OUTFILE = "/data/fnbinsurance/Corporate_Actuarial/Short_Term/Dashboards/ClaimsSLA.xlsx" 
     DBMS = xlsx
     REPLACE;
     SHEET="Claims SLA Table";
RUN;



proc printto;run;



