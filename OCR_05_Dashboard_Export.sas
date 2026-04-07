/*==============================================================
  FILE: OCR_05_Dashboard_Export_V2.sas
  PURPOSE: Queries OCR_Weekly_Tracker + MotorClaims_Final for
           ALL available history and exports a fully self-contained
           HTML dashboard file that can be opened in any browser
           or shared via email / Teams.
  SCHEDULE: Run after OCR_03_Weekly.sas each Monday, OR on demand.
  OUTPUT:   /data/fnbinsurance/Short_Term/Monitoring/
              OCR_Dashboard_YYYYMMDD.html

  CHANGES FROM V1 (FIXED):
  V2-FIX-1: Removed month-scoped date filter entirely. Previously
     the WHERE clause restricted RunDate to the current calendar
     month, meaning only the first (or only) week of each month
     appeared. All tracker rows are now returned and sorted by
     RunDate so the full monitoring cycle is visible.
  V2-FIX-2: Latest-week scalar sub-query now uses max(RunDate)
     against the numeric column instead of max(RunDate_fmt)
     against the character-formatted column. Alphabetical max on
     a DATE9. string (e.g. "07APR2025") does not reliably match
     chronological max; comparing numeric SAS dates does.
  V2-UX:    Full dashboard HTML/CSS/JS redesign — refined dark
     theme, improved KPI cards with trend indicators, better
     chart styling, sticky table headers, and a cleaner layout.
==============================================================*/

/*--------------------------------------------------------------
  1. Libname
--------------------------------------------------------------*/
%include "/data/fnbins/fnbinsurance/Growth_Analytics/SASCODE/DEPLOYED/Automation/STI_CA_2/Libnames.sas";

%macro logging(libname, database, schema, server);
LIBNAME &libname odbc noprompt="
  Driver=MSSQL;
  AnsiNPW=1;
  AuthenticationMethod=10;
  ApplicationUsingThreads=1;
  BulkLoadOptions=2;
  Database=&database;
  FetchTWFSasTime=1;
  HostName=&server;
  PortNumber=1433;
  UID=&User.;
  PWD=&FNB_Login."
Schema=&schema;
%mend;

%logging(STI_WER, FNB_STI_Analytics, Claims, LFE-RBPREATLDB1);

/*--------------------------------------------------------------
  2. Run date
--------------------------------------------------------------*/
%if not %symexist(rd) %then %do;
  %let rd = %sysfunc(today(), yymmddn8.);
%end;

%let outfile = /data/fnbinsurance/Short_Term/Monitoring/OCR_Dashboard_&rd..html;

/*--------------------------------------------------------------
  3. Pull ALL tracker rows — no date filter
  V2-FIX-1: Removed WHERE RunDate between &month_start. and
  &month_end. entirely. The dashboard now shows the complete
  monitoring cycle from the Baseline row onwards.
--------------------------------------------------------------*/
proc sql;
  create table work.tracker as
  select
      WeekLabel,
      RunDate,
      put(RunDate, date9.)          as RunDate_fmt,
      Baseline_Claims,
      Open_Claims,
      Current_OCR_Amt,
      Cumul_Closed,
      Closed_This_Week,
      OCR_Reduced_This_Week,
      Pct_Claims_Closed
  from STI_WER.OCR_Weekly_Tracker
  order by RunDate;
quit;

/*--------------------------------------------------------------
  4. Pull baseline and latest-week scalars
  V2-FIX-2: Latest-week sub-query uses max(RunDate) on the
  numeric SAS date column, which sorts correctly by date value.
  The original max(RunDate_fmt) sorted the DATE9. character
  string alphabetically which could return the wrong row.
--------------------------------------------------------------*/

/* Safe defaults — overwritten below if data exists */
%let baseline_claims = 0;
%let baseline_ocr    = 0;
%let latest_open     = 0;
%let latest_ocr      = 0;
%let latest_cumul    = 0;
%let latest_closed_wk= 0;
%let latest_ocr_red  = 0;
%let latest_pct      = 0;
%let latest_week     = N/A;

proc sql noprint;
  /* Baseline row */
  select Baseline_Claims,
         Current_OCR_Amt
  into :baseline_claims trimmed,
       :baseline_ocr    trimmed
  from work.tracker
  where WeekLabel = 'Baseline';

  /* Latest week scalars — V2-FIX-2: compare numeric RunDate */
  select Open_Claims,
         Current_OCR_Amt,
         Cumul_Closed,
         Closed_This_Week,
         OCR_Reduced_This_Week,
         Pct_Claims_Closed,
         WeekLabel
  into :latest_open      trimmed,
       :latest_ocr       trimmed,
       :latest_cumul     trimmed,
       :latest_closed_wk trimmed,
       :latest_ocr_red   trimmed,
       :latest_pct       trimmed,
       :latest_week      trimmed
  from work.tracker
  where RunDate = (select max(RunDate) from work.tracker);
quit;

/*--------------------------------------------------------------
  5. Pull claims detail (Motor Retail, not paid off)
--------------------------------------------------------------*/
proc sql;
  create table work.claims_detail as
  select
      c.ClaimCode,
      put(c.ReportMonth, date9.)                                  as ReportedMonth,
      c.ClaimHandler,
      put(c.Estimate_OCR, comma18.2)                              as Flagged_OCR,
      put(round(a.Total_Estimate_OCR_ExVAT, 0.01), comma18.2)     as Current_OCR,
      put(round(a.Total_Estimate_OCR_ExVAT,0.01) - c.Estimate_OCR,comma18.2) as Movement
  from STI_WER.Investigate_Claims c
  left join STI_WER.vw_OpsClaimsReport a
      on c.SubClaimCode = a.SubClaimCode
  where upcase(strip(c.ProductTypeSplit)) = 'MOTOR'
    and upcase(strip(c.Division))         = 'RETAIL'
    and coalesce(a.Total_Estimate_OCR_ExVAT, 0) > 0
  order by c.ReportMonth desc;
quit;

/*--------------------------------------------------------------
  6. Serialize tracker rows to JSON
--------------------------------------------------------------*/
data _null_;
  file '/tmp/tracker_json.txt' lrecl=32767;
  set work.tracker end=eof;
  if _n_ = 1 then put '[';
  put '{"label":"' WeekLabel      +(-1)  '",'
      '"date":"'   RunDate_fmt    +(-1)  '",'
      '"open":'    Open_Claims          best8. +(-1) ','
      '"ocr":'     Current_OCR_Amt      20.2   +(-1) ','
      '"cumul":'   Cumul_Closed         best8. +(-1) ','
      '"closed_wk":' Closed_This_Week   best8. +(-1) ','
      '"ocr_red":' OCR_Reduced_This_Week 20.2  +(-1) ','
      '"pct":'     Pct_Claims_Closed    8.6    +(-1)
      @;
  if eof then put '}]';
  else put '},';
run;

/*--------------------------------------------------------------
  7. Serialize claims detail to JSON
--------------------------------------------------------------*/
data _null_;
  file '/tmp/claims_json.txt' lrecl=32767;
  set work.claims_detail end=eof;
  ch = tranwrd(ClaimHandler, '"', '\"');
  if _n_ = 1 then put '[';
  put '{"claim":"'       ClaimCode      +(-1) '",'
      '"month":"'        ReportedMonth  +(-1) '",'
      '"handler":"'      ch             +(-1) '",'
      '"flagged_ocr":"'  Flagged_OCR    +(-1) '",'
      '"current_ocr":"'  Current_OCR    +(-1) '",'
      '"movement":"'     Movement       +(-1) '"}'
      @;
  if eof then put ']';
  else put ',';
run;

/*--------------------------------------------------------------
  8. Read tracker JSON into macro variable
--------------------------------------------------------------*/
%let tracker_json = ;

data _null_;
  infile '/tmp/tracker_json.txt' lrecl=32767 end=eof;
  input;
  call symput('tracker_json', cats(symget('tracker_json'), trim(_infile_)));
run;

/*==============================================================
  9. Write HTML dashboard — redesigned V2 UI
==============================================================*/
data _null_;
  file "&outfile." lrecl=32767;

  put '<!DOCTYPE html>';
  put '<html lang="en">';
  put '<head>';
  put '<meta charset="UTF-8">';
  put '<meta name="viewport" content="width=device-width, initial-scale=1.0">';
  put "<title>OCR Monitor &#8212; &latest_week.</title>";
  put '<link rel="preconnect" href="https://fonts.googleapis.com">';
  put '<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=Instrument+Sans:wght@400;500;600&display=swap" rel="stylesheet">';
  put '<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.js"></script>';
  put '<style>';

  /* ---- Design tokens ---- */
  put ':root {';
  put '  --bg:        #080b10;';
  put '  --surface:   #0e1219;';
  put '  --surface2:  #141820;';
  put '  --surface3:  #1a2030;';
  put '  --border:    rgba(255,255,255,0.06);';
  put '  --border2:   rgba(255,255,255,0.11);';
  put '  --text:      #dde3ee;';
  put '  --text2:     #8b95a8;';
  put '  --muted:     #4e5668;';
  put '  --blue:      #4f8ef7;';
  put '  --blue-dim:  rgba(79,142,247,0.12);';
  put '  --blue-glow: rgba(79,142,247,0.25);';
  put '  --green:     #3ecf8e;';
  put '  --green-dim: rgba(62,207,142,0.12);';
  put '  --amber:     #f5a623;';
  put '  --amber-dim: rgba(245,166,35,0.12);';
  put '  --red:       #f06a6a;';
  put '  --red-dim:   rgba(240,106,106,0.12);';
  put '  --font:      "Instrument Sans", sans-serif;';
  put '  --mono:      "IBM Plex Mono", monospace;';
  put '  --radius:    10px;';
  put '}';

  put '*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }';
  put 'body { background: var(--bg); color: var(--text); font-family: var(--font);';
  put '       font-size: 14px; line-height: 1.6; min-height: 100vh;';
  put '       background-image: radial-gradient(ellipse 80% 50% at 50% -10%, rgba(79,142,247,0.07), transparent); }';

  /* Layout */
  put '.shell { max-width: 1280px; margin: 0 auto; padding: 2.5rem 2rem 4rem; }';

  /* ---- Top bar ---- */
  put '.topbar { display: flex; align-items: center; justify-content: space-between;';
  put '          margin-bottom: 2.5rem; }';
  put '.brand { display: flex; align-items: center; gap: 12px; }';
  put '.brand-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--blue);';
  put '             box-shadow: 0 0 8px var(--blue); animation: pulse 2.5s ease-in-out infinite; }';
  put '@keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.4} }';
  put '.brand-name { font-family: var(--mono); font-size: 13px; color: var(--text2);';
  put '              letter-spacing: 0.08em; }';
  put '.brand-name span { color: var(--blue); }';
  put '.topbar-right { display: flex; align-items: center; gap: 10px; }';
  put '.chip { display: inline-flex; align-items: center; gap: 6px; padding: 4px 12px;';
  put '        border-radius: 20px; font-size: 11px; font-family: var(--mono);';
  put '        letter-spacing: 0.05em; border: 1px solid var(--border2); color: var(--text2); }';
  put '.chip.live { border-color: rgba(62,207,142,0.4); color: var(--green);';
  put '             background: var(--green-dim); }';
  put '.chip.live::before { content:""; width:6px; height:6px; border-radius:50%;';
  put '                     background:var(--green); display:inline-block; }';

  /* ---- Page title ---- */
  put '.page-title { margin-bottom: 2rem; }';
  put '.page-title .eyebrow { font-family: var(--mono); font-size: 11px; letter-spacing: 0.14em;';
  put '                       text-transform: uppercase; color: var(--blue); margin-bottom: 8px;';
  put '                       display: flex; align-items: center; gap: 8px; }';
  put '.page-title .eyebrow::after { content:""; flex:1; height:1px; background:var(--blue-dim); }';
  put '.page-title h1 { font-size: 30px; font-weight: 600; color: var(--text); line-height: 1.15; }';
  put '.page-title h1 em { color: var(--blue); font-style: normal; }';

  /* ---- KPI cards ---- */
  put '.kpi-grid { display: grid; grid-template-columns: repeat(4,minmax(0,1fr)); gap: 14px; margin-bottom: 2rem; }';
  put '.kpi { background: var(--surface); border: 1px solid var(--border2);';
  put '       border-radius: var(--radius); padding: 1.4rem 1.25rem; position: relative;';
  put '       overflow: hidden; transition: border-color 0.2s, box-shadow 0.2s; }';
  put '.kpi:hover { border-color: var(--border2); box-shadow: 0 0 24px rgba(0,0,0,0.3); }';
  put '.kpi-stripe { position: absolute; top: 0; left: 0; right: 0; height: 3px; border-radius: 1px 1px 0 0; }';
  put '.kpi.blue  .kpi-stripe { background: linear-gradient(90deg,var(--blue),transparent); }';
  put '.kpi.green .kpi-stripe { background: linear-gradient(90deg,var(--green),transparent); }';
  put '.kpi.amber .kpi-stripe { background: linear-gradient(90deg,var(--amber),transparent); }';
  put '.kpi.red   .kpi-stripe { background: linear-gradient(90deg,var(--red),transparent); }';
  put '.kpi-label { font-family: var(--mono); font-size: 10px; letter-spacing: 0.1em;';
  put '             text-transform: uppercase; color: var(--muted); margin-bottom: 10px; }';
  put '.kpi-value { font-size: 32px; font-weight: 600; line-height: 1; color: var(--text);';
  put '             margin-bottom: 6px; font-variant-numeric: tabular-nums; }';
  put '.kpi.red   .kpi-value,';
  put '.kpi.amber .kpi-value { font-size: 22px; font-family: var(--mono); }';
  put '.kpi-sub { font-size: 12px; color: var(--text2); }';
  put '.kpi-sub strong { color: var(--text); font-weight: 500; }';
  put '.pbar-track { height: 3px; background: var(--surface3); border-radius: 2px; margin-top: 12px; overflow: hidden; }';
  put '.pbar-fill  { height: 3px; border-radius: 2px; background: var(--green); width: 0;';
  put '              transition: width 1.2s cubic-bezier(0.4,0,0.2,1); }';

  /* ---- Charts ---- */
  put '.chart-row { display: grid; grid-template-columns: 1.6fr 1fr; gap: 14px; margin-bottom: 2rem; }';
  put '.chart-card { background: var(--surface); border: 1px solid var(--border2);';
  put '              border-radius: var(--radius); padding: 1.25rem 1.5rem; }';
  put '.chart-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 1.25rem; }';
  put '.chart-label { font-family: var(--mono); font-size: 11px; letter-spacing: 0.08em;';
  put '               text-transform: uppercase; color: var(--text2); }';
  put '.chart-tag { font-family: var(--mono); font-size: 10px; padding: 2px 8px;';
  put '             border-radius: 4px; background: var(--blue-dim); color: var(--blue); }';

  /* ---- Section heading ---- */
  put '.section-label { font-family: var(--mono); font-size: 10px; letter-spacing: 0.12em;';
  put '                 text-transform: uppercase; color: var(--muted); margin-bottom: 10px;';
  put '                 display: flex; align-items: center; gap: 8px; }';
  put '.section-label::after { content:""; flex:1; height:1px; background:var(--border2); }';

  /* ---- Table ---- */
  put '.table-wrap { background: var(--surface); border: 1px solid var(--border2);';
  put '              border-radius: var(--radius); overflow: auto; margin-bottom: 1.5rem;';
  put '              max-height: 400px; }';
  put 'table { width: 100%; border-collapse: collapse; font-size: 13px; }';
  put 'thead { position: sticky; top: 0; z-index: 2; }';
  put 'thead tr { background: var(--surface2); }';
  put 'th { text-align: left; padding: 11px 16px; font-family: var(--mono); font-size: 10px;';
  put '     letter-spacing: 0.1em; text-transform: uppercase; color: var(--muted);';
  put '     font-weight: 400; border-bottom: 1px solid var(--border2); white-space: nowrap; }';
  put 'td { padding: 10px 16px; border-bottom: 1px solid var(--border); color: var(--text);';
  put '     white-space: nowrap; }';
  put 'tbody tr:last-child td { border-bottom: none; }';
  put 'tbody tr { transition: background 0.12s; }';
  put 'tbody tr:hover { background: var(--surface2); }';
  put '.num { font-family: var(--mono); font-size: 12px; }';
  put '.pos { color: var(--green); }';
  put '.neg { color: var(--red); }';

  /* Badges */
  put '.badge { display: inline-flex; align-items: center; padding: 2px 10px; border-radius: 4px;';
  put '         font-family: var(--mono); font-size: 11px; letter-spacing: 0.04em; }';
  put '.badge-base { background: var(--blue-dim);  color: var(--blue);  border: 1px solid rgba(79,142,247,0.25); }';
  put '.badge-wk   { background: var(--green-dim); color: var(--green); border: 1px solid rgba(62,207,142,0.2); }';

  /* ---- Claims section ---- */
  put '.toggle-row { display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px; }';
  put '.toggle-btn { display: inline-flex; align-items: center; gap: 6px;';
  put '              background: transparent; border: 1px solid var(--border2);';
  put '              color: var(--text2); font-family: var(--mono); font-size: 11px;';
  put '              letter-spacing: 0.06em; padding: 6px 14px; border-radius: 6px;';
  put '              cursor: pointer; transition: all 0.18s; }';
  put '.toggle-btn:hover { border-color: var(--blue); color: var(--blue); background: var(--blue-dim); }';
  put '#claimsSection { display: none; }';
  put '.search-bar { width: 100%; background: var(--surface2);';
  put '              border: 1px solid var(--border2); border-radius: 8px;';
  put '              padding: 9px 16px; color: var(--text);';
  put '              font-family: var(--mono); font-size: 12px; margin-bottom: 10px;';
  put '              outline: none; transition: border-color 0.18s; }';
  put '.search-bar::placeholder { color: var(--muted); }';
  put '.search-bar:focus { border-color: var(--blue); box-shadow: 0 0 0 3px var(--blue-dim); }';

  /* Footer */
  put '.footer { text-align: center; font-family: var(--mono); font-size: 11px;';
  put '          color: var(--muted); margin-top: 3rem; padding-top: 1.5rem;';
  put '          border-top: 1px solid var(--border); letter-spacing: 0.06em; }';

  put '</style>';
  put '</head>';
  put '<body>';
  put '<div class="shell">';

  /* ---- Top bar ---- */
  put '<div class="topbar">';
  put '  <div class="brand">';
  put '    <div class="brand-dot"></div>';
  put '    <div class="brand-name">FNB <span>ST Insurance</span> &#8212; Analytics</div>';
  put '  </div>';
  put '  <div class="topbar-right">';
  put '    <span class="chip">Motor &#8226; Retail &#8226; Not Paid Off</span>';
  put "    <span class='chip live'>Current as of &rd.</span>";
  put '  </div>';
  put '</div>';

  /* ---- Page title ---- */
  put '<div class="page-title">';
  put '  <div class="eyebrow">OCR Monitoring Dashboard</div>';
  put "  <h1>OCR Weekly Tracker &#8212; <em>&latest_week.</em></h1>";
  put '</div>';

  /* ---- KPI cards ---- */
  put '<div class="kpi-grid">';

  put '  <div class="kpi blue">';
  put '    <div class="kpi-stripe"></div>';
  put '    <div class="kpi-label">Baseline Claims</div>';
  put "    <div class='kpi-value' id='m-baseline'>&baseline_claims.</div>";
  put '    <div class="kpi-sub">flagged on the 16th</div>';
  put '  </div>';

  put '  <div class="kpi green">';
  put '    <div class="kpi-stripe"></div>';
  put '    <div class="kpi-label">Open This Week</div>';
  put "    <div class='kpi-value' id='m-open'>&latest_open.</div>";
  put "    <div class='kpi-sub'><strong id='pct-label'>&latest_pct.</strong> resolved</div>";
  put '    <div class="pbar-track"><div class="pbar-fill" id="pbar"></div></div>';
  put '  </div>';

  put '  <div class="kpi amber">';
  put '    <div class="kpi-stripe"></div>';
  put '    <div class="kpi-label">Cumul. Closed</div>';
  put "    <div class='kpi-value'>&latest_cumul.</div>";
  put "    <div class='kpi-sub'><strong>&latest_closed_wk.</strong> closed this week</div>";
  put '  </div>';

  put '  <div class="kpi red">';
  put '    <div class="kpi-stripe"></div>';
  put '    <div class="kpi-label">Current OCR Total</div>';
  put "    <div class='kpi-value'>R &latest_ocr.</div>";
  put "    <div class='kpi-sub'>&#8595;&nbsp;<strong>R &latest_ocr_red.</strong> reduced this week</div>";
  put '  </div>';

  put '</div>';

  /* ---- Charts ---- */
  put '<div class="chart-row">';

  put '  <div class="chart-card">';
  put '    <div class="chart-head">';
  put '      <span class="chart-label">OCR Amount Over Cycle</span>';
  put '      <span class="chart-tag">R Total</span>';
  put '    </div>';
  put '    <div style="position:relative;height:240px;"><canvas id="ocrChart"></canvas></div>';
  put '  </div>';

  put '  <div class="chart-card">';
  put '    <div class="chart-head">';
  put '      <span class="chart-label">Claims Closed Per Week</span>';
  put '      <span class="chart-tag">Count</span>';
  put '    </div>';
  put '    <div style="position:relative;height:240px;"><canvas id="closedChart"></canvas></div>';
  put '  </div>';

  put '</div>';

  /* ---- Weekly tracker table ---- */
  put '<p class="section-label">Weekly Tracker Detail</p>';
  put '<div class="table-wrap">';
  put '<table>';
  put '<thead><tr>';
  put '  <th>Week</th><th>Run Date</th><th>Baseline</th><th>Open</th>';
  put '  <th>Closed / Wk</th><th>Cumul. Closed</th><th>% Resolved</th>';
  put '  <th>Current OCR</th><th>OCR Reduced</th>';
  put '</tr></thead>';
  put '<tbody id="trackerBody"></tbody>';
  put '</table>';
  put '</div>';

  /* ---- Claims detail ---- */
  put '<div class="toggle-row">';
  put '  <p class="section-label" style="flex:1;margin:0;">Claims Detail</p>';
  put '  <button class="toggle-btn" onclick="toggleClaims(this)">Show detail &#8595;</button>';
  put '</div>';

  put '<div id="claimsSection">';
  put '  <input class="search-bar" type="text" placeholder="Filter by claim code, handler, or month&#8230;" oninput="filterClaims(this.value)">';
  put '  <div class="table-wrap">';
  put '    <table>';
  put '    <thead><tr>';
  put '      <th>Claim Code</th><th>Reported Month</th><th>Handler</th>';
  put '      <th>OCR When Flagged</th><th>Current OCR</th><th>Movement</th>';
  put '    </tr></thead>';
  put '    <tbody id="claimsBody"></tbody>';
  put '    </table>';
  put '  </div>';
  put '</div>';

  put '<div class="footer">Generated by OCR_05_Dashboard_Export_V2.sas &#8226; FNB ST Insurance Analytics &#8226; Motor &#8226; Retail</div>';
  put '</div>'; /* .shell */

  /* ---- Inline JS ---- */
  put '<script>';
  put 'Chart.defaults.color = "#4e5668";';
  put 'Chart.defaults.font.family = "IBM Plex Mono, monospace";';
  put 'Chart.defaults.font.size = 11;';

  /* Inject tracker JSON safely via symget() */
  length _tracker_json $32767;
  _tracker_json = symget('tracker_json');
  put 'const TRACKER = ' _tracker_json ';';

  put 'const CLAIMS = ';
run;

/*--------------------------------------------------------------
  10. Append claims JSON directly from temp file
--------------------------------------------------------------*/
data _null_;
  file "&outfile." lrecl=32767 mod;
  infile '/tmp/claims_json.txt' lrecl=32767 end=eof;
  input;
  put _infile_;
  if eof then put ';';
run;

/*--------------------------------------------------------------
  11. Resume HTML output — JS logic, charts, close tags
--------------------------------------------------------------*/
data _null_;
  file "&outfile." lrecl=32767 mod;

  /* Progress bar */
  put "const baseline = &baseline_claims.;";
  put "const latestOpen = &latest_open.;";
  put 'const pct = baseline > 0 ? Math.round((1 - latestOpen / baseline) * 100) : 0;';
  put 'document.getElementById("pbar").style.width = pct + "%";';

  /* Formatters */
  put 'const fmtR = v => v === 0 ? "&#8212;" : "R\u00a0" + Number(v).toLocaleString("en-ZA",{minimumFractionDigits:2,maximumFractionDigits:2});';
  put 'const fmtN = v => Number(v).toLocaleString("en-ZA");';
  put 'const fmtP = v => (v * 100).toFixed(1) + "%";';

  /* Tracker table */
  put 'const tbody = document.getElementById("trackerBody");';
  put 'TRACKER.forEach(r => {';
  put '  const isBase = r.label === "Baseline";';
  put '  const badgeClass = isBase ? "badge-base" : "badge-wk";';
  put '  const tr = document.createElement("tr");';
  put '  tr.innerHTML = `';
  put '    <td><span class="badge ${badgeClass}">${r.label}</span></td>';
  put '    <td class="num" style="color:var(--text2)">${r.date}</td>';
  put '    <td class="num">${fmtN(r.open + r.cumul)}</td>';
  put '    <td class="num">${fmtN(r.open)}</td>';
  put '    <td class="num">${r.closed_wk === 0 ? "<span style=color:var(--muted)>&#8212;</span>" : fmtN(r.closed_wk)}</td>';
  put '    <td class="num">${fmtN(r.cumul)}</td>';
  put '    <td class="num">${r.pct === 0 ? "<span style=color:var(--muted)>&#8212;</span>" : fmtP(r.pct)}</td>';
  put '    <td class="num">${fmtR(r.ocr)}</td>';
  put '    <td class="num ${r.ocr_red > 0 ? "pos" : ""}">${r.ocr_red === 0 ? "<span style=color:var(--muted)>&#8212;</span>" : "&#8595;\u00a0" + fmtR(r.ocr_red)}</td>';
  put '  `;';
  put '  tbody.appendChild(tr);';
  put '});';

  /* Claims table */
  put 'let claimsData = CLAIMS;';
  put 'function renderClaims(data) {';
  put '  const cb = document.getElementById("claimsBody");';
  put '  cb.innerHTML = "";';
  put '  data.forEach(c => {';
  put '    const mv = parseFloat(c.movement.replace(/[^0-9.\-]/g,""));';
  put '    const mvClass = mv > 0 ? "neg" : mv < 0 ? "pos" : "";';
  put '    const mvArrow = mv > 0 ? "&#8593;\u00a0" : mv < 0 ? "&#8595;\u00a0" : "";';
  put '    const tr = document.createElement("tr");';
  put '    tr.innerHTML = `';
  put '      <td class="num">${c.claim}</td>';
  put '      <td>${c.month}</td>';
  put '      <td>${c.handler}</td>';
  put '      <td class="num">${c.flagged_ocr}</td>';
  put '      <td class="num">${c.current_ocr}</td>';
  put '      <td class="num ${mvClass}">${mvArrow}${c.movement}</td>`;';
  put '    cb.appendChild(tr);';
  put '  });';
  put '}';
  put 'renderClaims(claimsData);';

  /* Toggle */
  put 'function toggleClaims(btn) {';
  put '  const s = document.getElementById("claimsSection");';
  put '  const open = s.style.display === "block";';
  put '  s.style.display = open ? "none" : "block";';
  put '  btn.textContent = open ? "Show detail \u2193" : "Hide detail \u2191";';
  put '}';

  /* Search */
  put 'function filterClaims(q) {';
  put '  const lq = q.toLowerCase();';
  put '  renderClaims(claimsData.filter(c =>';
  put '    c.claim.toLowerCase().includes(lq) ||';
  put '    c.handler.toLowerCase().includes(lq) ||';
  put '    c.month.toLowerCase().includes(lq)';
  put '  ));';
  put '}';

  /* Chart — OCR over cycle */
  put 'const labels     = TRACKER.map(r => r.label);';
  put 'const ocrVals    = TRACKER.map(r => r.ocr);';
  put 'const closedVals = TRACKER.map(r => r.closed_wk);';

  put 'new Chart(document.getElementById("ocrChart"), {';
  put '  type: "line",';
  put '  data: { labels, datasets: [{';
  put '    data: ocrVals,';
  put '    borderColor: "#4f8ef7",';
  put '    backgroundColor: ctx => {';
  put '      const g = ctx.chart.ctx.createLinearGradient(0,0,0,240);';
  put '      g.addColorStop(0,"rgba(79,142,247,0.18)");';
  put '      g.addColorStop(1,"rgba(79,142,247,0)");';
  put '      return g;';
  put '    },';
  put '    fill: true, tension: 0.4,';
  put '    pointBackgroundColor: "#4f8ef7",';
  put '    pointBorderColor: "#080b10",';
  put '    pointBorderWidth: 2,';
  put '    pointRadius: 5, borderWidth: 2';
  put '  }]},';
  put '  options: { responsive:true, maintainAspectRatio:false,';
  put '    plugins: { legend:{ display:false }, tooltip:{';
  put '      backgroundColor:"#0e1219", borderColor:"rgba(255,255,255,0.1)", borderWidth:1,';
  put '      callbacks:{ label: ctx => " R " + Number(ctx.raw).toLocaleString("en-ZA",{minimumFractionDigits:2}) } } },';
  put '    scales: {';
  put '      y: { ticks:{ callback: v => "R "+(v/1000).toFixed(0)+"k", color:"#4e5668" },';
  put '           grid:{ color:"rgba(255,255,255,0.04)" }, border:{ display:false } },';
  put '      x: { ticks:{ color:"#4e5668" }, grid:{ display:false }, border:{ display:false } }';
  put '    }}';
  put '});';

  /* Chart — closed per week */
  put 'new Chart(document.getElementById("closedChart"), {';
  put '  type: "bar",';
  put '  data: { labels, datasets: [{';
  put '    data: closedVals,';
  put '    backgroundColor: "rgba(62,207,142,0.7)",';
  put '    hoverBackgroundColor: "#3ecf8e",';
  put '    borderRadius: 5, borderSkipped: false';
  put '  }]},';
  put '  options: { responsive:true, maintainAspectRatio:false,';
  put '    plugins: { legend:{ display:false }, tooltip:{';
  put '      backgroundColor:"#0e1219", borderColor:"rgba(255,255,255,0.1)", borderWidth:1 } },';
  put '    scales: {';
  put '      y: { ticks:{ color:"#4e5668" }, grid:{ color:"rgba(255,255,255,0.04)" }, border:{ display:false } },';
  put '      x: { ticks:{ color:"#4e5668" }, grid:{ display:false }, border:{ display:false } }';
  put '    }}';
  put '});';

  put '</script>';
  put '</body>';
  put '</html>';
run;

%put NOTE: Dashboard V2 exported to &outfile.;
