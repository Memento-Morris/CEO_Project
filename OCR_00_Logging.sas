
/*==============================================================
  FILE: OCR_00_Logging.sas
==============================================================*/

%macro ocr_log(step, status, records=, metric=, error=, info=);

    %local _week _cycle
           _records _metric _error _info;

    /* Resolve context */
    %if %symexist(week_num) %then %let _week = &week_num.;
    %else %let _week = .;

    %if %symexist(cycle_id) %then %let _cycle = "&cycle_id.";
    %else %let _cycle = NULL;

    /* Optional values */
    %if %length(&records.) > 0 %then %let _records = &records.;
    %else %let _records = .;

    %if %length(&metric.) > 0 %then %let _metric = &metric.;
    %else %let _metric = .;

    %if %length(&error.) > 0 %then %let _error = "%superq(error)";
    %else %let _error = NULL;

    %if %length(&info.) > 0 %then %let _info = "%superq(info)";
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
     | SAS log output                         |
     *----------------------------------------------------------*/
    %put NOTE: [OCR_LOG] Step=&step. Status=&status.;

    %if %length(&records.) > 0 %then
        %put NOTE: [OCR_LOG] Records=&records.; 

    %if %length(&metric.) > 0 %then
        %put NOTE: [OCR_LOG] Metric=&metric.; 

    %if %length(&error.) > 0 %then
        %put NOTE: [OCR_LOG] Error=&error.; 

%mend ocr_log;
