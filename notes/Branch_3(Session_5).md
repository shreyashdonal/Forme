# Branch 3 (Session 5) — 1-Click Coordinator Actions, In-App Resubmit Modal & Manual Receipt Attachment

---

## 1) Overview of the Session

In this session, we completed **Phase E (Review & Discrepancy Queue)** by implementing the coordinator decision actions inside [`UI/Views/ReviewView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/ReviewView.xaml):

1. **`[ Approve (Override) ]` Action**: 1-click coordinator approval with confirmation, dual-state persistence (`students.json` and `<CourseName>_Verification_Sheet.xlsx`), Under Review count decrement, and in-place queue advancement.
2. **`[ Flag for Resubmit ]` Workflow**: Custom in-app dark modal overlay (`ModalFlagResubmit`) equipped with 4 one-click preset tags (*Blurry Receipt*, *Wrong Course Name*, *Drive Access Denied*, *Fee Incomplete*) and custom instruction input.
3. **`[ Attach Receipt File... ]` Engine**: Direct local file attachment for students who emailed their receipt PDFs or images out-of-band, copying to the course receipts folder and triggering WinRT Page 1 rasterization with instant viewer refresh.
4. **Export Synchronization Helper (`Export-CourseVerificationSheetData`)**: Modularized the spreadsheet update routine to synchronize student verification statuses and coordinator remarks into the course verification sheet.
5. **Phase E Milestone Complete**: Checked off all items under Phase E in [`Progress.md`](file:///D:/Coding/Project/PDQA%20Project/Project/Progress.md).

---

## 2) The Coordinator Decision Architecture

### 2.1 The Need for Human-in-the-Loop Override

Automated rule engines and OCR are excellent at processing 90%+ of clean submissions rapidly. However, edge cases always occur:
- An official transaction screenshot may have unique Razorpay typography that OCR misread.
- The student paid via an institutional fee waiver or bank NEFT receipt rather than standard Razorpay.
- A slight typo occurred in the course title declared by the student.

The coordinator is the ultimate authority. Without a fast, safe override button, coordinators would have to manually edit spreadsheets or JSON files on disk.

```
                     [ Student Under Review ]
                                │
        ┌───────────────────────┴───────────────────────┐
        ▼                                               ▼
[ Approve (Override) ]                       [ Flag for Resubmit ]
  - Status -> 'Verified'                       - Status -> 'Under Review'
  - Remarks -> 'Manually approved...'          - Opens in-app modal
  - Saves students.json                        - Applies preset / custom note
  - Updates Verification Sheet                 - Saves remarks to Excel & JSON
  - Removes from queue                         - Updates diagnostics panel
```

---

## 3) Implementation Details

### 3.1 1-Click Approve Override (`BtnApproveOverride`)

Located in `ReviewActionsHost` in [`UI/Views/ReviewView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/ReviewView.xaml), styled with `SageBrush` (`#5B8C7B`):

1. **Accidental Click Guard**: Prompts a `MessageBoxButton::YesNo` confirmation showing the student's Name and Roll Number.
2. **State Updates**:
   - `VerificationStatus = "Verified"`
   - `VerificationRemarks = "Manually approved by coordinator on $(Get-Date)"`
3. **Dual Persistence**:
   - Saves directly to `data/Courses/<CourseName>/students.json` via `Save-CourseStudents`.
   - Calls `Export-CourseVerificationSheetData` to update the Excel/CSV verification sheet on disk.
4. **Queue Advancement**:
   - Invokes `Update-ReviewView`, which removes the approved student from the active list.
   - Automatically selects the next student in line; if no students remain, seamlessly transitions to the *"Queue is Clear"* state.

### 3.2 In-App Flag for Resubmission Modal (`ModalFlagResubmit`)

Rather than an unstyled OS message box, we built an integrated WPF modal overlay:

* **Z-Index & Layout**: Positioned with `Grid.RowSpan="2"` and `Margin="-32,-24,-32,-24"` with a semi-transparent backdrop (`#CC151513`), focusing the coordinator's attention on the card.
* **4 Quick-Click Preset Reasons**:
  * **Blurry Receipt**: *"Receipt image is blurry or unreadable. Please upload a clear photo/PDF of your payment receipt."*
  * **Wrong Course Name**: *"Payment receipt course title does not match your enrolled course. Please upload the receipt for this specific course."*
  * **Drive Access Denied**: *"Google Drive access is restricted (403 Forbidden). Please set link sharing to 'Anyone with the link can view'."*
  * **Fee Incomplete**: *"Receipt does not show the standard NPTEL exam fee (Rs 1,000 / Rs 1,100) or payment confirmation is missing."*
* **Custom Instructions**: A multi-line dark `TextBox` allowing custom explanations.
* **Instant Feedback**: Clicking **Flag Student** writes the note to the student record, saves to disk, updates the verification sheet, hides the modal, and refreshes the diagnostics display.

### 3.3 Manual Receipt Attachment (`BtnAttachLocalReceipt`)

When a student emails their receipt directly to the coordinator instead of re-filling the form:
1. **Interactive Functional Card**: Redesigned the manual attachment panel with active `#1C2420` dark sage styling, a bold `ACTION` tag badge, and prominent `[ Attach & Verify Receipt... ]` button.
2. **Safe Staging (Data Loss Prevention)**:
   - When a file is chosen, the old receipt is **not deleted immediately**.
   - The incoming file is staged in a temporary path (`<RollNo>_staged.<ext>`).
   - If a PDF, Page 1 is rasterized to PNG via WinRT.
3. **Automated 5-Rule OCR Check**:
   - The engine automatically runs OCR extraction on the staged receipt and evaluates all 5 rules (payment status, fee threshold, course title, Razorpay/NPTEL authenticity, student greeting).
4. **Auto-Approval Flow**:
   - If all 5 rules pass, a confirmation dialog appears detailing the matched rules and asking: *"All 5 rules matched! Would you like to approve this student now?"*
   - Clicking **`[ Yes ]`**: Purges the old receipt, promotes the new verified receipt, marks the student `Verified`, updates `students.json` and Excel, and advances the queue.
   - If OCR detects discrepancies: Informs the coordinator of the exact issues, and gives the option to keep the new file for manual inspection or keep the previous receipt intact.

---

## 4) Summary of Changes & File Matrix

| Component | File | Key Additions / Responsibilities |
|---|---|---|
| **Review View** | [`UI/Views/ReviewView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/ReviewView.xaml) | Added `BtnApproveOverride`, `BtnFlagResubmit`, active functional action card for `BtnAttachLocalReceipt` with sage accent styling, and `ModalFlagResubmit` with 4 preset tag buttons and text input; cleaned non-ASCII symbols. |
| **Verification Engine** | [`modules/VerificationEngine.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/modules/VerificationEngine.ps1) | Added `Export-CourseVerificationSheetData` helper to keep the Excel verification sheet synchronized when individual statuses or remarks change. |
| **OCR Engine** | [`modules/OcrEngine.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/modules/OcrEngine.ps1) | Added `[switch]$Force` parameter to `ConvertTo-ReceiptImage` to support force-rasterizing newly staged PDF receipts. |
| **Main Controller** | [`NPTEL-Manager.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/NPTEL-Manager.ps1) | Bound tags in `Show-StudentReviewDetails`; wired `BtnApproveOverride` with confirmation and queue advance; wired `BtnFlagResubmit` and modal controls; wired `BtnAttachLocalReceipt` with safe file staging, automated 5-rule OCR, safe old-file purge only on approval, and instant viewer reload. |
| **Session Notes** | [`notes/Branch_3(Session_5).md`](file:///D:/Coding/Project/PDQA%20Project/Project/notes/Branch_3%28Session_5%29.md) | Comprehensive educational documentation for Session 5. |
| **Progress Tracker** | [`Progress.md`](file:///D:/Coding/Project/PDQA%20Project/Project/Progress.md) | Checked off Phase E Items 3 & 4 (completing Phase E), recorded Session 5 log, and set Phase F as the next target. |

---

## 5) Bug Fixes & Resiliency Enhancements

During testing of the `[ Attach & Verify Receipt... ]` workflow, two runtime edge-cases were caught and resolved:

1. **`ConvertTo-ReceiptImage` `-Force` parameter**: Added `[switch]$Force` to `ConvertTo-ReceiptImage` in [`modules/OcrEngine.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/modules/OcrEngine.ps1) to allow bypassing cached PNGs when re-rasterizing newly staged PDF receipts.
2. **`Get-ReceiptText` Term Resolution**:
   - The native OCR engine function in `OcrEngine.ps1` was named `Invoke-ReceiptOcr`.
   - Added an explicit `Get-ReceiptText` compatibility wrapper to [`modules/OcrEngine.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/modules/OcrEngine.ps1) that forwards to `Invoke-ReceiptOcr`.
   - Updated [`NPTEL-Manager.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/NPTEL-Manager.ps1) to call `Invoke-ReceiptOcr` directly and added dynamic module availability guards for `Invoke-ReceiptOcr` and `Test-ReceiptVerificationRules`.
   - Verified OCR execution against real receipts in PowerShell (`Success: True`, line extraction confirmed).
3. **WPF Image File Lock & Alphabetical Selection Trap**:
   - *Problem*: Previously, the viewer loaded images via `BitmapImage.UriSource = New-Object Uri($filePath)`. In Windows .NET Framework, WPF holds an open unmanaged file handle on the file as long as the UI displays it. When attaching a new receipt, `Remove-Item ... -ErrorAction SilentlyContinue` failed silently due to this file lock.
   - *Extension Trap*: When a student had an existing `.jpeg` or `.pdf` and a `.png` was attached, the new file was created alongside the old one. Because the lookup used `Get-ChildItem -Filter "${cleanRoll}_receipt.*" | Select-Object -First 1`, it sorted alphabetically. Since `.jpeg` precedes `.png`, the viewer kept loading the old `.jpeg`!
   - *Solution*: Replaced `UriSource` with `[System.IO.File]::ReadAllBytes` loaded into a `System.IO.MemoryStream`. The file on disk is opened, read into memory in under 2 milliseconds, and immediately closed. Updated receipt replacement to delete **all files matching `${cleanRoll}_receipt*` across all extensions** (`.pdf`, `.jpeg`, `.png`, `_page1.png`). Added `Sort-Object LastWriteTime -Descending` so the newest file is always selected.
4. **`Bug1.png`: `ArgumentNullException` on `StreamSource` with `IgnoreImageCache`**:
   - *Problem*: When `BitmapCreateOptions.IgnoreImageCache` was passed alongside `StreamSource` in `Show-StudentReviewDetails`, WPF called `ImagingCache.RemoveFromCache(Uri uri, Hashtable table)`. Because the image was decoded from a RAM stream (with no URI), `uri` was `$null`, causing `EndInit()` to throw `System.ArgumentNullException: Key cannot be null. Parameter name: key`. This triggered the error catch block, rendering the *"Receipt File Not Available"* placeholder seen in `Bug1.png`.
   - *Solution*: Removed `IgnoreImageCache` from the stream decoder. Memory streams decode directly from byte arrays in RAM and do not use WPF's internal URI cache table anyway. Verified live rendering in PowerShell (`Loaded: True`, `PixelWidth: 2000`, `PixelHeight: 2830`).
   - *Viewport UX*: Named `ReviewDetailsScrollViewer` and added `ScrollToTop()` on student selection so the **Verification Diagnostics** box is never obscured when switching students.


---

## 6) Session Review Mini Dashboard & Staged Push Workflow (Coordinator Sketch Implementation)

Based on the coordinator's hand-drawn UI concept (`UI.jpeg`), the Under Review workflow was transformed into a high-throughput, 2-mode system with an in-session progress tracker and staged push synchronization:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ REVIEW PROGRESS MINI DASHBOARD                                                         │
│  [ TOTAL ISSUES: X ]    [ SOLVED IN THIS SESSION: Y ]    [ PENDING: Z ]                │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ [ 🚀 Push Changes to Main Sheet ]  ● Y changes ready to push                           │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ REVIEW QUEUE TABLE (Mode A)                                                            │
│  ENROLLMENT      NAME (hover for remarks)           QUICK ACTIONS (Auto width)         │
│  0801cs221109    Praveen Agariya                    [Issues] [Receipt] [Approve] [Open]│
└────────────────────────────────────────────────────────────────────────────────────────┘
                                                                     │
                                                                     ▼ [ Open Student ]
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ STUDENT DETAIL INSPECTION WORKSPACE (Mode B)                                           │
│  [ ← Back to Queue ]  Praveen Agariya (0801cs221109)      [Flag Resubmit] [Approve]    │
│  Diagnostics & Details (Left)             Zoomable Receipt Image Viewer (Right)        │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### 6.1 Two Clean Layout Modes
1. **Mode A — Review Queue Overview Panel (`ReviewQueueOverviewPanel`)**:
   - Displays the 3-metric progress mini dashboard (`TxtReviewTotalIssues`, `TxtReviewSolvedCount`, `TxtReviewPendingCount`).
   - Action bar with `[ Push Changes to Main Sheet ]` and dynamic status badge (`TxtPushChangesBadge`).
   - 3-Column Review Queue Table host (`ReviewRowsHost`): `ENROLLMENT` (Width 200, mono), `STUDENT NAME` (Width *, with full issues tooltip), and `QUICK ACTIONS` (Width Auto, preventing badge clipping).
2. **Mode B — Student Detail Inspection Workspace (`ReviewStudentDetailPanel`)**:
   - Full split-screen inspection workspace focused on the selected student.
   - Prominent `[ ← Back to Queue ]` button (`BtnBackToQueueTable`) to immediately return to the overview table.

### 6.2 The 4 Quick Actions per Row
- **`[ Issues ]`**: Displays a message box detailing OCR discrepancy breakdown and verification failure remarks.
- **`[ Receipt ]`**: Automatically detects the student's saved receipt file on disk (`.pdf`, `.png`, `.jpeg`) and opens it in the Windows default application.
- **`[ Approve ]`**: 1-click quick-approval that stages the student as solved in session memory, updates the row to a green `✓ Solved (Ready to Push)` badge, and enables the Push button.
- **`[ Open Student ]`**: Switches view to Mode B for complete split-screen review, manual receipt replacement, and resubmission modal access.

### 6.3 Staged Push Synchronization (`BtnPushSolvedChanges`)
- Solved students are staged in `$script:reviewStagedSolved` rather than immediately rewriting the Excel sheet on each individual click.
- When the coordinator clicks `[ Push Changes to Main Sheet ]`:
  1. All staged students are committed to `data/Courses/<CourseName>/students.json`.
  2. The course verification spreadsheet (`<CourseName>_Verification_Sheet.xlsx`) is synchronized via `Export-CourseVerificationSheetData`.
  3. Stage 1 verification panel counters are updated in the background (`Under Review` decrements, `Verified` increments).
  4. Staged changes are cleared and the queue is refreshed.
- A safety prompt on `[ ← Back to Stage 1 ]` warns coordinators if unpushed changes are staged.

---

## 6.1) Toggleable Approval (`[ Approve ]` ⇄ `[ Unapprove ]`) & Badge Streamlining

### Problem Solved
1. **Vanishing Action Button**: Previously, clicking `[ Approve ]` in the row quick actions completely removed the button, leaving coordinators without a quick mechanism to undo an accidental click or revert an approval prior to pushing changes to the main sheet.
2. **Badge Text & Clipping**: The previous badge text `✓ Solved (Ready to Push)` was verbose and could suffer from visual clutter. The user requested simplifying the badge to strictly **`Solved`** (no checkmark, no extra text).
3. **Table Column Streamlining**: The table was streamlined from 4 columns to 3 clean columns: `ENROLLMENT` (200), `STUDENT NAME` (*, with hover tooltip displaying issues), and `QUICK ACTIONS` (`Width="Auto"`, right-aligned). The first action button was also renamed from `Diagnostics` to `Issues`.

### Implementation Details
1. **Dynamic Button State**:
   - When a student is pending: Button 3 renders as **`[ Approve ]`** (Sage green CTA).
   - When clicked: The student's current status and remarks are cached (`OriginalStatus`, `OriginalRemarks`), status becomes `"Verified"`, and the student is staged in `$script:reviewStagedSolved`.
   - In-place row refresh transforms Button 3 into **`[ Unapprove ]`** (`BtnSecondary`, Danger border/text).
   - Clicking `[ Unapprove ]` presents a confirmation prompt, removes the entry from `$script:reviewStagedSolved` and `$script:reviewSessionSolvedRolls`, restores `$targetSt.VerificationStatus` and `$targetSt.VerificationRemarks`, and updates the queue.
2. **Simplified Badge**:
   - Rendered as `<TextBlock Text="Solved" .../>` styled with SageBrush / SageTintBrush.
   - 0 non-ASCII characters, 0 Unicode checkmark tokens.
3. **Width="Auto" Prevention of Clipping**:
   - Column 2 is set to `Width="Auto"`, guaranteeing that badge + action buttons always fit comfortably without edge clipping.
4. **Primary Heading Typography Polish**:
   - Upgraded the page title `"Review Submissions with Issues"` from monospaced (`IBM Plex Mono, Consolas`, 22pt, Medium) to modern clean sans-serif (`Segoe UI, Inter, sans-serif`, 26pt, SemiBold, `#FFFFFF`) to give it prominent visual hierarchy and an unmistakable page title presence.

---

## 7) Next Scheduled Milestone

* **Phase F — Filtered Student Roster & Export (`StudentListView.xaml`)**:
  - Connect Mini Dashboard cards (`[ VERIFIED ]`, `[ UNDER REVIEW ]`, `[ DID NOT REGISTER ]`) to navigate to `StudentListView.xaml`.
  - Implement 4 filter tabs: `[ All ]`, `[ Verified ]`, `[ Under Review ]`, `[ Did Not Register ]`.
  - Add search filter by Roll Number or Student Name.
  - Add `[ Export College Verification List (CSV) ]` for official academic cell reporting.


