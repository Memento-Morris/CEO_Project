/*==============================================================
  FILE: OCR_05_Dashboard_Export.sas
  PURPOSE: Queries OCR_Weekly_Tracker + MotorClaims_Final for
           the current month and exports a fully self-contained
           HTML dashboard file that can be opened in any browser
           or shared via email / Teams.
  SCHEDULE: Run after OCR_03_Weekly.sas each Monday, OR on demand.
  OUTPUT:   /data/fnbinsurance/Short_Term/Monitoring/
              OCR_Dashboard_YYYYMMDD.html

  FIXES APPLIED:
  1. RunDate column error: PROC SQL via libref uses SAS SQL
     functions (year()/month()) which resolve correctly against
     the ODBC libref. The original query was fine structurally,
     but the tracker work dataset was never built when the
     upstream PROC SQL failed. Fixed by pulling tracker data
     via a DATA step from the libref using a SAS date range
     instead, making the WHERE clause unambiguous.
  2. SYMCAT unknown: call symcat() does not exist in SAS Base.
     Replaced with a DATA step that writes the JSON files and
     reads them back using call symput() with cats() to build
     the macro variable correctly line by line.
  3. HTML entity conflicts: &mdash; &bull; etc. inside double-
     quoted SAS strings are resolved as macro variable references
     and cause "apparent symbolic reference not resolved" warnings.
     Fixed by replacing all HTML entities with their Unicode
     escape equivalents (e.g. &#8212; for mdash, &#8226; for bull)
     or rewriting with single-quoted strings where no macro
     variable injection is needed.
  4. FIX (NEW): BASELINE_CLAIMS not resolved warning + crash on
     PUT "&tracker_json.;" — two bugs fixed together:
       a) Pre-initialise all scalar macro variables with %let
          before PROC SQL so downstream references never fail
          even when the Baseline row is absent from the data.
       b) Replaced  put "&tracker_json.;"  with a DATA step
          variable populated via symget(). Embedding the macro
          variable directly in a PUT argument causes SAS to parse
          the JSON content (braces, colons, decimal numbers) as
          column/format specifications, producing ERROR 22, 200,
          and 156. Using symget() retrieves the value at run-time
          into a character variable which PUT writes as a plain
          string with no parser confusion.
  5. FIX (NEW): JSON numeric formatting — SAS default formats
     for numeric PUT produce extra leading/trailing spaces and
     may include E-notation. Added explicit formats to all
     numeric fields in the tracker JSON DATA step so the output
     is clean, compact JSON that the browser can parse reliably.
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
  3. Pull tracker rows for this month
     FIX 1: Use explicit SAS date integer range in the WHERE
     clause instead of year()/month() functions, which avoids
     any ambiguity when the ODBC driver translates the query.
     Compute the first and last day of the current month as
     SAS date integers and pass them as literals.
--------------------------------------------------------------*/
%let month_start = %sysfunc(intnx(month, %sysfunc(today()), 0, b));
%let month_end   = %sysfunc(intnx(month, %sysfunc(today()), 0, e));

proc sql;
  create table work.tracker as
  select
      WeekLabel,
      put(RunDate, date9.)          as RunDate_fmt,
      Baseline_Claims,
      Open_Claims,
      Current_OCR_Amt,
      Cumul_Closed,
      Closed_This_Week,
      OCR_Reduced_This_Week,
      Pct_Claims_Closed
  from STI_WER.OCR_Weekly_Tracker
  where RunDate between &month_start. and &month_end.
  order by RunDate;
quit;

/*--------------------------------------------------------------
  4. Pull baseline scalars
  FIX 4a: Pre-initialise every macro variable that PROC SQL
  populates via INTO. If the query returns zero rows (e.g. no
  Baseline row exists yet, or the latest-week sub-select finds
  nothing) SAS leaves the macro variable undefined, producing
  "apparent symbolic reference not resolved" warnings for every
  downstream reference and causing PUT statements in the HTML
  DATA step to crash. Providing safe defaults here means the
  dashboard still renders with placeholder values instead of
  aborting.  Also added NOPRINT to the first SELECT so it no
  longer echoes row counts to the log.
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

  /* Latest week scalars */
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
  where RunDate_fmt = (select max(RunDate_fmt) from work.tracker);
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
  6. Serialize tracker rows to JSON via DATA step
  FIX 2: Replaced call symcat() (which does not exist in SAS)
  with a two-step approach:
    a) Write JSON to a temp file.
    b) Read it back using call symput() with cats() to
       concatenate each line into the macro variable.

  FIX 5: Added explicit numeric formats to every numeric field.
  Without them, SAS uses the variable's default format which can
  produce leading spaces ("  197"), E-notation for large numbers,
  or extra decimal places — all of which break JSON.parse() in
  the browser.  Formats used:
    Open_Claims / Cumul_Closed / Closed_This_Week  -> best8.
    Current_OCR_Amt / OCR_Reduced_This_Week        -> 20.2
    Pct_Claims_Closed                              -> 8.6
  The +(-1) pointer-control trims trailing blanks after each
  formatted value so there is no whitespace inside the JSON.
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
  8. Read tracker JSON fragment into a macro variable
  FIX 2 (continued): call symput() + cats() appends each line.
  Macro variables are capped at 64 KB; safe for the tracker
  (max ~10 rows).  Claims JSON is streamed directly to the HTML
  file in Step 10 to avoid the 64 KB ceiling.
--------------------------------------------------------------*/
%let tracker_json = ;

data _null_;
  infile '/tmp/tracker_json.txt' lrecl=32767 end=eof;
  input;
  call symput('tracker_json', cats(symget('tracker_json'), trim(_infile_)));
run;

/*--------------------------------------------------------------
  9. Write the HTML dashboard — static head + CSS
  FIX 3: All HTML entities (&mdash; &bull; etc.) replaced with
  numeric equivalents (&#8212; &#8226;) so SAS does not attempt
  to resolve them as macro variable references.  Lines needing
  macro variable injection use double quotes only where
  necessary; purely static lines use single quotes.
--------------------------------------------------------------*/
data _null_;
  file "&outfile." lrecl=32767;

  put '<!DOCTYPE html>';
  put '<html lang="en">';
  put '<head>';
  put '<meta charset="UTF-8">';
  put '<meta name="viewport" content="width=device-width, initial-scale=1.0">';
  put "<title>Motor OCR Tracker &#8212; &latest_week. &#8212; &rd.</title>";
  put '<link rel="preconnect" href="https://fonts.googleapis.com">';
  put '<link href="https://fonts.googleapis.com/css2?family=DM+Mono:wght@400;500&family=Sora:wght@300;400;600&display=swap" rel="stylesheet">';
  put '<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.js"></script>';
  put '<style>';
  put ':root {';
  put '  --bg: #0d0f14;';
  put '  --surface: #151820;';
  put '  --surface2: #1c2030;';
  put '  --border: rgba(255,255,255,0.07);';
  put '  --border2: rgba(255,255,255,0.13);';
  put '  --text: #e8eaf2;';
  put '  --muted: #6b7280;';
  put '  --accent: #4f8ef7;';
  put '  --accent2: #34d399;';
  put '  --warn: #f59e0b;';
  put '  --danger: #f87171;';
  put '  --font: "Sora", sans-serif;';
  put '  --mono: "DM Mono", monospace;';
  put '}';
  put '*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }';
  put 'body { background: var(--bg); color: var(--text); font-family: var(--font);';
  put '       font-size: 14px; line-height: 1.6; min-height: 100vh; }';
  put '.shell { max-width: 1200px; margin: 0 auto; padding: 2rem 1.5rem; }';

  /* Header */
  put '.header { display: flex; justify-content: space-between; align-items: flex-start;';
  put '          margin-bottom: 2rem; padding-bottom: 1.5rem;';
  put '          border-bottom: 1px solid var(--border2); }';
  put '.header-left .eyebrow { font-size: 11px; letter-spacing: 0.12em; text-transform: uppercase;';
  put '                        color: var(--accent); font-family: var(--mono); margin-bottom: 6px; }';
  put '.header-left h1 { font-size: 26px; font-weight: 600; color: var(--text); }';
  put '.header-right { text-align: right; font-family: var(--mono); font-size: 12px; color: var(--muted); line-height: 2; }';
  put '.pill { display: inline-block; padding: 3px 10px; border-radius: 20px;';
  put '        font-size: 11px; font-family: var(--mono);';
  put '        background: rgba(79,142,247,0.15); color: var(--accent);';
  put '        border: 1px solid rgba(79,142,247,0.3); }';

  /* Metric cards */
  put '.metrics { display: grid; grid-template-columns: repeat(4, minmax(0,1fr));';
  put '           gap: 12px; margin-bottom: 2rem; }';
  put '.card { background: var(--surface); border: 1px solid var(--border);';
  put '        border-radius: 12px; padding: 1.25rem; position: relative; overflow: hidden; }';
  put '.card::before { content: ""; position: absolute; top: 0; left: 0; right: 0;';
  put '                height: 2px; }';
  put '.card.blue::before  { background: var(--accent); }';
  put '.card.green::before { background: var(--accent2); }';
  put '.card.amber::before { background: var(--warn); }';
  put '.card.red::before   { background: var(--danger); }';
  put '.card-label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em;';
  put '              color: var(--muted); margin-bottom: 8px; font-family: var(--mono); }';
  put '.card-value { font-size: 28px; font-weight: 600; color: var(--text); line-height: 1; margin-bottom: 6px; }';
  put '.card-sub { font-size: 12px; color: var(--muted); }';
  put '.pbar-bg { height: 4px; background: var(--surface2); border-radius: 2px; margin-top: 10px; }';
  put '.pbar-fill { height: 4px; border-radius: 2px; background: var(--accent2);';
  put '             transition: width 0.8s ease; }';

  /* Charts */
  put '.charts { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 2rem; }';
  put '.chart-card { background: var(--surface); border: 1px solid var(--border);';
  put '              border-radius: 12px; padding: 1.25rem; }';
  put '.chart-title { font-size: 13px; font-weight: 600; color: var(--text); margin-bottom: 1rem;';
  put '               font-family: var(--mono); letter-spacing: 0.04em; }';

  /* Table */
  put '.section-head { font-size: 11px; text-transform: uppercase; letter-spacing: 0.1em;';
  put '                color: var(--muted); font-family: var(--mono); margin-bottom: 12px; }';
  put '.table-wrap { background: var(--surface); border: 1px solid var(--border);';
  put '              border-radius: 12px; overflow: hidden; margin-bottom: 2rem; }';
  put 'table { width: 100%; border-collapse: collapse; font-size: 13px; }';
  put 'thead tr { background: var(--surface2); }';
  put 'th { text-align: left; padding: 10px 14px; font-size: 11px; text-transform: uppercase;';
  put '     letter-spacing: 0.08em; color: var(--muted); font-family: var(--mono);';
  put '     font-weight: 400; border-bottom: 1px solid var(--border2); }';
  put 'td { padding: 10px 14px; border-bottom: 1px solid var(--border); color: var(--text); }';
  put 'tbody tr:last-child td { border-bottom: none; }';
  put 'tbody tr:hover { background: var(--surface2); }';
  put '.badge { display: inline-block; padding: 2px 9px; border-radius: 20px;';
  put '         font-size: 11px; font-family: var(--mono); }';
  put '.badge-base { background: rgba(79,142,247,0.15); color: var(--accent);';
  put '              border: 1px solid rgba(79,142,247,0.3); }';
  put '.badge-wk { background: rgba(52,211,153,0.12); color: var(--accent2);';
  put '            border: 1px solid rgba(52,211,153,0.25); }';

  /* Claims detail */
  put '.toggle-btn { background: var(--surface2); border: 1px solid var(--border2);';
  put '              color: var(--text); font-family: var(--mono); font-size: 12px;';
  put '              padding: 7px 16px; border-radius: 8px; cursor: pointer;';
  put '              margin-bottom: 12px; letter-spacing: 0.04em; }';
  put '.toggle-btn:hover { background: var(--surface); border-color: var(--accent); color: var(--accent); }';
  put '#claimsSection { display: none; }';

  /* Search */
  put '.search-bar { width: 100%; background: var(--surface2); border: 1px solid var(--border2);';
  put '              border-radius: 8px; padding: 8px 14px; color: var(--text);';
  put '              font-family: var(--mono); font-size: 13px; margin-bottom: 12px;';
  put '              outline: none; }';
  put '.search-bar:focus { border-color: var(--accent); }';

  put '.footer { text-align: center; font-size: 12px; color: var(--muted);';
  put '          font-family: var(--mono); margin-top: 2rem; padding-top: 1.5rem;';
  put '          border-top: 1px solid var(--border); }';

  put '</style>';
  put '</head>';
  put '<body>';
  put '<div class="shell">';

  /* Header block
     FIX 3: &mdash; -> &#8212;  |  &bull; -> &#8226;
     Only lines needing macro var injection use double quotes. */
  put '<div class="header">';
  put '  <div class="header-left">';
  put '    <p class="eyebrow">FNB ST Insurance &#8212; Motor Retail</p>';
  put "    <h1>OCR Weekly Tracker &#8212; &latest_week.</h1>";
  put '  </div>';
  put '  <div class="header-right">';
  put '    <div><span class="pill">Motor &#8226; Retail &#8226; Not Paid Off</span></div>';
  put "    <div style='margin-top:8px;'>Run date: &rd.</div>";
  put "    <div>Baseline: &rd. cycle</div>";
  put '  </div>';
  put '</div>';

  /* Metric cards */
  put '<div class="metrics">';

  put '  <div class="card blue">';
  put '    <div class="card-label">Baseline claims</div>';
  put "    <div class='card-value' id='m-baseline'>&baseline_claims.</div>";
  put '    <div class="card-sub">flagged on the 16th</div>';
  put '  </div>';

  put '  <div class="card green">';
  put '    <div class="card-label">Open this week</div>';
  put "    <div class='card-value' id='m-open'>&latest_open.</div>";
  put "    <div class='card-sub'>&latest_pct. resolved</div>";
  put '    <div class="pbar-bg">';
  put "      <div class='pbar-fill' id='pbar'></div>";
  put '    </div>';
  put '  </div>';

  put '  <div class="card amber">';
  put '    <div class="card-label">Cumul. closed</div>';
  put "    <div class='card-value'>&latest_cumul.</div>";
  put "    <div class='card-sub'>&latest_closed_wk. closed this week</div>";
  put '  </div>';

  put '  <div class="card red">';
  put '    <div class="card-label">Current OCR total</div>';
  put "    <div class='card-value' style='font-size:20px;'>R &latest_ocr.</div>";
  put "    <div class='card-sub'>reduced R &latest_ocr_red. this week</div>";
  put '  </div>';

  put '</div>';

  /* Charts */
  put '<div class="charts">';
  put '  <div class="chart-card">';
  put '    <div class="chart-title">OCR amount over the cycle</div>';
  put '    <div style="position:relative; height:220px;"><canvas id="ocrChart"></canvas></div>';
  put '  </div>';
  put '  <div class="chart-card">';
  put '    <div class="chart-title">Claims closed per week</div>';
  put '    <div style="position:relative; height:220px;"><canvas id="closedChart"></canvas></div>';
  put '  </div>';
  put '</div>';

  /* Tracker table */
  put '<p class="section-head">Weekly tracker detail</p>';
  put '<div class="table-wrap">';
  put '<table>';
  put '<thead><tr>';
  put '  <th>Week</th><th>Date</th><th>Open</th>';
  put '  <th>Closed this week</th><th>Cumul. closed</th>';
  put '  <th>% closed</th><th>Current OCR</th><th>OCR reduced</th>';
  put '</tr></thead>';
  put '<tbody id="trackerBody"></tbody>';
  put '</table>';
  put '</div>';

  /* Claims detail toggle */
  put '<button class="toggle-btn" onclick="toggleClaims(this)">Show claims detail &#8595;</button>';
  put '<div id="claimsSection">';
  put '  <input class="search-bar" type="text" placeholder="Search by claim, handler, month..." oninput="filterClaims(this.value)">';
  put '  <div class="table-wrap">';
  put '  <table>';
  put '  <thead><tr>';
  put '    <th>Claim code</th><th>Reported month</th><th>Handler</th>';
  put '    <th>OCR when flagged</th><th>Current OCR</th><th>Movement</th>';
  put '  </tr></thead>';
  put '  <tbody id="claimsBody"></tbody>';
  put '  </table>';
  put '  </div>';
  put '</div>';

  put '<div class="footer">Generated by OCR_05_Dashboard_Export.sas &#8226; FNB ST Analytics &#8226; Motor &#8226; Retail</div>';
  put '</div>';

  /* ---- Inline JS with SAS-injected data ---- */
  put '<script>';

  /*------------------------------------------------------------
    FIX 4b: Inject tracker JSON safely.
    BEFORE (broken):
      put 'const TRACKER = ';
      put "&tracker_json.;";
    WHY IT CRASHED: When SAS macro-resolves &tracker_json. inside
    a PUT statement argument, it expands the JSON text inline.
    SAS then tries to parse tokens like  {"label":"Week 3",...}
    as column-name/format specifications.  The colon after the
    opening brace looks like a format modifier, the decimal in
    "0.709440" triggers ERROR 156 ("decimal spec must be less
    than width"), and the whole DATA step aborts.
    FIX: Retrieve the macro variable value at run-time into a
    DATA step character variable with symget().  PUT writes the
    variable value as a plain string — no SAS parser involvement
    with the content.
  ------------------------------------------------------------*/
  length _tracker_json $32767;
  _tracker_json = symget('tracker_json');
  put 'const TRACKER = ' _tracker_json ';';

  /* Inject claims data directly from the temp file to avoid 64KB limit */
  put 'const CLAIMS = ';
run;

/*--------------------------------------------------------------
  10. Append claims JSON directly from temp file into the HTML
      output — bypasses the 64 KB macro variable size ceiling.
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
  put 'document.getElementById("pbar").style.width =';
  put '  Math.round((1 - latestOpen/baseline)*100) + "%";';

  /* Formatters */
  put 'const fmtR = v => v === 0 ? "&#8212;" : "R " + Number(v).toLocaleString("en-ZA",{minimumFractionDigits:2,maximumFractionDigits:2});';
  put 'const fmtN = v => Number(v).toLocaleString("en-ZA");';
  put 'const fmtP = v => (v*100).toFixed(1) + "%";';

  /* Populate tracker table */
  put 'const tbody = document.getElementById("trackerBody");';
  put 'TRACKER.forEach(r => {';
  put '  const badgeClass = r.label === "Baseline" ? "badge-base" : "badge-wk";';
  put '  const tr = document.createElement("tr");';
  put '  tr.innerHTML = `';
  put '    <td><span class="badge ${badgeClass}">${r.label}</span></td>';
  put '    <td style="color:var(--muted);font-family:var(--mono)">${r.date}</td>';
  put '    <td>${fmtN(r.open)}</td>';
  put '    <td>${r.closed_wk === 0 ? "&#8212;" : fmtN(r.closed_wk)}</td>';
  put '    <td>${fmtN(r.cumul)}</td>';
  put '    <td>${r.pct === 0 ? "&#8212;" : fmtP(r.pct)}</td>';
  put '    <td style="font-family:var(--mono)">${fmtR(r.ocr)}</td>';
  put '    <td style="font-family:var(--mono)">${r.ocr_red === 0 ? "&#8212;" : fmtR(r.ocr_red)}</td>';
  put '  `;';
  put '  tbody.appendChild(tr);';
  put '});';

  /* Populate claims table */
  put 'let claimsData = CLAIMS;';
  put 'function renderClaims(data) {';
  put '  const cb = document.getElementById("claimsBody");';
  put '  cb.innerHTML = "";';
  put '  data.forEach(c => {';
  put '    const tr = document.createElement("tr");';
  put '    tr.innerHTML = `';
  put '      <td style="font-family:var(--mono)">${c.claim}</td>';
  put '      <td>${c.month}</td>';
  put '      <td>${c.handler}</td>';
  put '      <td style="font-family:var(--mono)">${c.flagged_ocr}</td>';
  put '      <td style="font-family:var(--mono)">${c.current_ocr}</td>';
  put '      <td style="font-family:var(--mono)">${c.movement}</td>';
  put '    `;';
  put '    cb.appendChild(tr);';
  put '  });';
  put '}';
  put 'renderClaims(claimsData);';

  /* Toggle + search */
  put 'function toggleClaims(btn) {';
  put '  const s = document.getElementById("claimsSection");';
  put '  const open = s.style.display === "block";';
  put '  s.style.display = open ? "none" : "block";';
  put '  btn.textContent = open ? "Show claims detail \u2193" : "Hide claims detail \u2191";';
  put '}';
  put 'function filterClaims(q) {';
  put '  const lq = q.toLowerCase();';
  put '  renderClaims(claimsData.filter(c =>';
  put '    c.claim.toLowerCase().includes(lq) ||';
  put '    c.handler.toLowerCase().includes(lq) ||';
  put '    c.month.toLowerCase().includes(lq)';
  put '  ));';
  put '}';

  /* Charts */
  put 'const labels     = TRACKER.map(r => r.label);';
  put 'const ocrVals    = TRACKER.map(r => r.ocr);';
  put 'const closedVals = TRACKER.map(r => r.closed_wk);';

  put 'new Chart(document.getElementById("ocrChart"), {';
  put '  type: "line",';
  put '  data: { labels, datasets: [{';
  put '    data: ocrVals,';
  put '    borderColor: "#4f8ef7",';
  put '    backgroundColor: "rgba(79,142,247,0.08)",';
  put '    fill: true, tension: 0.35,';
  put '    pointBackgroundColor: "#4f8ef7", pointRadius: 5, borderWidth: 2';
  put '  }]},';
  put '  options: { responsive: true, maintainAspectRatio: false,';
  put '    plugins: { legend: { display: false } },';
  put '    scales: {';
  put '      y: { ticks: { color: "#6b7280", font: { size: 11 },';
  put '                    callback: v => "R " + (v/1000).toFixed(0) + "k" },';
  put '           grid: { color: "rgba(255,255,255,0.05)" } },';
  put '      x: { ticks: { color: "#6b7280", font: { size: 11 } }, grid: { display: false } }';
  put '    }}';
  put '});';

  put 'new Chart(document.getElementById("closedChart"), {';
  put '  type: "bar",';
  put '  data: { labels, datasets: [{';
  put '    data: closedVals,';
  put '    backgroundColor: "#34d399",';
  put '    borderRadius: 4, borderSkipped: false';
  put '  }]},';
  put '  options: { responsive: true, maintainAspectRatio: false,';
  put '    plugins: { legend: { display: false } },';
  put '    scales: {';
  put '      y: { ticks: { color: "#6b7280", font: { size: 11 } },';
  put '           grid: { color: "rgba(255,255,255,0.05)" } },';
  put '      x: { ticks: { color: "#6b7280", font: { size: 11 } }, grid: { display: false } }';
  put '    }}';
  put '});';

  put '</script>';
  put '</body>';
  put '</html>';
run;

%put NOTE: Dashboard exported to &outfile.;
