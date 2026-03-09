# Claims Excel — Monday Auto-Refresh Setup

## Step 1 — Edit the script
Open `RefreshClaims.vbs` in Notepad and update line 4:
```
sFile = "C:\ClaimsReports\Claims_Tracking.xlsx"
```
Change it to the **actual full path** of your Excel file on the server.

---

## Step 2 — Test it manually
Double-click `RefreshClaims.vbs` — it should open Excel in the background,
refresh all data, save, and close. Check your Excel file to confirm it updated.

---

## Step 3 — Schedule it in Task Scheduler

1. Open **Task Scheduler** (search in Start menu)
2. Click **Create Basic Task** on the right
3. Name it: `Claims Excel Refresh`
4. Trigger: **Weekly → Monday** at your preferred time (e.g. 6:00 AM)
5. Action: **Start a program**
   - Program: `wscript.exe`
   - Arguments: `"C:\Path\To\RefreshClaims.vbs"`
6. Finish → enter your Windows password when prompted

Done! Every Monday it will automatically do the same as clicking Data → Refresh All.
