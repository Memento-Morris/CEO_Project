options obs=100;
options mprint source notes;

/* Setup for the bundle: the original resolves campaign codes from the
   Excel config and discovers per-campaign tables in production libraries.
   Here we seed the same &camp_count / &camp_N macro variables and create
   matching WORK members so %build_campaign_filter has real metadata to
   query via dictionary.tables. */
%let camp_count = 2;
%let camp_1 = APN_FUNERAL;
%let camp_2 = APN_LIFE;

data work.APN_FUNERAL_20260101_0800; cust_no = 1; run;
data work.APN_FUNERAL_20260102_0900; cust_no = 2; run;
data work.APN_LIFE_20260103_1000;    cust_no = 3; run;
data work.SOME_OTHER_TABLE;          cust_no = 4; run;
