Attribute VB_Name = "WeeklyTracker"

' ============================================================
' OCR CLAIMS - WEEKLY PROGRESS TRACKER MACRO
' ============================================================
' Every Monday (via Task Scheduler):
'   1. Refresh all data
'   2. Fill Current OCR Amount + Claims Closed into correct week col
'   3. Export Motor & Non-Motor tables (Col Q onwards) as separate xlsx
'   4. Screenshot all charts from each sheet
'   5. Email both xlsx files + chart screenshots to recipient
'
' On the 16th of each month:
'   1. Fill full baseline (Open Claims + OCR + Closed)
'   2. Send cycle-complete summary email
'   3. Clear tracker for new cycle
'
' Open Claims is set ONCE on the 16th — does NOT update weekly
' ============================================================

' *** SET YOUR EMAIL ADDRESS HERE ***
Const RECIPIENT_EMAIL As String = "YOUR_EMAIL@example.com"

' *** SET YOUR TEMP FOLDER FOR EXPORTS (must exist) ***
' Charts and xlsx exports are saved here before emailing
Const EXPORT_FOLDER As String = "C:\Temp\OCR_Reports\"

' ============================================================
' DEBUG SETTINGS
' DEBUG_MODE      = True  : use fake date, show message boxes
' DEBUG_FAKE_DATE : date to simulate ("YYYY-MM-DD")
' DEBUG_LOG       = True  : write timestamped log to Notes sheet
' ============================================================
Const DEBUG_MODE As Boolean = True
Const DEBUG_FAKE_DATE As String = "2025-03-17"
Const DEBUG_LOG As Boolean = True


' ============================================================
' MAIN ENTRY POINT
' ============================================================
Sub RunWeeklyUpdate()

    Dim today As Date
    If DEBUG_MODE Then
        today = CDate(DEBUG_FAKE_DATE)
        WriteLog "DEBUG RUN - Simulating date: " & Format(today, "dd MMM yyyy")
    Else
        today = Date
    End If

    ' Ensure export folder exists
    Call EnsureFolder(EXPORT_FOLDER)

    ' Refresh all data
    WriteLog "Refreshing all data connections..."
    ThisWorkbook.RefreshAll
    Application.CalculateUntilAsyncQueriesDone
    If Not DEBUG_MODE Then Application.Wait Now + TimeValue("00:00:10")
    WriteLog "Refresh complete."

    ' 16th = baseline day: fill baseline, send cycle summary, clear for next cycle
    If Day(today) = 16 Then
        WriteLog "16th detected - filling baseline."
        Call FillColumn(ThisWorkbook.Sheets("Motor"), 2, "Motor", True)
        Call FillColumn(ThisWorkbook.Sheets("Non-Motor"), 2, "Non-Motor", True)
        Call SendCycleCompleteEmail(today)
        WriteLog "Cycle complete email sent. Clearing tracker."
        Call ClearTracker
        If Not DEBUG_MODE Then
            MsgBox "Baseline filled. Cycle-complete email sent. Tracker cleared for new cycle.", vbInformation
        End If
        Exit Sub
    End If

    ' Weekly update: determine column, fill OCR + Closed
    Dim weekCol As Integer
    weekCol = GetWeekColumn(today)

    If weekCol = 0 Then
        WriteLog "ERROR: Could not determine week column for " & Format(today, "dd MMM yyyy")
        Exit Sub
    End If

    Dim weekNum As Integer: weekNum = weekCol - 2
    WriteLog "Filling Week " & weekNum & " (col " & weekCol & ") for " & Format(today, "dd MMM yyyy")

    Call FillColumn(ThisWorkbook.Sheets("Motor"), weekCol, "Motor", False)
    Call FillColumn(ThisWorkbook.Sheets("Non-Motor"), weekCol, "Non-Motor", False)
    WriteLog "Tracker values written."

    ' Export tables + charts and send weekly report email
    Call SendWeeklyReportEmail(today, weekNum)

    If Not DEBUG_MODE Then
        MsgBox "Week " & weekNum & " tracker updated and report emails sent.", vbInformation
    End If

End Sub


' ============================================================
' Fill tracker column
' isBaseline=True  -> Open Claims + OCR + Closed (16th only)
' isBaseline=False -> OCR + Closed only (weekly)
'
' Motor:     B7=Total_Row_Count  B12=Sum_Current_Estimate_OCR  B10=Paid_Off_Count
' Non-Motor: B4=Total_Row_Count  B9=Sum_Current_Estimate_OCR   B7=Paid_Off_Count
' Tracker:   row28=Open Claims   row29=OCR Amount              row30=Cumulative Closed
' ============================================================
Sub FillColumn(ws As Worksheet, targetCol As Integer, sheetType As String, isBaseline As Boolean)

    Dim openClaims As Double, currentOCR As Double, paidOff As Double

    If sheetType = "Motor" Then
        openClaims = ws.Cells(7, 2).Value
        currentOCR = ws.Cells(12, 2).Value
        paidOff    = ws.Cells(10, 2).Value
    Else
        openClaims = ws.Cells(4, 2).Value
        currentOCR = ws.Cells(9, 2).Value
        paidOff    = ws.Cells(7, 2).Value
    End If

    If isBaseline Then
        ws.Cells(28, targetCol).Value = openClaims
        WriteLog sheetType & " Baseline - Open Claims: " & openClaims
    End If

    ws.Cells(29, targetCol).Value = currentOCR
    ws.Cells(30, targetCol).Value = paidOff
    WriteLog sheetType & " - OCR: " & Format(currentOCR, "#,##0.00") & " | Closed: " & paidOff

End Sub


' ============================================================
' Determine column from Mondays elapsed since last 16th
' Returns: 2=Baseline(16th), 3=W1, 4=W2, 5=W3, 6=W4, 7=W5, 0=error
' ============================================================
Function GetWeekColumn(today As Date) As Integer

    Dim d As Integer: d = Day(today)
    Dim m As Integer: m = Month(today)
    Dim y As Integer: y = Year(today)

    If d = 16 Then GetWeekColumn = 2: Exit Function

    Dim baseDate As Date
    If d > 16 Then
        baseDate = DateSerial(y, m, 16)
    Else
        If m = 1 Then
            baseDate = DateSerial(y - 1, 12, 16)
        Else
            baseDate = DateSerial(y, m - 1, 16)
        End If
    End If

    Dim mondays As Integer: mondays = 0
    Dim i As Long
    For i = 1 To DateDiff("d", baseDate, today)
        If Weekday(baseDate + i, vbMonday) = 1 Then mondays = mondays + 1
    Next i

    If mondays >= 1 And mondays <= 5 Then
        GetWeekColumn = mondays + 2
    Else
        GetWeekColumn = 0
    End If

End Function


' ============================================================
' WEEKLY REPORT EMAIL
' Exports Motor + Non-Motor Col Q tables as xlsx
' Screenshots all charts from each sheet
' Sends one email per sheet (2 emails total) with attachments
' ============================================================
Sub SendWeeklyReportEmail(today As Date, weekNum As Integer)

    WriteLog "Starting weekly report export..."

    Dim dateStr As String: dateStr = Format(today, "yyyy-mm-dd")
    Dim motorFile As String:    motorFile    = EXPORT_FOLDER & "Motor_Report_" & dateStr & ".xlsx"
    Dim nonMotorFile As String: nonMotorFile = EXPORT_FOLDER & "NonMotor_Report_" & dateStr & ".xlsx"

    ' Export tables
    Call ExportTableToXlsx(ThisWorkbook.Sheets("Motor"), motorFile, "Motor")
    Call ExportTableToXlsx(ThisWorkbook.Sheets("Non-Motor"), nonMotorFile, "Non-Motor")
    WriteLog "Tables exported."

    ' Screenshot charts
    Dim motorCharts() As String
    Dim nmCharts() As String
    motorCharts = ExportCharts(ThisWorkbook.Sheets("Motor"), "Motor", dateStr)
    nmCharts    = ExportCharts(ThisWorkbook.Sheets("Non-Motor"), "NonMotor", dateStr)
    WriteLog "Charts exported."

    ' Send Motor email
    Call SendReportEmail( _
        RECIPIENT_EMAIL, _
        "Motor OCR Claims Report - Week " & weekNum & " (" & Format(today, "dd MMM yyyy") & ")", _
        "Hi," & vbCrLf & vbCrLf & _
        "Please find attached the Motor OCR Claims report for Week " & weekNum & " (" & Format(today, "dd MMM yyyy") & ")." & vbCrLf & vbCrLf & _
        "Attached:" & vbCrLf & _
        "  - Motor claims data table (Col Q onwards)" & vbCrLf & _
        "  - Chart screenshots" & vbCrLf & vbCrLf & _
        "Regards," & vbCrLf & "OCR Claims Automation", _
        motorFile, motorCharts)

    ' Send Non-Motor email
    Call SendReportEmail( _
        RECIPIENT_EMAIL, _
        "Non-Motor OCR Claims Report - Week " & weekNum & " (" & Format(today, "dd MMM yyyy") & ")", _
        "Hi," & vbCrLf & vbCrLf & _
        "Please find attached the Non-Motor OCR Claims report for Week " & weekNum & " (" & Format(today, "dd MMM yyyy") & ")." & vbCrLf & vbCrLf & _
        "Attached:" & vbCrLf & _
        "  - Non-Motor claims data table (Col Q onwards)" & vbCrLf & _
        "  - Chart screenshots" & vbCrLf & vbCrLf & _
        "Regards," & vbCrLf & "OCR Claims Automation", _
        nonMotorFile, nmCharts)

    WriteLog "Weekly report emails sent."

End Sub


' ============================================================
' Export Col Q onwards from a sheet to a new xlsx file
' Headers in row 7, data from row 8 to last filled row
' ============================================================
Sub ExportTableToXlsx(ws As Worksheet, outputPath As String, sheetLabel As String)

    ' Find last data row in col Q (col 17)
    Dim lastRow As Long: lastRow = 7
    Dim i As Long
    For i = ws.max_row To 8 Step -1
        If ws.Cells(i, 17).Value <> "" Then
            lastRow = i
            Exit For
        End If
    Next i

    ' Create new workbook
    Dim newWb As Workbook
    Set newWb = Workbooks.Add
    Dim newWs As Worksheet
    Set newWs = newWb.Sheets(1)
    newWs.Name = sheetLabel

    ' Copy Col Q-V (cols 17-22) from source
    Dim srcCol As Integer, destCol As Integer
    destCol = 1
    For srcCol = 17 To 22
        ' Copy header
        newWs.Cells(1, destCol).Value = ws.Cells(7, srcCol).Value
        newWs.Cells(1, destCol).Font.Bold = True
        ' Copy data rows
        Dim r As Long
        For r = 8 To lastRow
            Dim cellVal As Variant
            cellVal = ws.Cells(r, srcCol).Value
            newWs.Cells(r - 6, destCol).Value = cellVal
            ' Format date column
            If srcCol = 18 And IsDate(cellVal) Then
                newWs.Cells(r - 6, destCol).NumberFormat = "dd MMM yyyy"
            End If
            ' Format currency columns
            If srcCol = 19 Or srcCol = 20 Or srcCol = 21 Then
                newWs.Cells(r - 6, destCol).NumberFormat = "#,##0.00"
            End If
        Next r
        destCol = destCol + 1
    Next srcCol

    ' Auto-fit columns
    newWs.Columns("A:F").AutoFit

    ' Save
    newWb.SaveAs outputPath, FileFormat:=xlOpenXMLWorkbook
    newWb.Close False
    WriteLog "Exported " & sheetLabel & " table to " & outputPath

End Sub


' ============================================================
' Export all charts from a sheet as PNG images
' Returns array of file paths
' ============================================================
Function ExportCharts(ws As Worksheet, prefix As String, dateStr As String) As String()

    Dim paths() As String
    Dim chartCount As Integer: chartCount = ws.ChartObjects.Count

    If chartCount = 0 Then
        ReDim paths(0)
        paths(0) = ""
        ExportCharts = paths
        Exit Function
    End If

    ReDim paths(chartCount - 1)

    Dim j As Integer
    For j = 1 To chartCount
        Dim co As ChartObject
        Set co = ws.ChartObjects(j)
        Dim imgPath As String
        imgPath = EXPORT_FOLDER & prefix & "_Chart" & j & "_" & dateStr & ".png"

        ' Export chart as image
        co.Chart.Export Filename:=imgPath, FilterName:="PNG"
        paths(j - 1) = imgPath
        WriteLog "Chart " & j & " exported: " & imgPath
    Next j

    ExportCharts = paths

End Function


' ============================================================
' Send email via Outlook with one xlsx + chart image attachments
' ============================================================
Sub SendReportEmail(toAddr As String, subject As String, body As String, xlsxPath As String, chartPaths() As String)

    On Error GoTo EmailError

    Dim oApp As Object: Set oApp = CreateObject("Outlook.Application")
    Dim oMail As Object: Set oMail = oApp.CreateItem(0)

    With oMail
        .To = toAddr
        .Subject = subject
        .Body = body

        ' Attach xlsx
        If xlsxPath <> "" Then
            If Dir(xlsxPath) <> "" Then
                .Attachments.Add xlsxPath
            End If
        End If

        ' Attach chart images
        Dim k As Integer
        For k = 0 To UBound(chartPaths)
            If chartPaths(k) <> "" Then
                If Dir(chartPaths(k)) <> "" Then
                    .Attachments.Add chartPaths(k)
                End If
            End If
        Next k

        .Send
    End With

    Exit Sub

EmailError:
    WriteLog "ERROR sending email '" & subject & "': " & Err.Description
    If Not DEBUG_MODE Then MsgBox "Email error: " & Err.Description, vbExclamation

End Sub


' ============================================================
' Send cycle-complete summary email on the 16th
' ============================================================
Sub SendCycleCompleteEmail(today As Date)

    On Error GoTo EmailError

    Dim oApp As Object: Set oApp = CreateObject("Outlook.Application")
    Dim oMail As Object: Set oMail = oApp.CreateItem(0)
    Dim mWs As Worksheet:  Set mWs  = ThisWorkbook.Sheets("Motor")
    Dim nmWs As Worksheet: Set nmWs = ThisWorkbook.Sheets("Non-Motor")

    With oMail
        .To = RECIPIENT_EMAIL
        .Subject = "OCR Claims Tracker - Monthly Cycle Complete (" & Format(today, "dd MMM yyyy") & ")"
        .Body = "Hi," & vbCrLf & vbCrLf & _
                "Today is the 16th — the monthly OCR Claims tracker cycle is complete." & vbCrLf & vbCrLf & _
                "--- Final Values Before Reset ---" & vbCrLf & _
                "MOTOR" & vbCrLf & _
                "  Open Claims (Baseline):  " & mWs.Cells(28, 2).Value & vbCrLf & _
                "  Final OCR Amount:         " & GetLastFilled(mWs, 29) & vbCrLf & _
                "  Final Claims Closed:      " & GetLastFilled(mWs, 30) & vbCrLf & vbCrLf & _
                "NON-MOTOR" & vbCrLf & _
                "  Open Claims (Baseline):  " & nmWs.Cells(28, 2).Value & vbCrLf & _
                "  Final OCR Amount:         " & GetLastFilled(nmWs, 29) & vbCrLf & _
                "  Final Claims Closed:      " & GetLastFilled(nmWs, 30) & vbCrLf & vbCrLf & _
                "The tracker has been cleared and the new baseline for today has been filled in." & vbCrLf & _
                "Week 1 will populate next Monday." & vbCrLf & vbCrLf & _
                "Regards," & vbCrLf & "OCR Claims Automation"
        .Send
    End With

    WriteLog "Cycle-complete email sent."
    Exit Sub

EmailError:
    WriteLog "ERROR sending cycle-complete email: " & Err.Description

End Sub


' ============================================================
' Clear tracker — reset cols B:G rows 28-30
' ============================================================
Sub ClearTracker()

    Dim names(1) As String
    names(0) = "Motor": names(1) = "Non-Motor"
    Dim s As Integer
    For s = 0 To 1
        Dim ws As Worksheet: Set ws = ThisWorkbook.Sheets(names(s))
        Dim col As Integer
        For col = 2 To 7
            ws.Cells(28, col).ClearContents
            ws.Cells(29, col).ClearContents
            ws.Cells(30, col).Value = 0
        Next col
        ws.Cells(33, 2).Value = "0.0%"
    Next s
    WriteLog "Tracker cleared."

End Sub


' ============================================================
' Ensure a folder exists, create it if not
' ============================================================
Sub EnsureFolder(folderPath As String)
    If Dir(folderPath, vbDirectory) = "" Then
        MkDir folderPath
        WriteLog "Created folder: " & folderPath
    End If
End Sub


' ============================================================
' Helper: last non-empty value in a tracker row (cols B-G)
' ============================================================
Function GetLastFilled(ws As Worksheet, rowNum As Integer) As String
    Dim col As Integer
    Dim v As String: v = "N/A"
    For col = 2 To 7
        If ws.Cells(rowNum, col).Value <> "" And ws.Cells(rowNum, col).Value <> 0 Then
            v = Format(ws.Cells(rowNum, col).Value, "#,##0.00")
        End If
    Next col
    GetLastFilled = v
End Function


' ============================================================
' DEBUG: Simulate full monthly cycle step by step
' Walks: 16th → W1 → W2 → W3 → W4 → W5 → next 16th
' Pauses 2s between steps — watch the sheet update live
' Check Notes sheet for full log after completion
' ============================================================
Sub SimulateFullCycle()

    WriteLog "====== SIMULATION START ======"
    Call ClearTracker

    Dim steps(6) As String
    steps(0) = "2025-03-16"   ' 16th - baseline
    steps(1) = "2025-03-17"   ' Week 1
    steps(2) = "2025-03-24"   ' Week 2
    steps(3) = "2025-03-31"   ' Week 3
    steps(4) = "2025-04-07"   ' Week 4
    steps(5) = "2025-04-14"   ' Week 5
    steps(6) = "2025-04-16"   ' Next 16th - reset

    Call EnsureFolder(EXPORT_FOLDER)

    Dim i As Integer
    For i = 0 To 6
        Dim fakeDate As Date: fakeDate = CDate(steps(i))
        WriteLog "--- Step " & i & ": " & Format(fakeDate, "dd MMM yyyy") & " ---"

        If Day(fakeDate) = 16 And i = 0 Then
            Call FillColumn(ThisWorkbook.Sheets("Motor"), 2, "Motor", True)
            Call FillColumn(ThisWorkbook.Sheets("Non-Motor"), 2, "Non-Motor", True)

        ElseIf Day(fakeDate) = 16 And i > 0 Then
            Call SendCycleCompleteEmail(fakeDate)
            Call ClearTracker
            Call FillColumn(ThisWorkbook.Sheets("Motor"), 2, "Motor", True)
            Call FillColumn(ThisWorkbook.Sheets("Non-Motor"), 2, "Non-Motor", True)

        Else
            Dim wc As Integer: wc = GetWeekColumn(fakeDate)
            If wc > 0 Then
                Call FillColumn(ThisWorkbook.Sheets("Motor"), wc, "Motor", False)
                Call FillColumn(ThisWorkbook.Sheets("Non-Motor"), wc, "Non-Motor", False)
                Call SendWeeklyReportEmail(fakeDate, wc - 2)
            End If
        End If

        Application.Wait Now + TimeValue("00:00:02")
    Next i

    WriteLog "====== SIMULATION COMPLETE ======"
    MsgBox "Simulation done! Check the tracker, your inbox, and the Notes sheet log.", vbInformation

End Sub


' ============================================================
' Write timestamped log to Notes sheet col A
' ============================================================
Sub WriteLog(msg As String)

    If Not DEBUG_LOG Then Exit Sub
    Dim logWs As Worksheet
    On Error Resume Next
    Set logWs = ThisWorkbook.Sheets("Notes")
    On Error GoTo 0
    If logWs Is Nothing Then Exit Sub
    Dim nextRow As Long
    nextRow = logWs.Cells(logWs.Rows.Count, 1).End(xlUp).Row + 1
    If nextRow < 2 Then nextRow = 2
    logWs.Cells(nextRow, 1).Value = Format(Now, "yyyy-mm-dd hh:mm:ss") & "  |  " & msg

End Sub
