# Branch 2 (Session 1) — Web Developer's Guide & Session Notes

> **Target Audience:** Web Developer learning the PowerShell + WPF Desktop Stack  
> **Topic:** Spreadsheet Ingestion, In-App DataGrid Previews, Desktop Process Launching, and Execution Policies  
> **Date:** September 2026  

---

## 1. The Big Picture: Excel Handling on the Desktop vs. Web

On the web, reading an Excel sheet typically involves:
1. An `<input type="file" accept=".xlsx" />`.
2. Passing the file buffer to an npm package like **`xlsx` (SheetJS)** or **`exceljs`** in Node.js.
3. Rendering the parsed JSON array in a TanStack Table or HTML `<table>`.

In desktop PowerShell:
- We don't have a web server; the files live directly on the coordinator's local hard drive.
- We use the **`ImportExcel`** PowerShell module (which uses the .NET **EPPlus** library under the hood).
- Like SheetJS, it reads raw `.xlsx` XML archives in memory — **zero dependency on Microsoft Office**.
- We display the records using a WPF **`DataGrid`** with custom dark theme styling.

---

## 2. What We Built in Branch 2 (Session 1)

### 2.1 The Spreadsheet Parser Module (`modules/Import-StudentSheet.ps1`)
In Node.js, you might write a helper: `parseStudentSheet(filePath)`.  
In PowerShell, we created the function: **`Import-StudentSheet -Path $Path`**.

#### How It Works:
```powershell
function Import-StudentSheet {
    param([string]$Path)
    ...
    # 1. Validate file existence and extension (.xlsx, .xls, .csv)
    # 2. If CSV: uses built-in Import-Csv
    # 3. If XLSX: uses Import-Excel without launching Excel.exe
    # 4. Filters out completely blank rows
    # 5. Returns a structured result object
}
```

#### What It Returns (Equivalent to a TypeScript Interface):
```powershell
[PSCustomObject]@{
    Success  = $true       # Boolean
    FilePath = $Path       # String
    RowCount = 153         # Integer
    Headers  = @(...)      # Array of column names (e.g. Timestamp, Name, Roll No)
    Rows     = @(...)      # Array of student row objects
    Error    = $null       # Error message if failed
}
```

#### Dual-Use Script (CLI + Module):
Like Node.js `if (require.main === module)`, we made this script work both ways:
1. **Dot-Sourced in App**: `. .\modules\Import-StudentSheet.ps1` exposes the function inside the app.
2. **Direct CLI Execution**: You can test it directly in terminal:
   ```powershell
   .\modules\Import-StudentSheet.ps1 -Path "C:\path\to\sheet.xlsx"
   ```

---

### 2.2 In-App Sheet Preview Modal (`UI/Views/DashboardView.xaml`)
In React, you would render a modal overlay: `{isModalOpen && <Modal><Table/></Modal>}`.  
In WPF, we use a root `<Grid>` with a collapsed overlay layer:

```xml
<Grid>
    <!-- Normal Dashboard Content -->
    <ScrollViewer> ... </ScrollViewer>

    <!-- Modal Overlay (Starts Hidden) -->
    <Grid x:Name="SheetPreviewModal" Visibility="Collapsed" Background="#D0151513">
        <Border Background="{DynamicResource PanelBrush}" ...>
            <!-- Header with Title, Count, and [X] Close -->
            <!-- WPF DataGrid displaying rows -->
            <!-- Footer with [Open in Windows] and [Close] -->
        </Border>
    </Grid>
</Grid>
```

#### WPF `DataGrid` Dark Theme Styling:
By default, WPF controls use standard Windows 95/classic gray palettes. To match our **Warm Dark Minimalism** theme:
- `DataGrid.ColumnHeaderStyle`: Styled with `#26261F` (`PanelModBrush`), `#E8B04B` amber text, and 1px borders.
- `DataGrid.CellStyle`: Styled with `#EAE6DD` bone white text and subtle accent highlighting when a cell or row is selected (`AccentTintBrush`).
- Alternating row backgrounds: `#202019` and `#1E1E1B`.

---

### 2.3 Option C: Two Ways to View the Sheet
Coordinators have two distinct needs when dealing with spreadsheets:
1. **Quick Glance**: *"Did my Google Form have 150 students or 200?"*  
   $\rightarrow$ Click **`[ Preview Sheet ]`** to open the in-app DataGrid modal without leaving the app.
2. **Deep Inspection / Editing**: *"I need to fix a student's typo in Excel."*  
   $\rightarrow$ Click **`[ Open File ]`** to launch the file directly in Microsoft Excel (or whatever spreadsheet software is default on Windows).

#### How Desktop File Launching Works:
In web apps, you cannot launch desktop software due to browser sandboxing. In desktop apps, we use the .NET Process API:
```powershell
[System.Diagnostics.Process]::Start($sheetPath)
```
Windows immediately opens the file in the user's default registered program for `.xlsx` (e.g., Microsoft Excel, WPS Office, LibreOffice).

---

### 2.4 Live Metric Binding
When a course workspace is opened:
- The app checks if a registration sheet is attached.
- If attached, it calls `Import-StudentSheet` to count the valid student rows.
- The `TOTAL REGISTERED` metric card on the Dashboard automatically updates from `0` to the real count (e.g. `153`).

---

## 3. The Excel Mystery Explained: Hidden Columns & Timestamps

When testing with the real course sheet (`Introduction to Soft computing NPTEl result May 2026 (Responses).xlsx`), two interesting behaviors surfaced:

### 1. Why Did the App Show "Extra Columns"?
When opened in Microsoft Excel, the sheet only showed 7 columns:
`Timestamp`, `Enrollment Number`, `Name`, `Upload Certificate`, `Final exam marks`, `top 5%`, `top 1%`.

**The Reason:**
In Microsoft Excel, **Columns D, E, F, G, and H** were explicitly marked as **`Hidden = True`** by whoever created the spreadsheet:
- Column D: `Mobile Number` *(Hidden in Excel)*
- Column E: `Subject` *(Hidden in Excel)*
- Column F: `Assignment marks` *(Hidden in Excel)*
- Column G: `Main Exam Marks` *(Hidden in Excel)*
- Column H: `Result` *(Hidden in Excel)*

Because our parser reads raw data directly from the file XML, it revealed all columns. You confirmed: *"keep all columns visible, just format the timestamps."*

### 2. Why Did Timestamps Look Like `46146.7169...`?
In Excel, dates are not stored as strings like `"2026-05-04"`. Excel stores dates as **serial numbers** representing the number of fractional days elapsed since December 30, 1899:
- `46146` = May 4, 2026
- `.71696` = 17:12:26 (5:12 PM)

In .NET / PowerShell, you convert this with:
```powershell
$dateTime = [DateTime]::FromOADate(46146.7169644329)
# Outputs: 5/4/2026 17:12:26
```

---

## 4. The One-Command Startup Trick (`./NPTEL-Manager.ps1`)

In Node.js, you run `npm start` or `node server.js`.  
In Windows PowerShell, scripts are often blocked by **Execution Policies** (`RemoteSigned` or `Restricted`), and WPF requires **STA (Single-Threaded Apartment)** threading.

We solved this completely by adding a self-configuring launcher at the very top of `NPTEL-Manager.ps1`:

```powershell
# 1. Silently bypass execution policy for the current process ONLY (zero admin rights needed)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

# 2. Check if the current terminal is in STA mode (required by WPF)
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    # If not STA, restart itself with -STA and -ExecutionPolicy Bypass flags
    $scriptFile = if ($PSScriptRoot) { Join-Path $PSScriptRoot "NPTEL-Manager.ps1" } else { ".\NPTEL-Manager.ps1" }
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "$scriptFile"
    exit
}
```

Now, whether you type:
```powershell
./NPTEL-Manager.ps1
```
or:
```powershell
.\NPTEL-Manager.ps1
```
It starts immediately with zero errors!

---

## 5. Summary of Files Created / Touched in Branch 2 Session 1

- [`modules/Import-StudentSheet.ps1`](file:///D:/Coding/Project/PDQA%20Project/modules/Import-StudentSheet.ps1): Dedicated parser module for reading `.xlsx` and `.csv` files via `ImportExcel`.
- [`UI/Views/DashboardView.xaml`](file:///D:/Coding/Project/PDQA%20Project/UI/Views/DashboardView.xaml): Added `[Preview Sheet]` and `[Open File]` buttons, plus the full-screen dark DataGrid modal overlay.
- [`NPTEL-Manager.ps1`](file:///D:/Coding/Project/PDQA%20Project/NPTEL-Manager.ps1): Wired process launching, in-app modal preview, live metric counting, process bypass, and STA assurance.
- [`notes/Branch_1(Session_1).md`](file:///D:/Coding/Project/PDQA%20Project/notes/Branch_1%28Session_1%29.md): Web developer notes for Branch 1.
- [`notes/Branch_2(Session_1).md`](file:///D:/Coding/Project/PDQA%20Project/notes/Branch_2%28Session_1%29.md): This notes document.
