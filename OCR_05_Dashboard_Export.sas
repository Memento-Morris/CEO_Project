      

NOTE: No rows were selected.
ERROR: The following columns were not found in the contributing tables: RunDate.
NOTE: PROC SQL set option NOEXEC and will continue to check the syntax of statements.
NOTE: The SAS System stopped processing this step because of errors.
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      
NOTE: There were 188 observations read from the data set WORK.CLAIMS_DETAIL.
NOTE: DATA statement used (Total process time):
      real time           0.01 seconds
      cpu time            0.02 seconds
      

360          call symcat('tracker_json', trim(symget('tracker_json')) || trim(_infile_));
                  ______
                  251

ERROR 251-185: The subroutine SYMCAT is unknown, or cannot be accessed. Check your spelling. 
               Either it was not found in the path(s) of executable images, or there was incorrect or missing subroutine descriptor 
               information.

NOTE: The SAS System stopped processing this step because of errors.
NOTE: DATA statement used (Total process time):
      real time           0.03 seconds
      cpu time            0.01 seconds
      

366          call symcat('claims_json', trim(symget('claims_json')) || trim(_infile_));
                  ______
                  251

ERROR 251-185: The subroutine SYMCAT is unknown, or cannot be accessed. Check your spelling. 
               Either it was not found in the path(s) of executable images, or there was incorrect or missing subroutine descriptor 
    
WARNING: Apparent symbolic reference MDASH not resolved.
WARNING: Apparent symbolic reference LATEST_WEEK not resolved.
WARNING: Apparent symbolic reference MDASH not resolved.
WARNING: Apparent symbolic reference MDASH not resolved.
WARNING: Apparent symbolic reference LATEST_WEEK not resolved.
WARNING: Apparent symbolic reference MDASH not resolved.
WARNING: Apparent symbolic reference MDASH not resolved.
WARNING: Apparent symbolic reference LATEST_WEEK not resolved.
WARNING: Apparent symbolic reference BULL not resolved.
WARNING: Apparent symbolic reference BULL not resolved.
WARNING: Apparent symbolic reference BASELINE_CLAIMS not resolved.
WARNING: Apparent symbolic reference LATEST_OPEN not resolved.
WARNING: Apparent symbolic reference LATEST_PCT not resolved.
WARNING: Apparent symbolic reference LATEST_CUMUL not resolved.
WARNING: Apparent symbolic reference LATEST_CLOSED_WK not resolved.
WARNING: Apparent symbolic reference LATEST_OCR not resolved.
WARNING: Apparent symbolic reference LATEST_OCR_RED not resolved.
WARNING: Apparent symbolic reference BASELINE_CLAIMS not resolved.
WARNING: Apparent symbolic reference LATEST_OPEN not resolved.           information.
