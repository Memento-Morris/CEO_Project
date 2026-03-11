# OCR Claims Weekly Tracker - Setup Guide

## What Happens Each Monday
1. Data refreshes automatically
2. Current OCR Amount + Claims Closed written to the correct week column
3. Motor claims table (Col Q–V) exported as `Motor_Report_YYYY-MM-DD.xlsx`
4. Non-Motor claims table exported as `NonMotor_Report_YYYY-MM-DD.xlsx`
5. All 3 charts from each sheet exported as PNG screenshots
6. **Two separate emails sent** — one for Motor, one for Non-Motor — each with the xlsx + chart images attached

## What Happens on the 16th
1. Full baseline filled (Open Claims + OCR + Closed) — Open Claims frozen for the month
2. Cycle-complete summary email sent with final values
3. Tracker cleared and ready for new cycle

---

## SharePoint Setup (Do This First)

Since your file is in SharePoint, sync it locally via OneDrive:
1. Go to the SharePoint folder in your browser
2. Click **Sync** (or right-click > "Add shortcut to OneDrive")
3. Find the synced path in File Explorer — will look like:
   `C:\Users\YourName\OneDrive - YourCompany\FolderName\`
4. All saves go local first, then sync back to SharePoint automatically

---

## Step 1: Create the Export Folder

Create a folder at `C:\Temp\OCR_Reports\` — this is where chart PNGs and xlsx exports are temporarily saved before being emailed.

You can change this path in the VBA by updating:
```vba
Const EXPORT_FOLDER As String = "C:\Temp\OCR_Reports\"
```

---

## Step 2: Save File as .xlsm

1. Open `ytt.xlsx` in Excel
2. **File → Save As → "Excel Macro-Enabled Workbook (*.xlsm)"**
3. Save into your OneDrive synced folder as `ytt.xlsm`

---

## Step 3: Add the VBA Macro

1. Open `ytt.xlsm`, press **Alt + F11**
2. Right-click **VBAProject (ytt.xlsm)** → **Insert → Module**
3. Open `WeeklyTracker_VBA.bas` in Notepad, copy all, paste into the module
4. Update these constants at the top:
   ```vba
   Const RECIPIENT_EMAIL As String = "YOUR_EMAIL@example.com"
   Const EXPORT_FOLDER As String = "C:\Temp\OCR_Reports\"
   ```
5. **Ctrl + S**, close VBA editor

---

## Step 4: Update VBScript Path

Open `RunWeeklyTracker.vbs` in Notepad and update:
```
Const FILE_PATH = "C:\Users\YourName\OneDrive - YourCompany\Claims\ytt.xlsm"
```

---

## Step 5: Windows Task Scheduler

1. Open **Task Scheduler** (Win + S)
2. **Create Basic Task** → Name: `OCR Claims Weekly Tracker`
3. **Trigger**: Weekly → Monday → set time (e.g. 08:00 AM)
4. **Action**: Start a program
   - Program: `wscript.exe`
   - Arguments: `"C:\full\path\to\RunWeeklyTracker.vbs"`
5. **Finish**
6. Right-click task → **Properties** → check **"Run whether user is logged on or not"**

---

## Step 6: Enable Macros

1. Open `ytt.xlsm`
2. **File → Options → Trust Center → Trust Center Settings → Macro Settings**
3. Select **"Enable all macros"**
4. Check **"Trust access to the VBA project object model"**
5. OK

---

## Email Attachments Per Week

| Email | Attachments |
|-------|------------|
| Motor Report | `Motor_Report_YYYY-MM-DD.xlsx` + 3 chart PNGs |
| Non-Motor Report | `NonMotor_Report_YYYY-MM-DD.xlsx` + 3 chart PNGs |

The xlsx contains columns: `ClaimCode`, `ReportedMonth`, `Estimate_OCR_When_Flagged`, `Current_Estimate_OCR`, `OCR_Movement`, `ClaimHandler`

---

## Testing & Debugging

### Test a single step
1. Set `DEBUG_FAKE_DATE` to the date you want to simulate:
   ```vba
   Const DEBUG_MODE As Boolean = True
   Const DEBUG_FAKE_DATE As String = "2025-03-17"  ' A Monday = Week 1
   ```
2. **Alt + F8** → `RunWeeklyUpdate` → **Run**
3. Check your inbox and the Notes sheet log

### Simulate the full cycle at once
1. **Alt + F8** → `SimulateFullCycle` → **Run**
2. Walks through all 7 steps with 2s pauses
3. Sends actual emails at each weekly step — check inbox
4. Notes sheet has full timestamped log

### Go live
```vba
Const DEBUG_MODE As Boolean = False
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Charts not exporting | Ensure `C:\Temp\OCR_Reports\` exists (macro creates it, but verify permissions) |
| Email not sending | Outlook must be installed and logged in |
| Wrong file path | Update `FILE_PATH` in `RunWeeklyTracker.vbs` |
| Module not found | Ensure the VBA module is named `WeeklyTracker` in the editor |
| Data not refreshing | Check OneDrive is synced and SharePoint connection is active |
