/*==============================================================
  FILE: OCR_00_Logging.sas
  PURPOSE: Audit logging macro for OCR tracking jobs.
           %include this at the top of OCR_02_Baseline.sas and
           OCR_03_Weekly.sas, after the libname is established.

  USAGE:
    %ocr_log(STEP_NAME, STATUS)
    %ocr_log(STEP_NAME, STATUS, records=123, metric=456789.00)
    %ocr_log(STEP_NAME, FAILED, error=INSERT failed SQLRC=8)

  VALID STATUS VALUES: STARTED / SUCCESS / WARNING / FAILED

  NOTES:
    - week_num and cycle_id are read from macro scope if they
      exist at call time; if not yet set, they log as missing.
    - Do NOT wrap in timing logic across separate macro calls --
      SAS macro variables are not block-scoped. Timing can be
      derived from RunDate in the DB (DATEDIFF between log rows).

  CHANGES:
    Bug 6 fixed -- error= and info= values are sanitised before
    being embedded in the INSERT so that any single or double
    quote in the message text cannot break the SQL.
    Strategy: replace any embedded single-quote with two
    single-quotes (standard SQL escaping) and strip double-
    quotes, then wrap the value in single-quotes for the INSERT.
==============================================================*/

%macro ocr_log(step, status, records=, metric=, error=, info=);

    %local _week _cycle
           _records _metric _error _info
           _error_clean _info_clean;

    /* Resolve context variables defensively -- they may not
       exist yet if logging is called before they are set.    */
    %if %symexist(week_num) %then %let _week  = &week_num.;
    %else                         %let _week  = .;

    %if %symexist(cycle_id) %then %let _cycle = '&cycle_id.';
    %else                         %let _cycle = NULL;

    /* Optional numeric values */
    %if %length(&records.) > 0 %then %let _records = &records.;
    %else                             %let _records = .;

    %if %length(&metric.) > 0 %then %let _metric = &metric.;
    %else                            %let _metric = .;

    /*----------------------------------------------------------*
     | Bug 6 fix: sanitise text fields for SQL safety.          |
     | %superq prevents macro resolution but does NOT escape    |
     | SQL quotes.  We strip double-quotes and double up any    |
     | single-quotes so the SQL INSERT cannot be broken by      |
     | special characters in the message text.                  |
     *----------------------------------------------------------*/
    %if %length(&error.) > 0 %then %do;
        %let _error_clean = %sysfunc(tranwrd(%superq(error), %str(%'), %str(%'%')));
        %let _error_clean = %sysfunc(compress(&_error_clean., %str(%")));
        %let _error = '&_error_clean.';
    %end;
    %else %let _error = NULL;

    %if %length(&info.) > 0 %then %do;
        %let _info_clean = %sysfunc(tranwrd(%superq(info), %str(%'), %str(%'%')));
        %let _info_clean = %sysfunc(compress(&_info_clean., %str(%")));
        %let _info = '&_info_clean.';
    %end;
    %else %let _info = NULL;

    /* Database insert */
    proc sql noprint;
        insert into STI_WER.OCR_Run_Log
        (
            WeekNum,
            CycleID,
            ProcessStep,
            Status,
            RecordsProcessed,
            MetricValue,
            ErrorMessage,
            AdditionalInfo
        )
        values
        (
            &_week.,
            &_cycle.,
            "&step.",
            "&status.",
            &_records.,
            &_metric.,
            &_error.,
            &_info.
        );
    quit;

    /*----------------------------------------------------------*
     | SAS log output                                           |
     *----------------------------------------------------------*/
    %put NOTE: [OCR_LOG] Step=&step. Status=&status.;

    %if %length(&records.) > 0 %then
        %put NOTE: [OCR_LOG] Records=&records.;

    %if %length(&metric.) > 0 %then
        %put NOTE: [OCR_LOG] Metric=&metric.;

    %if %length(&error.) > 0 %then
        %put NOTE: [OCR_LOG] Error=&error.;

%mend ocr_log;
