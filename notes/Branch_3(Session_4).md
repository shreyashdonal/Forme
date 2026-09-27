# Branch 3 (Session 4) — Review Queue Navigation, Split-Screen Workspace & Safe Course Deletion

---

## 1) Overview of the Session

In this session, we commenced **Phase E (Review & Discrepancy Queue)** and also implemented an ad-hoc **Course Deletion Workflow**:

1. **Review Queue Navigation (Phase E Item 1)**: Wired the Stage 1 `UNDER REVIEW` mini-dashboard card to dynamically route to [`UI/Views/ReviewView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/ReviewView.xaml), populating a live queue of flagged submissions with zero dummy data.
2. **Split-Screen Review Workspace (Phase E Item 2)**: Replaced the static right-hand placeholder with an interactive 2-state split-screen workspace displaying student registration metadata & verification diagnostics on the left, and a zoomable payment receipt viewer on the right.
3. **Course Deletion Workflow (Extra / Ad-Hoc Task)**: Added safe course deletion (`Remove-Course`) with confirmation prompts, cache directory cleanup, active course state reset, and delete action buttons in both the [`CoursesView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/CoursesView.xaml) card and [`WorkspaceView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/WorkspaceView.xaml) header.

---

## 2) Review Queue Architecture & Hub-and-Spoke Routing

### 2.1 The Coordinator Workflow

During registration audits, the 5-rule verification engine flags records that have discrepancies (e.g. fee payment missing, course code mismatch, or identity greeting mismatch). These students are placed in the `Under Review` status.

Previously, clicking the `UNDER REVIEW` card on the Stage 1 dashboard showed a placeholder popup. In this session, it was converted into a live router:

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

In web frameworks like React or Vue, this is the classic **Master-Detail (Split View)** pattern:

```tsx
// React / Web Dev equivalent
<div className="review-layout">
  <aside className="queue-sidebar">
    <ReviewQueueList 
      items={students.filter(s => s.status === 'Under Review')} 
      selectedId={activeStudent.id}
      onSelect={(student) => setActiveStudent(student)} 
    />
  </aside>

  <main className="detail-workspace">
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
  Shows an informative empty state (*"No Submission Selected"*) with academic instructions when the queue is clear or no student has been clicked yet.
* **State B — `ReviewWorkspaceGrid` (`Visibility="Collapsed"` initially)**:
  Revealed as soon as a student card is clicked (or auto-selected).

### 3.2 Sub-Column 1: Student Information & Diagnostics (Left)

Displays comprehensive administrative records read from `data/Courses/<CourseName>/students.json`:
* **Student Identity**: Full Name, Roll Number, and `[ UNDER REVIEW ]` status badge in warm amber (`#E8B04B`).
* **Verification Diagnostics Panel**: Renders the exact rule mismatch recorded by the verification engine (e.g., *"Fee amount mismatch: detected ₹0 instead of ₹1,000"*, *"Course title not matched"*).
* **Registration Metadata**: Enrolled email, subject title, registration declaration status, submission timestamp, and Google Drive URL with a direct `[ 🌐 Open Drive Link ]` launcher.

### 3.3 Sub-Column 2: Zoomable Receipt Viewer (Right)

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

1. **Explicit Coordinator Confirmation**:
   Prompts a `MessageBoxButton::YesNo` warning confirming the operation and reassuring that original Excel spreadsheets on disk remain untouched.
2. **State & Database Persistence**:
   Filters the course out of `$script:courses` and writes back to `data/courses.json`.
3. **Active Course Invalidation**:
   If the deleted course is currently loaded in memory (`$script:activeCourse`), it resets to `$null` and restores the shell header status to *"No Course Active"*.
4. **Local Cache Purge**:
   Recursively deletes `data/Courses/<CourseName>` containing cached receipts and `students.json`.
5. **UI Synchronization**:
   Calls `Refresh-CourseLists` to update the library cards and navigate back to `CoursesView` if the coordinator was inside that course's workspace.

### 4.3 Action Touchpoints

* **Course Card Level**: `[ Delete Course ]` button placed on the bottom-left of each card in [`CoursesView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/CoursesView.xaml), styled with `DangerBrush` (`#E24B4A`).
* **Workspace Header Level**: `[ Delete Course ]` button placed in the top-right header of [`WorkspaceView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/WorkspaceView.xaml).

---

## 5) Summary of Changes & File Matrix

| Component | File | Key Additions / Responsibilities |
|---|---|---|
| **Review View** | [`UI/Views/ReviewView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/ReviewView.xaml) | Added `TxtReviewBreadcrumb`, `BtnBackToStage1`, dynamic `ReviewWorkspaceGrid` with 2 sub-columns (details & diagnostics on left, zoomable image canvas with toolbar on right), and empty fallback state. |
| **Workspace View** | [`UI/Views/WorkspaceView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/WorkspaceView.xaml) | Wrapped title in header Grid and added `BtnDeleteCourseFromWorkspace` button. |
| **Controller & Router** | [`NPTEL-Manager.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/NPTEL-Manager.ps1) | Implemented `Open-ReviewView`, `Update-ReviewView`, `Show-StudentReviewDetails` with `BitmapImage` freeze, zoom controls, missing receipt download, and `Remove-Course` with full confirmation and cascade cleanup. |
| **Tracking** | [`Progress.md`](file:///D:/Coding/Project/PDQA%20Project/Project/Progress.md) | Checked off Phase E Items 1 & 2, recorded Course Deletion under Extra Tasks, and updated Session 4 log. |

---

## 6) Next Scheduled Milestone

* **Phase E — Item 3**: Implement 1-click coordinator actions: `[ Approve Override ]` and `[ Flag for Resubmit ]`.
