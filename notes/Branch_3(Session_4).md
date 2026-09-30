# Branch 3 (Session 4) — Review Workspace, Decoupled Pipeline, Resubmission De-Duplication & "Update Sheet" Engine

---

## 1) Overview of the Session

In this session, we advanced **Phase E (Review & Discrepancy Queue)** and engineered three critical architectural improvements to solve real-world campus registration dilemmas:

1. **Review Queue Navigation & Split-Screen Workspace (Phase E Items 1 & 2)**:
   - Wired the Stage 1 `UNDER REVIEW` metric card to dynamically route to [`UI/Views/ReviewView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/ReviewView.xaml).
   - Built a 2-column split-screen workspace featuring student registration metadata & OCR rule diagnostics on the left, and a zoomable, hardware-accelerated receipt viewer on the right.
2. **Safe Course Deletion Workflow (Extra / Ad-Hoc Task)**:
   - Implemented `Remove-Course` with explicit coordinator confirmation, database updates (`data/courses.json`), cache cleanup (`data/Courses/<CourseName>`), and active state invalidation.
3. **Decoupled 2-Step Verification Pipeline (Extra / Ad-Hoc Task)**:
   - Decoupled receipt downloading from OCR verification to isolate network I/O, Google Drive rate limits, and 403 sharing permission issues from local OCR processing.
   - Added dedicated `[ 📥 Download Receipts ]` and `[ ▶ Run Verification (OCR) ]` actions with on-disk cache tracking (`Receipts on disk: X / Y`).
4. **The Resubmission Problem & The "Update Sheet" Engine (Extra / Ad-Hoc Task)**:
   - Solved the duplicate submission problem where students flagged under review re-submit the Google Form, creating duplicate rows in the spreadsheet.
   - Implemented automated de-duplication (latest timestamp wins), automatic stale receipt cache purging, and replaced confusing "Replace Sheet" / "Sync" buttons with a single unified **"Update Sheet"** workflow.
5. **Windows PowerShell 5.1 Cross-Version Hardening**:
   - Eliminated non-ASCII Unicode crashes, fixed AST parser traps (`if` expressions inside method calls), and hardened WPF event button closure scoping.

---

## 2) Review Queue Architecture & Hub-and-Spoke Routing

### 2.1 The Coordinator Workflow

During registration audits, the 5-rule verification engine flags records with discrepancies (e.g. fee payment missing, course code mismatch, or identity greeting mismatch). These students are marked as `Under Review`.

Clicking the `UNDER REVIEW` mini-dashboard card on Stage 1 navigates to a dedicated review workspace:

```
[ Stage 1 Dashboard ] 
       │
       ▼ (Clicks "UNDER REVIEW" Card)
[ ReviewView.xaml ]
   ├── Left Column: Flagged Student Queue (<ReviewItemsListHost>)
   └── Right Column: Split-Screen Detail Workspace (<ReviewWorkspaceGrid>)
       │
       ▼ (Clicks "← Back to Stage 1")
[ Stage 1 Dashboard ] (Instant metric & state synchronization)
```

### 2.2 Web Dev Parallel (Master-Detail Route Pattern)

In modern web development (React / Next.js / Vue), this represents the classic **Master-Detail (Split View)** pattern:

```tsx
// React / Web Dev equivalent
<div className="review-layout flex">
  <aside className="queue-sidebar w-1/3">
    <ReviewQueueList 
      items={students.filter(s => s.status === 'Under Review')} 
      selectedId={activeStudent?.rollNo}
      onSelect={(student) => setActiveStudent(student)} 
    />
  </aside>

  <main className="detail-workspace w-2/3">
    {activeStudent ? (
      <SplitScreenReview 
        student={activeStudent}
        receiptViewer={<ZoomableReceiptViewer src={activeStudent.receiptUrl} />}
      />
    ) : (
      <EmptySelectionPlaceholder message="Select a student from the queue" />
    )}
  </main>
</div>
```

---

## 3) Split-Screen Review Workspace Implementation

### 3.1 Two-State Detail Container

In [`UI/Views/ReviewView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/ReviewView.xaml), `ReviewDetailsContainer` encapsulates two mutual visibility states:

* **State A — `ReviewDetailsPlaceholder` (`Visibility="Visible"` initially)**:
  Shows an informative empty state (*"No Submission Selected"*) when the queue is clear or no student has been clicked yet.
* **State B — `ReviewWorkspaceGrid` (`Visibility="Collapsed"` initially)**:
  Revealed as soon as a student card is clicked (or auto-selected).

### 3.2 Left Sub-Column: Student Details & Diagnostics

Displays administrative records read directly from `data/Courses/<CourseName>/students.json`:
* **Student Identity**: Full Name, Roll Number, and `[ UNDER REVIEW ]` badge in warm amber (`#E8B04B`).
* **Verification Diagnostics Panel**: Renders the exact rule mismatch recorded by the verification engine (e.g., *"Fee amount mismatch: detected ₹0 instead of ₹1,000"*, *"Course title not matched"*).
* **Registration Metadata**: Enrolled email, subject title, registration declaration status, submission timestamp, and Google Drive URL with a direct `[ 🌐 Open Drive Link ]` launcher.

### 3.3 Right Sub-Column: Zoomable Receipt Viewer

Displays the student's payment receipt image inside a scrollable and scalable canvas:

* **WPF `ScaleTransform` Engine**:
  ```xml
  <ScrollViewer x:Name="ReceiptScrollViewer" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto">
      <Grid HorizontalAlignment="Center" VerticalAlignment="Center">
          <Image x:Name="ReceiptImage" Stretch="None" RenderOptions.BitmapScalingMode="HighQuality">
              <Image.LayoutTransform>
                  <ScaleTransform x:Name="ReceiptZoomScale" ScaleX="1.0" ScaleY="1.0"/>
              </Image.LayoutTransform>
          </Image>
      </Grid>
  </ScrollViewer>
  ```
* **Toolbar Controls**:
  * `BtnZoomIn` (`＋`): Multiplies `ScaleX` and `ScaleY` by `1.25x` (capped at 400%).
  * `BtnZoomOut` (`－`): Divides `ScaleX` and `ScaleY` by `1.25x` (floored at 25%).
  * `BtnZoomFit` (`Fit`): Resets scale to `1.0x` (`100%`).
  * `BtnOpenReceiptFile` (`↗ Open File`): Launches the local image or PDF in the default Windows photo or document viewer via `ProcessStartInfo.UseShellExecute = $true`.
* **Zero-Lag PDF Rasterization**:
  If the downloaded receipt is a PDF document, [`ConvertTo-ReceiptImage`](file:///D:/Coding/Project/PDQA%20Project/Project/modules/OcrEngine.ps1) automatically converts Page 1 to a high-resolution PNG using Windows WinRT `Windows.Data.Pdf`. Subsequent views load instantly from the cached `*_page1.png`.
* **Memory & File Lock Protection**:
  To prevent file-locking errors if the user deletes or syncs files while reviewing:
  ```powershell
  $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
  $bmp.BeginInit()
  $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
  $bmp.UriSource = New-Object System.Uri($displayImgPath, [System.UriKind]::Absolute)
  $bmp.EndInit()
  $bmp.Freeze() # Makes bitmap immutable and releases underlying file handle
  $imgReceipt.Source = $bmp
  ```
* **Graceful Missing Receipt Fallback**:
  If the receipt is not found locally, the viewer shows `ReceiptMissingPlaceholder` with an alert and an on-demand `[ ⬇ Try Downloading Receipt ]` button that downloads the single student's file directly without re-downloading the entire class.

---

## 4) Safe Course Deletion Workflow

### 4.1 Problem Addressed

As courses accumulate across semesters or test registrations are created, coordinators need a clean way to remove a course without leaving orphaned files or corrupting application state.

### 4.2 The Solution (`Remove-Course`)

Implemented `Remove-Course` in [`NPTEL-Manager.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/NPTEL-Manager.ps1):

1. **Explicit Coordinator Confirmation**: Prompts a `MessageBoxButton::YesNo` warning confirming the operation and reassuring that original Excel spreadsheets on disk remain untouched.
2. **State & Database Persistence**: Filters the course out of `$script:courses` and writes back to `data/courses.json`.
3. **Active Course Invalidation**: If the deleted course is currently loaded in memory (`$script:activeCourse`), it resets to `$null` and restores the shell header status to *"No Course Active"*.
4. **Local Cache Purge**: Recursively deletes `data/Courses/<CourseName>` containing cached receipts and `students.json`.
5. **UI Synchronization**: Calls `Refresh-CourseLists` to update the library cards and navigate back to `CoursesView` if the coordinator was inside that course's workspace.

---

## 5) Decoupled 2-Step Verification Pipeline

### 5.1 The Dilemma: Network Latency vs Local OCR

In earlier versions, clicking `[ ▶ Verify All (OCR) ]` triggered both downloading and OCR in a single monolithic pass:
- If 50 students were registered, the coordinator was forced to wait for network downloads before seeing any verification progress.
- If Google Drive returned HTTP 403 (restricted access), the entire verification pipeline threw errors or required re-running from scratch.
- If receipts were already downloaded on disk, re-running verification unnecessarily re-contacted Google servers.

### 5.2 The 2-Step Decoupled Solution

We decoupled the workflow into two independent, observable steps:

```
[ Step 1: Download Receipts ] ────▶ Local Cache: data/Courses/<Course>/receipts/
                                             │
                                             ▼
[ Step 2: Run Verification (OCR) ] ◀── Fast Offline Local Processing
```

1. **Step 1: Dedicated Downloader (`BtnDownloadReceipts`)**:
   - Calls `Download-CourseReceipts` with detailed per-file status.
   - Diagnoses Google Drive permission errors (HTTP 403 Forbidden) and gives clear coordinator instructions:
     > *"Some receipts could not be downloaded. Google Drive link has restricted access. Ask student to change sharing settings to 'Anyone with the link'."*
2. **Step 2: Fast Offline OCR (`BtnVerifyAll`)**:
   - Inspects the local `receipts/` directory before starting.
   - If receipts are already cached on disk, it prompts the coordinator and passes `-SkipDownload:$true` to `Invoke-CourseVerificationPipeline`.
   - OCR runs at maximum local CPU speed without any network latency.
3. **Live Cache Counter (`TxtPipelineStatus`)**:
   - Displays real-time disk cache health: `Receipts on disk: 6 / 6 ready for verification`.

---

## 6) The Student Resubmission Dilemma & The "Update Sheet" Engine

### 6.1 The Real-World Campus Problem

In university NPTEL coordination:
1. Student **A** submits a registration form with a blurry receipt or wrong PDF link.
2. The verification engine flags student **A** as `Under Review`.
3. The coordinator contacts the student or asks them to re-upload the receipt via Google Form.
4. **Google Forms Behavior**: Google Forms creates a **brand-new second row** at the bottom of the spreadsheet with a new timestamp and updated Google Drive link; it rarely edits the existing row.
5. **The Technical Dilemma**:
   - If the spreadsheet contains two rows for the same Roll Number, which row takes priority?
   - If the system re-runs OCR, how do we guarantee it doesn't inspect the old cached blurry receipt stored on disk?
   - How does the coordinator update their registration data without confusing separate "Replace Sheet" and "Sync Responses" buttons?

### 6.2 The De-Duplication & Cache Purge Rule

We introduced two foundational rules in [`modules/Import-StudentSheet.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/modules/Import-StudentSheet.ps1) and [`modules/VerificationEngine.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/modules/VerificationEngine.ps1):

1. **Latest Submission Wins (Chronological De-Duplication)**:
   - When importing the spreadsheet, rows are mapped by `RollNo` (case-insensitive, fallback to `Email`).
   - If duplicate rows exist for the same student, later rows (newest submissions from Google Forms) overwrite earlier entries:
     ```powershell
     if ($studentMap.ContainsKey($key)) {
         $duplicateCount++
         $supersededRolls.Add($key) | Out-Null
     }
     $studentMap[$key] = $student
     ```
2. **Automated Stale Receipt Purging**:
   - In `Sync-CourseResponses`, when an existing student's `ProofUrl` has changed in the updated sheet:
     1. The system locates all existing receipt files matching `<RollNo>_receipt.*` in `data/Courses/<CourseName>/receipts/`.
     2. Deletes the old PDF and rendered PNG images from disk.
     3. Resets the student's status to `Pending` and clears stale OCR remarks.
     4. This guarantees that Step 1 (`Download Receipts`) downloads the **new** receipt file, and Step 2 (`Verify All`) scans the **new** image.

### 6.3 Unified Coordinator UX: "Update Sheet"

Previously, the UI had two competing buttons:
- `[ 📁 Replace Sheet ]` (which changed the file path)
- `[ 🔄 Sync Responses ]` (which re-scanned the file path)

This confused coordinators. We replaced both with a single, clear **`[ Update Sheet ]`** action:
- Clicking `[ Update Sheet ]` displays a smart choice dialog:
  - **Yes**: Re-scans the currently linked spreadsheet (perfect when Google Sheets auto-syncs or exports to the same file path).
  - **No**: Opens the Windows file dialog to browse for a new / updated spreadsheet file.
- After processing, a comprehensive report dialog is shown:
  ```
  Update Complete!
  
  Updated from sheet: 6 students parsed (0 new, 1 updated).
  Superseded duplicates: 1 duplicate submissions replaced with latest entries.
  
  Old receipts purged: 1 outdated receipt files removed for resubmitted students.
  ```

---

## 7) Windows PowerShell 5.1 Cross-Version Engineering Lessons

### 7.1 The Non-ASCII / ANSI 1252 Trap

* **The Problem**: When PowerShell 5.1 runs a `.ps1` script via `powershell.exe -File script.ps1`, it decodes the file using the local Windows ANSI codepage (Windows-1252 on Western Windows) unless a UTF-8 BOM is present.
* Multi-byte UTF-8 emojis (`📥`, `▶`, `⚠️`, `•`, `──`) caused parser crashes:
  ```
  Unexpected token '¥' in expression or statement.
  The string is missing the terminator: '.
  ```
* **The Rule**: Keep `.ps1` scripts **100% clean ASCII**. Use standard ASCII characters in script code. Where symbols are needed in WPF XAML, use standard text or XML character entities.

### 7.2 Method Argument Parsing Syntax Trap

* **The Problem**: In PowerShell 5.1, passing an inline conditional expression `(if (...) { ... } else { ... })` directly inside a .NET method call:
  ```powershell
  # FAILS in PowerShell 5.1:
  [System.Windows.MessageBox]::Show("...", "Title", [MessageBoxButton]::OK, (if ($err) { [MessageBoxImage]::Warning } else { [MessageBoxImage]::Information }))
  ```
  Causes PowerShell to parse `if` as a cmdlet/command invocation, producing:
  `The term 'if' is not recognized as the name of a cmdlet, function, script file...`
* **The Solution**: Always evaluate conditional method parameters outside the method call into a local variable first:
  ```powershell
  $msgIcon = if ($duplicateCount -gt 0) { [System.Windows.MessageBoxImage]::Warning } else { [System.Windows.MessageBoxImage]::Information }
  [System.Windows.MessageBox]::Show($msgText, "Update Status", [System.Windows.MessageBoxButton]::OK, $msgIcon)
  ```

### 7.3 WPF Scriptblock Closure & Dynamic Scoping

* **The Problem**: In PowerShell WPF applications, closures over local script variables can evaluate to `$null` when an event fires long after the enclosing function has completed.
* **The Solution**: Always retrieve controls dynamically at event runtime using `$script:views["<ViewName>"].FindName("...")` or the dynamic sender `$this`, and null-guard property writes.

### 7.4 PSCustomObject Fixed Property Set Trap

* **The Problem**: When a `[PSCustomObject]` is initialized via `[PSCustomObject]@{ Key = Val }`, PowerShell instantiates a fixed set of `NoteProperty` members. Attempting to assign to a new property later (e.g. `$result.DuplicateCount = $duplicateCount`) throws a fatal runtime exception:
  ```
  Exception setting "DuplicateCount": The "property 'DuplicateCount' cannot be found on this object. Verify that the property exists and can be set."
  ```
* **The Solution**: Always declare all expected return properties in the initial hashtable definition (e.g., `DuplicateCount = 0`, `SupersededRolls = @()`), ensuring every property can be written without throwing runtime property set errors.

---

## 8) Summary of Changes & File Matrix

| Component | File | Key Additions / Responsibilities |
|---|---|---|
| **Student Sheet Parser** | [`modules/Import-StudentSheet.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/modules/Import-StudentSheet.ps1) | Added ordered de-duplication mapping by `RollNo`/`Email` (latest row wins), tracking `DuplicateCount` and `SupersededRolls`. |
| **Verification Engine** | [`modules/VerificationEngine.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/modules/VerificationEngine.ps1) | Added `[switch]$SkipDownload` for fast offline OCR; updated `Sync-CourseResponses` to de-duplicate rows and automatically purge old cached receipt files for resubmitted students. |
| **Stage 1 View** | [`UI/Views/Stage1View.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/Stage1View.xaml) | Built 2-step verification bar (`BtnDownloadReceipts`, `BtnVerifyAll`, `TxtPipelineStatus`); replaced separate Replace/Sync with unified `BtnUpdateSheet`. |
| **Dashboard Fallback** | [`UI/Views/DashboardView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/DashboardView.xaml) | Aligned legacy/fallback controls with `BtnDownloadReceipts` and `BtnUpdateSheet`. |
| **Review View** | [`UI/Views/ReviewView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/ReviewView.xaml) | Added `TxtReviewBreadcrumb`, `BtnBackToStage1`, and `ReviewWorkspaceGrid` with split-screen student details & zoomable receipt viewer. |
| **Main Controller** | [`NPTEL-Manager.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/NPTEL-Manager.ps1) | Wired `BtnDownloadReceipts` with Google Drive permission advice; added on-disk receipt check and offline OCR to `BtnVerifyAll`; wired unified `BtnUpdateSheet` with choice prompt; cleaned all non-ASCII characters; fixed PS 5.1 method argument syntax bugs. |
| **Project Tracking** | [`Progress.md`](file:///D:/Coding/Project/PDQA%20Project/Project/Progress.md) | Logged Phase E Items 1 & 2, Decoupled 2-Step Pipeline, and Smart Resubmission & "Update Sheet" Workflow under Extra Tasks. |

---

## 9) Next Scheduled Milestone

* **Phase E — Item 3**: Implement 1-click coordinator actions: `[ Approve Override ]` and `[ Flag for Resubmit ]` in [`UI/Views/ReviewView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/ReviewView.xaml).
