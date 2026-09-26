# Branch 3 (Session 3) — Stage-Based Workspace Redesign, Multi-Page Router & Navigation Hardening

---

## 1) Architectural Shift: From Monolithic Dashboard to Stage-Based Workspace

### 1.1 The Problem

Previously, [`UI/Views/DashboardView.xaml`](file:///D:/Coding/Project/PDQA%20Project/Project/UI/Views/DashboardView.xaml) was a single monolithic file of over 700 lines. It stacked everything into one long, overwhelming scrollable view:
1. Breadcrumb and Course Header
2. 4-Column Live Metric Numbers
3. Stage 1 Registration Sheet Attachment Bar
4. Registration Sheet Column Health Panel
5. Verification Sheet Generation Prompt & Active Panel
6. Receipt Verification & OCR Engine Trigger Bar
7. 3 Mini-Dashboard Cards (`VERIFIED`, `UNDER REVIEW`, `DID NOT REGISTER`)
8. Stage 2 Post-Exam Results Placeholder
9. In-App Spreadsheet Preview Modal Overlay

For college elective coordinators, this layout created cognitive overload:
- Stage 1 tasks (enrollment audits, receipt OCR verification) happen at the **start of the semester** (January or July).
- Stage 2 tasks (NPTEL exam results upload, score reconciliation) happen **5 to 6 months later** (April or November).
- Cramming both stages, column diagnostics, and OCR pipelines onto one single page obscured the semester workflow and made future feature expansion difficult.

### 1.2 The Redesign Concept (User Sketch)

The user provided a handwritten blueprint reorganizing the course view into an intuitive stage-based pipeline:
- **Workspace Landing Page**: Course Name + "— Workspace", retaining the high-level 4-column metric bar.
- **Stage Cards**: Two clean, side-by-side interactive entry points:
  - **Stage 1 (Student Registration)**: Manages registration sheets, column health, and batch OCR receipt verification.
  - **Stage 2 (Examination Result)**: Dedicated workspace for post-exam score uploads and credit mapping.
- **Drill-Down Navigation**: Clicking a stage card transitions the user to a dedicated view with a clear `← Back to Workspace` escape hatch.

### 1.3 Web Dev Parallel (React / Next.js)

In modern web development, this is identical to refactoring a long, cluttered page with inline accordions into nested routes:

```
// Previous: Monolithic Dashboard Page
/courses/[courseId]/dashboard (Everything rendered on one page)

// Modern: Nested Workspace Hub & Route Architecture
/courses/[courseId]/workspace            -> <WorkspaceLayout /> + <StageCardsGrid />
/courses/[courseId]/workspace/stage-1    -> <Stage1Registration />
/courses/[courseId]/workspace/stage-2    -> <Stage2ExamResults />
```

---

## 2) The Multi-View Implementation

We split the UI into three dedicated XAML UserControls loaded dynamically via `Import-Xaml`:

### 2.1 `WorkspaceView.xaml` (Mission Control)
- Displays the breadcrumb `COURSES > {COURSE_NAME}` and title `{CourseName} — Workspace`.
- Contains the 4-column gap-grid metric strip:
  - **TOTAL REGISTERED**: Total students parsed from Google Forms.
  - **EXAM REGISTERED**: Students confirmed with payment receipts.
  - **ACTION NEEDED**: Students enrolled in the course who have not registered for exams.
  - **STAGE 2: RESULTS**: Status indicator (`Pending` vs `Uploaded`).
- Houses two side-by-side interactive cards (`CardStage1` and `CardStage2`) with status badges:
  - Stage 1 Badge: Computes `Complete ✓` when all registered students are verified, otherwise `In Progress`.
  - Stage 2 Badge: Shows `Complete ✓` once exam results are attached, otherwise `Pending`.

### 2.2 `Stage1View.xaml` (Registration & Verification Hub)
- Header with `[ ← Back to Workspace ]` button and breadcrumb `COURSES > {COURSE_NAME} > STAGE 1`.
- Linked registration spreadsheet card with `[ Preview Sheet ]`, `[ Open File ]`, `[ Replace Sheet... ]`.
- Registration Sheet Health diagnostics (7 column badges, warning banner, sync timestamp).
- Verification Sheet generation prompt & active status card.
- OCR Batch Verification action bar with `[ ▶ Verify All (OCR) ]`.
- 3-card Mini Dashboard (`VERIFIED`, `UNDER REVIEW`, `DID NOT REGISTER`).
- In-app DataGrid preview modal overlay.

### 2.3 `Stage2View.xaml` (Post-Exam & Credit Reconciliation)
- Header with `[ ← Back to Workspace ]` button and breadcrumb `COURSES > {COURSE_NAME} > STAGE 2`.
- `[ + Upload Exam Results Sheet ]` action card.
- Active sheet state panel displaying attached results file and reconciliation status.
- "Coming Soon" placeholder for automated credit transfer and grade conversion.

---

## 3) Bug Fixes & Technical Hardening

### 3.1 Cross-Version Unicode Escape Sequence Fix

#### The Bug
On Windows PowerShell 5.1 (the default engine on Windows 10/11), the title displayed as:
```
Softcomputing u{2014} Workspace
```
And the status badge rendered as:
```
Complete u{2713}
```

#### The Root Cause
PowerShell 7.1+ introduced modern Unicode escape sequences using `` `u{HEX} `` (e.g. `` `u{2014} `` for em-dash and `` `u{2713} `` for checkmark). However, Windows PowerShell 5.1 does not support `` `u{...} `` interpolation — it ignores the backtick and outputs the literal string `u{2014}`. Furthermore, saving files as UTF-8 without BOM in PowerShell 5.1 can cause literal special characters to be mangled by default system code pages.

#### The Fix
We replaced the escape string with runtime-evaluated `[char]` expressions:

```powershell
# Before (Broken in PowerShell 5.1):
$title.Text = "$cName `u{2014} Workspace"
$txtStage1Status.Text = "Complete `u{2713}"

# After (100% Cross-Version & Encoding-Safe):
$title.Text = "$cName " + [char]0x2014 + " Workspace"
$txtStage1Status.Text = "Complete " + [char]0x2713
```

In .NET / WPF, `[char]0x2014` (Unicode 8212, em-dash `—`) and `[char]0x2713` (Unicode 10003, checkmark `✓`) evaluate directly to UTF-16 characters at runtime, completely bypassing file encoding issues.

---

### 3.2 Context-Aware View Retention (Preventing Aggressive Router Ejection)

#### The Bug
When a coordinator clicked `[ ▶ Verify All (OCR) ]` inside `Stage1View`, the OCR pipeline ran smoothly, but upon completion, the app immediately kicked the coordinator back to `WorkspaceView` before or right after showing the completion summary dialog.

#### The Root Cause
To update the UI after batch verification or health checks, the click handler calls `Select-Course $script:activeCourse`. In the initial refactor, `Select-Course` had an unconditional navigation call at the end:

```powershell
# Buggy initial implementation:
function Select-Course {
    param($Course)
    ...
    # Refreshes metrics on Workspace, Stage 1, Stage 2
    ...
    Navigate-To "WorkspaceView"   # <-- Forcefully changes view back to Workspace!
}
```

Whenever the coordinator performed an action inside `Stage1View` (e.g., verifying receipts, replacing a sheet, or rechecking health), `Select-Course` ran and forcefully swapped `$ViewContainer.Content` to `WorkspaceView`.

#### The Fix
We introduced active view tracking in `Navigate-To` and made `Select-Course` context-aware:

```powershell
# 1. Track current view in router
function Navigate-To {
    param([string]$ViewName)

    $viewControl = Get-OrCreateView $ViewName
    if (-not $viewControl) { return }

    $script:currentView = $ViewName
    $ViewContainer.Content = $viewControl
    ...
}

# 2. Guard navigation in Select-Course
function Select-Course {
    param(
        $Course,
        [string]$TargetView = $null
    )
    if (-not $Course) { return }
    $script:activeCourse = $Course
    ...
    # Update controls in-place across views
    ...
    if ($TargetView) {
        Navigate-To $TargetView
    } elseif ($script:currentView -eq "Stage1View" -or $script:currentView -eq "Stage2View") {
        # Already inside the stage detail view; keep user on the active view
    } else {
        Navigate-To "WorkspaceView"
    }
}
```

Now:
1. When opening a course from `CoursesView`, the user routes into `WorkspaceView`.
2. When clicking `CardStage1`, the user routes into `Stage1View`.
3. Inside `Stage1View`, clicking `[ ▶ Verify All (OCR) ]` updates all metrics and badges in-place while keeping the coordinator comfortably on `Stage1View`.
4. The coordinator returns to `WorkspaceView` only when they explicitly click `[ ← Back to Workspace ]`.
