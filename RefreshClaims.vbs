' RefreshClaims.vbs
' Opens the Excel file, runs Refresh All, saves and closes it.
' Schedule this via Windows Task Scheduler to run every Monday.

Dim sFile
sFile = "C:\ClaimsReports\Claims_Tracking.xlsx"   ' <-- UPDATE THIS PATH

Dim oExcel
Set oExcel = CreateObject("Excel.Application")
oExcel.Visible = False
oExcel.DisplayAlerts = False

Dim oWorkbook
Set oWorkbook = oExcel.Workbooks.Open(sFile)

' Refresh All connections (same as Data → Refresh All)
oWorkbook.RefreshAll

' Wait for background queries to finish
Dim oConn
For Each oConn In oWorkbook.Connections
    Do While oConn.OLEDBConnection.Refreshing
        WScript.Sleep 1000
    Loop
Next

oWorkbook.Save
oWorkbook.Close False
oExcel.Quit

Set oWorkbook = Nothing
Set oExcel = Nothing

WScript.Echo "Refresh complete."
