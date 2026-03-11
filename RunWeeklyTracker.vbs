' ============================================================
' RunWeeklyTracker.vbs
' Called by Windows Task Scheduler every Monday
' Opens the Excel file (synced from SharePoint via OneDrive)
' and runs the weekly tracker macro
' ============================================================

' *** UPDATE THIS TO YOUR ONEDRIVE SYNCED PATH ***
' Sync the SharePoint folder to your PC via OneDrive.
' Right-click the folder in SharePoint > "Sync" or "Add shortcut to OneDrive"
' Your path will look like:
'   C:\Users\YourName\OneDrive - YourCompany\FolderName\ytt.xlsm
Const FILE_PATH = "C:\Users\YourName\OneDrive - YourCompany\Claims\ytt.xlsm"

Dim xlApp
Dim xlBook

Set xlApp = CreateObject("Excel.Application")
xlApp.Visible = False
xlApp.DisplayAlerts = False
xlApp.EnableEvents = True

' Open file - UpdateLinks ensures SharePoint data connections refresh
Set xlBook = xlApp.Workbooks.Open(FILE_PATH, UpdateLinks:=True)

' Wait for connections to load before running macro
xlApp.Wait Now() + TimeValue("00:00:15")

' Run the macro
xlApp.Run "WeeklyTracker.RunWeeklyUpdate"

' Save - OneDrive will sync changes back to SharePoint automatically
xlBook.Save
xlBook.Close False
xlApp.Quit

Set xlBook = Nothing
Set xlApp = Nothing
