proc sql;
    CONNECT TO ODBC (DSN='RBIDTPRDSS1_SMARTSTORE' 
                     USER="fnbjnb01\&svc_User" 
                     PASSWORD="&svc_Pwd");

    Create Table <SAS_Table> as
    Select <SAS-level columns/transformations>
    FROM CONNECTION TO ODBC (
        /* Raw T-SQL query sent directly to SQL Server */
        SELECT ...
        FROM [FNB_SMARTSTORE_PROD].[schema].[table]
    );

    DISCONNECT FROM ODBC;
QUIT;


proc sql;
    CONNECT TO ODBC (DSN='RBIDTPRDSS1_SMARTSTORE' 
                     USER="fnbjnb01\myusername" 
                     PASSWORD="mypassword");

    Create Table Test as 
    SELECT *
    FROM CONNECTION TO ODBC (
        SELECT TOP 5 * 
        FROM [FNB_SMARTSTORE_PROD].[SI_CORE_IDIT_ODS].[P_POLICY]
    );

    DISCONNECT FROM ODBC;
QUIT;
