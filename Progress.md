# NPTEL Management System — Project Progress Tracker

> **How to use this file:** At the start of every session, review this file and paste the prompt
> from **Section 6**. The assistant reads this file, builds ONLY the next unchecked piece, and
> gives small paste-ready updates as it goes. **You paste those updates back into this file.**
> This file is the project's memory between sessions — if it isn't written here, it is not remembered.

---

## 0. Project Snapshot

**Project:** A desktop management and automated verification tool for college NPTEL elective coordinators. It automates cross-checking student registrations against college records and fee receipts at semester start, and later merges NPTEL examination results into final college grade sheets.

**Stack:** PowerShell 5.1 / 7 · WPF (XAML UserControls) · Local JSON State (`data/courses.json`) · Native Windows Forms Dialogs.

**Working style / rules (Must be followed every session):**
- **Modular Component Architecture**: Web-like SPA structure with individual XAML views (`UI/Views/*.xaml`) swapped inside a single App Shell (`UI/MainWindow.xaml`) using `Navigate-To`.
- **Zero Jargon**: The medical term *"Triage"* is strictly banned. Use plain academic terms: **Review**, **Errors**, **Issues**, or **Mismatches**.
- **Zero Dummy Data**: No hardcoded mock names, counts, or fake paths. All views start in clean empty states until real courses and spreadsheets are provided.
- **2-Stage Semester Lifecycle**:
  - *Stage 1 (Start of Semester)*: Initial registration verification using **ONE single spreadsheet** (Student Registration / Google Form).
  - *Stage 2 (In 5-6 Months)*: Post-exam results upload (`[+ Upload Exam Results Sheet]`) to merge scores with verified students.
- **Strict Validation**: Courses cannot be created without a valid Course Title AND an existing `.xlsx`, `.xls`, or `.csv` spreadsheet file on disk.
- **PowerShell Scoping Rules**: Never rely on local function variables inside WPF event scriptblocks; always look up controls dynamically or bind metadata via WPF element `.Tag`.
- **Always Code Task-by-Task & Ask Before Coding**: Work strictly on one task at a time. Always present the plan and explicitly ask the user for confirmation BEFORE implementing or writing any code.
- **Handling Unlisted / Extra Tasks**: If work diverts to an unlisted or ad-hoc task requested by the user, by default add it to the active branch checklist under a `#### Extra / Ad-Hoc Completed Tasks` section, mark it `[x] <task> [Session N]`, log it in that session's notes, and then resume the scheduled roadmap.

**Repo layout (current):**
```
PDQA Project/
├── UI/
│   ├── MainWindow.xaml            # Main window shell & navigation bar
│   ├── Styles/
│   │   └── Theme.xaml             # Design tokens, brushes, & control styles (from Design.md)
│   └── Views/
│       ├── HomeView.xaml          # Welcome launcher + toggleable course setup form
│       ├── CoursesView.xaml       # Managed courses library & card grid
│       ├── WorkspaceView.xaml     # Course workspace landing page (metrics & interactive stage cards)
│       ├── Stage1View.xaml        # Stage 1 Student Registration & Verification command center
│       ├── Stage2View.xaml        # Stage 2 Post-Exam Results & reconciliation workspace
│       ├── DashboardView.xaml     # Legacy course dashboard (preserved for fallback)
│       ├── ReviewView.xaml        # Discrepancy review & receipt comparison (staged for Phase E)
│       ├── EmailView.xaml         # Dedicated Email Management Center view (Branch 4)
│       ├── SettingsView.xaml      # Google Sheets & Tesseract OCR paths
│       └── StudentListView.xaml   # Full student roster view (staged for Phase F)
├── data/
│   ├── courses.json               # Persisted courses store (Zero mock data)
│   └── Courses/                   # Human-readable course storage (<CourseName>/students.json + receipts/)
├── modules/
│   ├── Import-StudentSheet.ps1    # Spreadsheet parser & student store persistence engine
│   ├── Download-Receipts.ps1      # Batch Google Drive downloader & local matching cache
│   ├── OcrEngine.ps1              # Native WinRT PDF rasterizer & OCR text extraction
│   └── VerificationEngine.ps1     # 5-Rule verification matcher & automated delta pipeline
├── notes/
│   ├── Branch_1(Session_1).md     # Web dev guide & notes for Branch 1 Session 1
│   ├── Branch_2(Session_1).md     # Web dev guide & notes for Branch 2 Session 1
│   ├── Branch_2(Session_2).md     # Web dev guide & notes for Branch 2 Session 2
│   ├── Branch_2(Session_3).md     # Web dev guide & notes for Branch 2 Session 3
│   ├── Branch_2(Session_4).md     # Web dev guide & notes for Branch 2 Session 4
│   ├── Branch_3(Session_1).md     # Notes for Branch 3 Session 1 (Phases A, B, C & Data Restructure)
│   ├── Branch_3(Session_2).md     # Notes for Branch 3 Session 2 (Phase D: 5-Rule Matcher & Delta Sync)
│   ├── Branch_3(Session_3).md     # Notes for Branch 3 Session 3 (Stage-Based Workspace & Router)
│   ├── Branch_3(Session_4).md     # Notes for Branch 3 Session 4 (Review Workspace, Decoupled Pipeline & "Update Sheet" De-duplication)
│   ├── Branch_3(Session_5).md     # Notes for Branch 3 Session 5 (1-Click Actions, Resubmit Modal & Manual Attachment)
│   ├── Branch_3(Session_6).md     # Notes for Branch 3 Session 6 (Collapsible Health, 'Import Receipts' & Concession Matching)
│   └── Branch_4(Session_1).md     # Notes for Branch 4 Session 1 (Email Center, Zero-Password Dispatch & 2-Way Audit)
├── NPTEL-Manager.ps1              # Main WPF application runner & router controller
├── build.ps1                      # ps2exe compilation script
├── test_parse.ps1                 # XAML and script syntax validator
├── Design.md                      # UI visual specification (Warm Dark Minimalism)
├── Approach.md                    # Project architectural comparison
├── project.md                     # Comprehensive domain specification
├── CHAT_SUMMARY.md                # Historical development chat log
├── PROGRESS-TEMPLATE.md           # Template specification for this file
└── Progress.md                    # This active tracking file
```

**Notes tracking:** Session notes in `notes/` directory: `Branch_1(Session_1).md`, `Branch_2(Session_1).md` through `Branch_2(Session_4).md`, `Branch_3(Session_1).md` through `Branch_3(Session_6).md`, `Branch_4(Session_1).md`.

---

## 1. Branches & Numbering

| # | Name | Purpose | Status |
|---|------|---------|--------|
| 1 | Main | Core build, in planned order | Paused |
| 2 | Dealing with sheet in our app | Import, parse, validate student enrollment sheet & handle sheet operations | Paused |
| 3 | Student Verification System | Batch download receipts, OCR extraction, rule-based verification, and discrepancy review | Paused |
| 4 | Send Email | Student notification system for receipt resubmissions, discrepancy alerts, and coordinator updates | Paused |
| 5 | Stage 2 Examination Results & Final Sheet | Import exam responses, verify certificate marks via WinRT OCR, review discrepancies, and generate college Final Result Sheet | In progress |

---

## 2. Checklists (one per branch)

### Branch 1 (Main)

#### Phase A — Theme, Design Tokens & Shell Setup
- [x] Create centralized theme dictionary based on `Design.md` (`UI/Styles/Theme.xaml`) `[Session 1]`
- [x] Build App Shell layout with fixed header, status badge, and `<ContentControl>` outlet (`UI/MainWindow.xaml`) `[Session 1]`
- [x] Implement dynamic SPA router in controller script (`NPTEL-Manager.ps1`) `[Session 1]`
- [x] Eliminate all medical/er jargon (banned the term *"Triage"*) `[Session 1]`

#### Phase B — Course Onboarding & Home Launcher
- [x] Clean welcome launcher canvas on Home (`PanelHomeWelcome`) with 2 distinct CTA cards `[Session 1]`
- [x] On-demand toggleable course registration form (`PanelRegisterForm`) with Back & Cancel buttons `[Session 1]`
- [x] 1-Sheet initial registration flow (Student Enrollment & Registration Sheet only) `[Session 1]`
- [x] Mandatory spreadsheet validation: block course creation if title is blank or sheet file does not exist on disk `[Session 1]`
- [x] Persist courses to local JSON database (`data/courses.json`) `[Session 1]`
- [x] Remove dummy data across all views and implement clean empty states `[Session 1]`
- [x] Temporarily remove `Review` and `Student List` from navigation until Excel ingestion is built `[Session 1]`
- [x] Fix PowerShell `Split-Path` null error and event closure variable scoping using button `.Tag` `[Session 1]`

#### Phase C — Courses Hub & Management (`CoursesView.xaml`)
- [ ] Display real registered courses dynamically from `data/courses.json` with badges and file paths
- [ ] Implement course card management actions: `[Open Dashboard]`, `[Replace Sheet]`, `[Delete Course]`
- [ ] Empty state prompt: "+ Add Your First Course" linking directly to the registration form

#### Phase D — Excel Parsing & Student Data Ingestion (Stage 1)
- [ ] Create PowerShell Excel / CSV reader module (`modules/Import-StudentSheet.ps1`)
- [ ] Auto-detect and map columns: Roll Number, Student Name, Course Name/Code, Fee Amount, Receipt URL/Path
- [ ] Store parsed student enrollment records scoped per course in `data/students_<courseId>.json`

#### Phase E — Verification Rule Engine & Review Queue (`ReviewView.xaml`)
- [ ] Implement matching logic: Course Code match, Fee payment threshold check (₹1,000 / ₹1,100)
- [ ] Automatically mark clean records as `[Verified]`
- [ ] Route discrepancies to `ReviewView`: mismatched course name, missing payment, blurry receipt
- [ ] Re-enable `Review` tab in navigation once parser is active
- [ ] Implement 1-click coordinator actions: `[Approve Override]` and `[Flag Resubmit]`

#### Phase F — Student Roster & Export (`StudentListView.xaml`)
- [ ] Display full student list with real search, department filter, and status badges (`Verified`, `Needs Review`)
- [ ] Re-enable `Student List` tab in navigation
- [ ] Add CSV export button for coordinator college records

#### Phase G — Stage 2: Post-Exam Results Upload & Credit Mapping (In 5-6 Months)
- [ ] Parse official NPTEL exam results spreadsheet uploaded via Dashboard
- [ ] Merge exam marks and certificate criteria (Elite / Silver / Gold / Pass / Fail) with verified students
- [ ] Export final college credit transfer and evaluation report

### Branch 2 (Dealing with sheet in our app)

#### Core Roadmap
- [x] Build spreadsheet parser module (`modules/Import-StudentSheet.ps1`) supporting `.xlsx` and `.csv` without requiring Microsoft Excel `[Session 1]`
- [x] Implement smart column detection (Enrollment / Roll No, Student Name, Course / Subject, Fee / Amount, Certificate / Receipt link) `[Session 2]`
- [x] Ingest sheet rows and persist parsed student enrollment records in `data/students_<courseId>.json` `[Session 3]`
- [x] Connect Course Dashboard (`DashboardView.xaml`) to show parsed student sheet metrics and summary `[Session 4]`
- [x] Implement `[Replace Sheet]` workflow to update or re-link a course's registration spreadsheet `[Session 4]`
- [ ] Add spreadsheet validation error feedback for unsupported formats or missing required columns

#### Extra / Ad-Hoc Completed Tasks
- [x] Add `[Open File]` (system launcher) and in-app sheet preview modal to Course Dashboard (`DashboardView.xaml`) `[Session 1]`
- [x] Add process-scope execution bypass and auto-STA launcher for one-command startup (`./NPTEL-Manager.ps1`) `[Session 1]`
- [x] Create web developer educational session notes (`notes/Branch_1(Session_1).md`, `notes/Branch_2(Session_1).md`) `[Session 1]`
- [x] Refactor Registration Sheet Health panel to show basic sheet counts (Total, Exam Registered, Other) and remove all verification jargon `[Session 4]`
- [x] Add `[Recheck Health]` button to Registration Sheet Health panel to force re-scan modified spreadsheets `[Session 4]`
- [x] Implement Verification Sheet panel to duplicate registration sheet and append 'Verification Status' & 'Remarks' columns `[Session 4]`

### Branch 3 (Student Verification System)

#### Phase A — Verification Sheet Mini-Dashboard & UI Controls
- [x] Add `[ ▶ Verify All (OCR) ]` button to Verification Sheet panel in `DashboardView.xaml` `[Session 1]`
- [x] Add 3-metric Mini Dashboard cards to Verification Sheet panel: `VERIFIED`, `UNDER REVIEW`, `DID NOT REGISTER` `[Session 1]`
- [x] Bind dynamic verification status counts to the Mini Dashboard in `NPTEL-Manager.ps1` `[Session 1]`

#### Phase B — Batch Receipt Downloader
- [x] Build batch receipt downloader module (`modules/Download-Receipts.ps1`) to extract Google Drive file IDs and stream downloads `[Session 1]`
- [x] Implement local course storage (`data/receipts/<CourseId>/<RollNo>_receipt.<ext>`) with skip-existing resumable cache `[Session 1]`
- [x] Add download error handling for broken or inaccessible links `[Session 1]`

#### Phase C — PDF Page-to-Image Conversion & OCR Engine
- [x] Build Windows native PDF rasterizer (`Windows.Data.Pdf`) to render Page 1 screenshot PDFs into crisp PNG images `[Session 1]`
- [x] Build OCR text extractor module to scan rendered receipt images for text lines `[Session 1]`

#### Phase D — 5-Rule Verification Matcher
- [x] Implement Rule 1: Payment Status check (confirm "successful", guard against "failed") `[Session 2]`
- [x] Implement Rule 2: Fee Amount check (detect ₹1,000 / ₹1,100) `[Session 2]`
- [x] Implement Rule 3: Course Title matching (match against active course keywords) `[Session 2]`
- [x] Implement Rule 4: NPTEL / Razorpay authenticity check (`order_`, `pay_`, `support@nptel.iitm.ac.in`) `[Session 2]`
- [x] Implement Rule 5: Student Name cross-check (match `Hello <Name>` with student roster) `[Session 2]`
- [x] Wire `[ ▶ Verify All (OCR) ]` pipeline to classify records into Verified, Under Review, or Did Not Register `[Session 2]`
- [x] Write verification results back to both `data/Courses/<CourseName>/students.json` and `<CourseName>_Verification_Sheet.xlsx` `[Session 2]`

#### Phase E — Review & Discrepancy Queue (`ReviewView.xaml`)
- [x] Wire Mini Dashboard `[ UNDER REVIEW ]` card to navigate to `ReviewView.xaml` `[Session 4]`
- [x] Build split-screen review workspace: student details on left, zoomable receipt image on right `[Session 4]`
- [x] Implement 1-click coordinator actions: `[ Approve Override ]` and `[ Flag for Resubmit ]` `[Session 5]`
- [x] Add `[ ← Back to Dashboard ]` header navigation button with instant metric synchronization `[Session 4]`

#### Phase F — Filtered Student Roster & Export (`StudentListView.xaml`)
- [ ] Wire Mini Dashboard `[ VERIFIED ]` and total counts to navigate to `StudentListView.xaml`
- [ ] Implement 4 filter tabs: `[ All ]`, `[ Verified ]`, `[ Under Review ]`, `[ Did Not Register ]`
- [ ] Add student search by Roll No / Name
- [ ] Add `[ Export College Verification List (CSV) ]` button
- [ ] Add `[ ← Back to Dashboard ]` return button

#### Extra / Ad-Hoc Completed Tasks
- [x] Organize data directory into human-readable course name folders (`data/Courses/<CourseName>/receipts/`) instead of raw UUIDs `[Session 1]`
- [x] Relocate `students.json` database inside course folders (`data/Courses/<CourseName>/students.json`) with legacy auto-migration `[Session 1]`
- [x] Implement Smart Delta Response Synchronization (`Sync-CourseResponses`) with receipt link change invalidation and rich report dialog `[Session 2]`
- [x] Add `[ 🔄 Sync Responses ]` button to Stage 1 attachment bar in `DashboardView.xaml` `[Session 2]`
- [x] Stage-Based Course Workspace Redesign: Split monolithic DashboardView into WorkspaceView, Stage1View, and Stage2View `[Session 3]`
- [x] Dynamic Stage Status Badges: Real-time calculation and display of 'In Progress' vs 'Complete ✓' on Workspace cards `[Session 3]`
- [x] Cross-Version Unicode Hardening: Replaced unsupported PowerShell 7 escape sequences with runtime [char] tokens for cross-version em-dash and checkmarks `[Session 3]`
- [x] Context-Aware Navigation State: Implemented $script:currentView tracking so in-stage actions (OCR Verify All, Health Recheck, Replace Sheet) stay on the active stage view `[Session 3]`
- [x] Course Deletion Workflow: Implemented safe Remove-Course with confirmation dialog, JSON/cache cleanup, and Delete buttons in CoursesView card & WorkspaceView header `[Session 4]`
- [x] Metric Synchronization & Path Resolution Fix: Explicitly passed CourseName to all store calls in NPTEL-Manager.ps1 and hardened ArrayList type preservation, ensuring Stage 1 dashboard mini-cards accurately reflect verified OCR counts `[Session 4]`
- [x] Decoupled 2-Step Verification Pipeline: Added dedicated [ 📥 Download Receipts ] and [ ▶ Run OCR Verification ] actions with on-disk cache tracking and permission diagnostics `[Session 4]`
- [x] Smart Resubmission De-Duplication & "Update Sheet" Workflow: Replaced "Replace Sheet" and "Sync" with a unified "Update Sheet" action that re-scans or browses sheets, de-duplicates multiple submissions by Roll No (latest timestamp wins), automatically purges old cached receipts for resubmitted students, and queues them for re-verification `[Session 4]`
- [x] Session Review Mini Dashboard & Queue Table Redesign: Redesigned ReviewView with 2-mode architecture based on coordinator sketch: Mode A (Mini Dashboard with Total Issues, Solved in Session, Pending; Push Changes to Main Sheet action bar with dynamic badge; polished Segoe UI 26pt SemiBold #FFFFFF heading; 3-column student card rows with mono Enrollment, Name [with issue tooltip], and Quick Actions [Width: Auto - never clipped]: Issues, Receipt, Approve/Unapprove toggle, Open Student) and Mode B (split-screen student detail inspection workspace with Back to Queue button) `[Session 5]`
- [x] Staged Push Synchronization & Toggleable Approval: Quick-approvals and detail overrides stage students in session memory with visual 'Solved' badges (no tick mark, no extra text); clicking [ Approve ] toggles into [ Unapprove ] with full rollback of status and remarks; clicking [ Push Changes to Main Sheet ] commits all staged students to students.json and synchronizes <CourseName>_Verification_Sheet.xlsx, automatically decrementing Under Review and incrementing Verified counters on the Stage 1 dashboard `[Session 5]`
- [x] Collapsible Sheet Health Panel & Categorized Impact Guidance: Compact mini-info header row (`Total Students • Exam Registered • Detected/7 Standard Columns`) with toggle button `[ View Details ▼ ]` ⇄ `[ Hide Details ▲ ]` and distinct Critical vs Optional column impact guidance `[Session 6]`
- [x] Direct Native File Explorer for Sheet Updates: Clicking `[ Update Sheet ]` directly opens Windows File Explorer dialog without intermediate prompts `[Session 6]`
- [x] Typo-Tolerant Sheet Schema & Defensive Property Initialization: Regex handles real-world variations like `"Reistration Done"`, and defensive initialization of `VerificationStatus` prevents runtime property assignment errors `[Session 6]`
- [x] Local Folder & ZIP Receipt Ingestion Engine (`[ 📁 Import Receipts ]`): Added toolbar button left of `[ 📥 Download Receipts ]`, auto-extracting `.zip` archives with temp cleanup, and 4-tier smart matching (Roll Number, Full Name, Token overlap, Unique First Name) `[Session 6]`
- [x] Rule 2 Fee Concession & Comma-Separated Normalization: Expanded Rule 2 to accept ₹500/₹550 official SC/ST/PwD concessions alongside standard ₹1,000/₹1,100, with comma/decimal normalization `[Session 6]`
- [x] Instant View Panel Reload on Manual Attachment: Fixed bug where newly attached and approved receipts were not re-rendered in Review Mode B view panel `[Session 6]`
- [x] Clean & Adaptive Verification Pipeline Bar: Streamlined pipeline UI by removing all "Step 1/Step 2" text clutter and duplicate titles, replaced with a clean single-line status pill and an on-demand adaptive progress bar (with live percentage and student ticker) that dynamically morphs across Import, Download, and OCR verification `[Session 6]`
- [x] PowerShell 5.1 Parser Hardening & Scoping Fixes: Script-scoped Update-PipelineBarState with Dispatcher render queue pumping; eliminated inline ternary concatenations to ensure 100% compatibility with Windows PowerShell 5.1 `[Session 6]`

### Branch 4 (Send Email)

#### Phase A — Dedicated Email UI & Review Entry Point (Shared Foundation)
- [x] Add "Send Email to Flagged Students" action bar row in `ReviewView.xaml` `[Session 1]`
- [x] Create dedicated Email Management Center view (`UI/Views/EmailView.xaml`) `[Session 1]`
- [x] Wire SPA router in `NPTEL-Manager.ps1` (`Navigate-To -ViewName "EmailView"`) with return navigation `[Session 1]`

#### Sub-Branch 4.1 — Browser Draft Dispatch (Approach 2: Zero-Password & Manual Gmail Send)
- [x] Build 1-click Gmail Web Compose launcher with BCC student list, dynamic subject, and pre-filled instructions `[Session 1]`
- [x] Add 1-click `[ 📋 Copy Formatted Notice ]` (for WhatsApp/Telegram) and `[ 📋 Copy BCC Emails ]` buttons `[Session 1]`
- [x] Mark recipients as `Notified` in `students.json` with timestamp upon launching draft `[Session 1]`

#### Sub-Branch 4.2 — Direct In-App Background Dispatch (Approach 1: SMTP / App Password)
- [ ] Email & SMTP configuration card with masked `<PasswordBox>` in `SettingsView.xaml`
- [ ] Secure credential storage using Windows DPAPI encryption (`data/settings.json`)
- [ ] Implement native SMTP client module (`modules/EmailEngine.ps1`) with test email verification
- [ ] Direct in-app batch sender with live progress bar and individual delivery tracking in `students.json`

#### Extra / Ad-Hoc Completed Tasks
- [x] Fix WPF Event Scope Closure on Template Switcher (promoted `Set-EmailTemplate` to script-scoped function) `[Session 1]`
- [x] Email Center UI Declutter & Modernization (streamlined headers, eliminated noisy descriptions, shortened button labels) `[Session 1]`
- [x] 2-Way Delivery Status Management (added `[✓ Mark Notified]` and `[↺ Unmark]` manual roster controls with state rollback) `[Session 1]`
- [x] Decommissioned Redundant 'Flag for Resubmit' Button & Modal (all review queue students are already flagged; simplified Mode B to single 'Approve (Override)' action) `[Session 1]`

### Branch 5 (Stage 2: Examination Results & Final Sheet)

#### Phase A — Exam Results Sheet Ingestion & Data Store
- [x] Define Stage 2 response header schema and parser in `modules/Import-StudentSheet.ps1` (`Import-ExamResultsSheet`) `[Session 1]`
- [x] Store Stage 2 student records in `data/Courses/<CourseName>/exam_results.json` (or merged in `students.json`) `[Session 1]`
- [x] Update `courses.json` with `ExamResultsSheet` path and stage status `"ResultsUploaded"` `[Session 1]`

#### Phase B — Certificate Ingestion & 4-Tier Matching
- [ ] Reuse Google Drive direct batch downloader from `modules/Download-Receipts.ps1` (`Download-ReceiptsFromDrive`)
- [ ] Reuse 4-tier local matching algorithm (`Import-ReceiptsFromLocalSource`) for local folders / ZIP archives
- [ ] Store matched certificates in `data/Courses/<CourseName>/certificates/` with persistent cache

#### Phase C — WinRT OCR & Certificate Data Extractor
- [ ] Reuse WinRT PDF rasterizer (`ConvertTo-ReceiptImage` in `modules/OcrEngine.ps1`) to render certificate PDFs to 1600px PNGs
- [ ] Reuse WinRT OCR engine (`Invoke-ReceiptOcr`) to extract raw lines and bounding boxes
- [ ] Build specialized extractor `Extract-CertificateData` in `modules/ExamVerificationEngine.ps1` targeting NPTEL certificate fields (Candidate Name, Course Title, Assignment /25, Exam /75, Total /100, Roll No, Credits)

#### Phase D — 5-Rule Exam Verification Engine & Under Review Policy
- [ ] Implement `Test-ExamVerificationRules` in `modules/ExamVerificationEngine.ps1` (Course Match, Identity Match, Assignment Marks, Exam Marks, Total Marks)
- [ ] Enforce strict Under Review policy: mark any decimal or rounding mismatch (e.g. 25 vs 24.67) and missing/unreadable certificates as `Under Review` with detailed remarks
- [ ] Implement `Invoke-CourseExamVerificationPipeline` with batch processing, delta skipping, and progress reporting

#### Phase E — Stage 2 UI Command Center (`UI/Views/Stage2View.xaml`)
- [x] Replace "Coming Soon" in `Stage2View.xaml` with Results Sheet Attachment Card, Pipeline Control Bar, adaptive progress bar, and 4-metric summary cards `[Session 1]`
- [ ] Wire Stage 2 Review Queue interaction with split-screen preview and 1-click `[ Accept Certificate Marks ]` override button
- [ ] Update Workspace Navigation and Stage 2 status badge in `NPTEL-Manager.ps1`

#### Phase F — Official College Final Result Sheet Generator
- [ ] Build `Export-CourseFinalResultSheet` in `modules/Export-FinalResultSheet.ps1` using `ImportExcel`
- [ ] Populate standard departmental columns (S.No, Enrollment No, Student Name, Assignment Marks /25, Exam Marks /75, Total Marks /100, NPTEL Roll No, Credits, Pass/Fail, Remarks) — without medal tiers
- [ ] Apply clean institutional styling (Navy header `#1F4E79`, white bold text, alternating light rows, auto-fitted columns)
- [ ] Add `[ 📊 Generate Final Result Sheet ]` button in `Stage2View.xaml` with direct system file launcher

#### Extra / Ad-Hoc Completed Tasks
- [x] Windows PowerShell 5.1 Unicode & String Hardening for Stage 2: Replaced literal em-dash strings with `[string][char]0x2014` and sanitized non-ASCII tokens to guarantee 100% parse stability in Windows PowerShell 5.1 `[Session 1]`
- [x] Applied Skill 1 Dynamic Control Resolution to Stage 2 View: Refactored 'View Details' health toggle, preview modal close, and search filter event handlers in `NPTEL-Manager.ps1` to resolve controls dynamically via `$script:views["Stage2View"]` and `$this`, eliminating runtime property visibility/content errors `[Session 1]`
- [x] Manual Result Verification Sheet Generation & Verification Columns: Aligned Stage 2 Card D with Stage 1 architecture — added State A prompt with `[ + Generate Result Verification Sheet ]`, built `New-CourseExamVerificationSheet` to generate `<Course>_Result_Verification_Sheet.xlsx` appending `Verification Status` and `Verification Remarks` columns, and wired Preview Sheet, Open File, and Recreate Sheet actions `[Session 1]`
- [x] Collapsible Verification Sheet Panel in Stage 1 & Stage 2: Wrapped the large active verification details (pipeline bar, 3-card mini dashboard, and action buttons) inside a collapsible container (collapsed by default); added `[ Open Sheet ▼ ]` / `[ Close Sheet ▲ ]` toggle button in the File Location Bar following Skill 1 dynamic control resolution `[Session 1]`

---

## 3. Sessions Log

### Session 1 (Branch 1 (Main)) — Modular UI Architecture, Jargon Removal & Clean Course Setup

**Files created/updated**
```
UI/Styles/Theme.xaml (Centralized design tokens, Warm Dark palette, DarkInput style, Button styles)
UI/MainWindow.xaml (App shell with logo, dynamic ViewContainer, and updated 3-tab navigation)
UI/Views/HomeView.xaml (2-state Home: Welcome launcher with action cards + toggleable course setup form)
UI/Views/CoursesView.xaml (Managed courses library with dynamic host and empty state)
UI/Views/DashboardView.xaml (Course dashboard with Stage 1 sheet tracking + Stage 2 post-exam upload card)
UI/Views/ReviewView.xaml (Renamed from TriageView, replaced jargon with Review)
UI/Views/StudentListView.xaml (Renamed from RosterView, clean empty state)
UI/Views/SettingsView.xaml (Clean settings for Google Sheets and Tesseract OCR)
NPTEL-Manager.ps1 (Refactored to modular router, fixed null Split-Path, fixed event scope with .Tag, enforced spreadsheet validation)
data/courses.json (Persisted local JSON store for registered courses)
Progress.md (Replaced with standard PROGRESS-TEMPLATE structure)
```

**Decisions made this session**
- *Modular SPA Architecture*: Selected UserControl-based views swapped into `<ContentControl>` over a single monolithic XAML file.
- *Strict Jargon Ban*: Completely eliminated the term "Triage" throughout UI and code; replaced with "Review" and "Issues".
- *Single-Sheet Initial Registration*: Initially only require 1 sheet (Student Registration & Enrollment). Exam results sheet is deferred to Stage 2 (5-6 months later).
- *Strict Course Validation*: Prevented empty course creation. Both Course Title and an existing Excel/CSV file must be provided.
- *Navigation Simplification*: Removed "Review" and "Student List" tabs until Excel parsing is connected, keeping top navigation to `[ Home ]`, `[ Courses ]`, `[ Settings ]`.
- *PowerShell Event Scoping*: Used button `.Tag` to pass course ID into click events to prevent closure scope garbage-collection errors in PowerShell 5.1.

**Known issues / TODO carried forward**
```
- Real Excel/CSV parsing engine is not yet connected to read student rows from the attached file.
- Next piece: Phase C (Enhance CoursesView.xaml management and card actions).
```

### Session 1 (Branch 2 (Dealing with sheet in our app)) — Spreadsheet Parsing, In-App Previews & Web Dev Notes

**Files created/updated**
```
modules/Import-StudentSheet.ps1 (Spreadsheet parsing engine supporting .xlsx and .csv with row filtering and header extraction)
UI/Views/DashboardView.xaml (Added [Preview Sheet], [Open File] buttons, and full dark in-app DataGrid preview modal)
NPTEL-Manager.ps1 (Wired system file launcher, connected in-app table preview, dynamic enrolled metric counting, process bypass, and STA launcher)
notes/Branch_1(Session_1).md (Web developer's guide & deep-dive notes for Branch 1)
notes/Branch_2(Session_1).md (Web developer's guide & deep-dive notes for Branch 2)
Progress.md (Added Branch 2, project rules, repo layout updates, and session progress)
```

**Decisions made this session**
- *Zero-Office Dependency*: Leveraged the existing ImportExcel PowerShell module for .xlsx processing, with native Import-Csv fallback.
- *Dual-Use Script*: Designed `Import-StudentSheet.ps1` to support both dot-sourced function calls and direct script execution with `-Path`.
- *Option C Hybrid Sheet Access*: Provided both direct Windows Shell launch (`[Open File]`) and a full in-app dark data grid preview modal (`[Preview Sheet]`).
- *One-Command Startup*: Configured process-level ExecutionPolicy Bypass and auto-STA self-restart so `./NPTEL-Manager.ps1` runs effortlessly.
- *Visible Columns Retained*: Kept all columns visible (Columns D to H) instead of hiding them, prioritizing human-readable timestamp formatting.
- *Web Dev Documentation*: Standardized educational session notes in `notes/` translating PowerShell/WPF concepts to React, CSS, and Node.js.

**Known issues / TODO carried forward**
```
- Excel serial timestamps (e.g. 46146.7169...) need conversion to human-readable date strings (5/4/2026 17:12:26).
- Next piece: Format timestamps in modules/Import-StudentSheet.ps1, followed by smart column detection.
```

### Session 2 (Branch 2 (Dealing with sheet in our app)) — Serial Dates, Schema Normalization & Smart Column Mapping

**Files created/updated**
```
modules/Import-StudentSheet.ps1 (Added ConvertTo-ReadableDate for OADate conversion, Get-ColumnMapping for smart schema detection, and normalized Students collection with Raw extra columns)
notes/Branch_2(Session_2).md (Web developer notes on Excel serial dates, fuzzy column matching, and Raw pattern)
Progress.md (Recorded Session 2 progress and updated notes tracking)
```

**Decisions made this session**
- *Excel Serial OADate Conversion*: Implemented `[DateTime]::FromOADate()` conversion for serial numbers in the 30000–60000 range to output human-readable `dd/MM/yyyy HH:mm:ss` timestamps.
- *Targeted Smart Column Matching*: Matched headers against regex patterns tailored for college Google Forms (handling typos like "Enrollnment" and trailing spaces).
- *Normalized Data Model*: Every row is parsed into standard properties (`RollNo`, `Name`, `Email`, `Subject`, `IsEnrolled`, `IsRegistered`, `ProofUrl`, `Timestamp`).
- *Type Coercion for Booleans*: Translated text values ("Yes", "No", "Done") into real boolean `$true`/`$false`.
- *Raw Extra Columns Preservation*: Stored all unmapped sheet columns in a dedicated `Raw` ordered dictionary on each student record, guaranteeing zero data loss.

**Known issues / TODO carried forward**
```
- Parsed students need to be persisted to local course JSON database (data/students_<courseId>.json).
- Next piece: Ingest sheet rows and persist parsed student enrollment records in data/students_<courseId>.json.
```

### Session 3 (Branch 2 (Dealing with sheet in our app)) — Local Course Student Database Persistence

**Files created/updated**
```
NPTEL-Manager.ps1 (Added Get-CourseStudentsFilePath, Save-CourseStudents, Get-CourseStudents, wired fast JSON cache to Course Creation and Select-Course)
notes/Branch_2(Session_3).md (Web developer notes on local JSON storage, lazy ingestion, and state decoupling)
Progress.md (Recorded Session 3 student persistence completion)
```

**Decisions made this session**
- *Zero-Lag JSON Cache*: Saved normalized student records into `data/students_<courseId>.json`, ensuring instant `0ms` dashboard loading and eliminating repeat Excel parsing.
- *Lazy Ingestion / Auto-Heal*: `Get-CourseStudents` automatically reads from disk cache first; if missing, it parses the attached registration spreadsheet and caches it on the fly.
- *Safe from Excel Locking*: Reading from local JSON prevents file lock crashes if the coordinator has the spreadsheet open in Microsoft Excel.

**Known issues / TODO carried forward**
```
- Next piece: Connect Course Dashboard (DashboardView.xaml) to show parsed student sheet metrics and summary.
```

### Session 4 (Branch 2 (Dealing with sheet in our app)) — Sheet Health, Immutable Verification Sheets & DataGrid Normalization

**Files created/updated**
```
UI/Views/DashboardView.xaml (Upgraded to 4-column live metrics; added Registration Sheet Health panel with basic sheet numbers; added Verification Sheet panel with Prompt and Active states)
NPTEL-Manager.ps1 (Enhanced Get-CourseStudentStore with -Force bypass; added New-CourseVerificationSheet; added safe Add-Member property assignment; wired Recheck Health, Replace Sheet, and Verification Sheet actions)
modules/Import-StudentSheet.ps1 (Added automatic whitespace trimming on property names and headers to fix WPF DataGrid silent binding failure)
data/courses.json (Migrated schema to include VerificationSheet property)
notes/Branch_2(Session_4).md (Web dev notes on sheet health decoupling, WPF DataGrid reflection traps, and immutable verification sheet pattern)
Progress.md (Recorded Session 4 completion and notes)
```

**Decisions made this session**
- *4-Column Live Metric Breakdown*: Divided dashboard metrics into Total Enrolled, Exam Registered (Sage Green), Action Needed (Amber Warning for unregistered students), and Stage 2 Results status.
- *Registration Sheet Health Panel*: Refactored the audit panel between Stage 1 and Stage 2 into a clean, simple "Registration Sheet Health" panel. Strictly eliminated all verification/stage jargon ("Triage", "Column Audit", "Schema Mapping", "Pending Review").
- *Basic Sheet Ingestion Numbers*: Integrated quick-metric indicators inside the panel displaying Total Students, Exam Registered, and Other / Not Registered as read from the sheet.
- *Factual Column Detection Status*: Retained 7 standard academic column badges (`RollNo`, `Name`, `Email`, `Subject`, `IsEnrolled`, `IsRegistered`, `ProofUrl`) showing detected sheet headers or missing alerts without making assumptions about verification.
- *Recheck Health & Replace Sheet Integration*: Added `[Recheck Health]` button with `-Force` cache bypass to re-scan modified spreadsheets from disk; wired `[Replace Sheet...]` to immediately ingest the replacement sheet, update JSON store, and refresh the dashboard.
- *Verification Sheet Panel & Generation*: Created a dedicated "Verification Sheet" dashboard panel with State A (Prompt to generate) and State B (Active with path, Preview, and Open in Excel). Built `New-CourseVerificationSheet` to duplicate the registration responses and append `Verification Status` and `Verification Remarks` columns, protecting the original Google Forms sheet.
- *WPF DataGrid Trailing Space Property Normalization*: Discovered and resolved an issue where Google Forms headers with trailing whitespace (e.g. `'Upload proof of registration '`) caused WPF's `Binding` tokenizer to fail silently and render empty cells in the preview table. Added automatic whitespace trimming for all property names and headers in `Import-StudentSheet.ps1`.
- *Safe Property Mutation in PowerShell 5.1*: Implemented dynamic `Add-Member -Force` guards when mutating `[PSCustomObject]` properties to eliminate runtime `property cannot be found` crashes.

**Known issues / TODO carried forward**
```
- Next piece: Add spreadsheet validation error feedback for unsupported formats or missing required columns.
```

### Session 1 (Branch 3 (Student Verification System)) — Verification Sheet Mini-Dashboard & UI Controls

**Files created/updated**
```
UI/Views/DashboardView.xaml (Added Automated Batch Verification action bar with [ ▶ Verify All (OCR) ] button and 3-metric Mini Dashboard cards for VERIFIED, UNDER REVIEW, and DID NOT REGISTER)
NPTEL-Manager.ps1 (Bound dynamic verification status counts to Mini Dashboard in Select-Course, wired BtnVerifyAll, added card click handlers, and initialized non-registered vs pending statuses in New-CourseVerificationSheet; loaded Download-Receipts and OcrEngine modules)
modules/Download-Receipts.ps1 (Built batch receipt downloader and ingestion module supporting Google Drive link extraction, offline local folder matching by roll number/name, resumable cache, and file type detection)
modules/OcrEngine.ps1 (Built native Windows PDF-to-Image rasterizer and OCR engine using Windows.Data.Pdf and Windows.Media.Ocr with zero external dependencies)
test_parse.ps1 (Added automated scriptblock compilation checks for all helper modules)
notes/Branch_3(Session_1).md (Web developer guide covering Command Center pattern, non-registered data partitioning, WPF mouse event bubbling, and native WinRT OCR)
Progress.md (Completed Phase A, Phase B & Phase C checklist items and updated session log)
```

**Decisions made this session**
- *Hub Action Layout*: Integrated the automated batch verification trigger and the 3-metric Mini Dashboard directly inside `PanelVerificationSheetActive` so the coordinator has a single dedicated command center.
- *Strict Jargon Ban*: Adhered strictly to plain academic/administrative labels: `VERIFIED` (Sage Green), `UNDER REVIEW` (Warm Amber), and `DID NOT REGISTER` (Muted/Bone White).
- *Automatic Non-Registered Partitioning*: Pre-classified students where `IsRegistered -eq $false` as `Did Not Register` so opting-out students are accurately surfaced immediately without requiring OCR attempts.
- *Hub and Spoke Readiness*: Added `Cursor="Hand"` and informative click handlers on all 3 Mini Dashboard cards, paving the way for seamless one-click navigation to `ReviewView` (Phase E) and `StudentListView` (Phase F).
- *Hybrid Online / Offline Ingestion*: Implemented dual receipt ingestion supporting both Google Drive direct download and offline local folder matching (matching Roll No or First Name), ensuring testing and isolated environments work seamlessly without internet or login friction.
- *Resumable File Cache*: Embedded checksum and file existence checks in `data/Courses/<CourseName>/receipts/<RollNo>_receipt.<ext>` to avoid redundant downloads across app sessions.
- *Human-Readable Course Storage*: Organized course files into human-readable course name directories (`data/Courses/<CourseName>/receipts/` and planned `data/Courses/<CourseName>/sheets/`) rather than raw UUIDs so coordinators can intuitively inspect files in Windows Explorer.
- *Zero-Dependency Native Windows OCR*: Leveraged Windows built-in `Windows.Media.Ocr` and `Windows.Data.Pdf` via WinRT, enabling high-speed PDF rendering and text recognition with zero third-party installations (no Tesseract/Ghostscript required).

**Known issues / TODO carried forward**
```
- Completed Phase A, Phase B, Phase C, and Course Directory Reorganization in Session 1.
```

### Session 2 (Branch 3 (Student Verification System)) — Phase D: 5-Rule Verification Matcher, Automated Pipeline & Smart Delta Response Sync

**Files created/updated**
```
modules/VerificationEngine.ps1 (Built 5-Rule Verification Matcher; built automated pipeline with delta sync; implemented Sync-CourseResponses with receipt URL change invalidation and dual JSON/Excel updates)
modules/OcrEngine.ps1 (Added rendered PNG page caching to skip redundant PDF rendering; ensured deterministic stream/page cleanup in finally block)
modules/Import-StudentSheet.ps1 (Centralized student store persistence functions Get-CourseStudentsFilePath, Save-CourseStudents, Get-CourseStudentStore, and Get-CourseStudents)
UI/Views/DashboardView.xaml (Added [ 🔄 Sync Responses ] button to Stage 1 attachment bar alongside Replace Sheet...)
NPTEL-Manager.ps1 (Wired [ 🔄 Sync Responses ] with dual file-source prompts and detailed breakdown dialog; fixed [ ▶ Verify All (OCR) ] closure binding and button null checks)
```

**Decisions made this session**
- *5-Rule Deterministic Evaluation*: Designed pure rule-based matching with no heuristic ambiguity (Rule 1 Status, Rule 2 Fee, Rule 3 space-insensitive Title, Rule 4 Authenticity, Rule 5 Identity greeting).
- *Delta Verification Sync*: Skip students already marked "Verified" unless explicitly forced (`-Force`), preserving manual coordinator approvals and saving OCR runtime.
- *Smart Delta Response Sync (`Sync-CourseResponses`)*: Separate hard file replacement (`[ Replace Sheet... ]`) from incremental Google Form merges (`[ 🔄 Sync Responses ]`).
- *Evidence-Based Re-verification*: If an existing student (even if previously "Verified") submits a new Google Drive link, the old receipt cache is purged and their status resets to "Pending" with an explicit alert in the sync report dialog.
- *Simultaneous Dual Persistence*: Both verification and delta sync pipelines update `data/Courses/<CourseName>/students.json` and `<CourseName>_Verification_Sheet.xlsx` simultaneously.

**Known issues / TODO carried forward**
```
- Completed Phase D, 5-Rule Matcher, and Smart Delta Response Sync in Session 2.
```

### Session 3 (Branch 3 (Student Verification System)) — Stage-Based Workspace Redesign, Multi-Page Router & Navigation Hardening

**Files created/updated**
```
UI/Views/WorkspaceView.xaml (New workspace overview landing page with breadcrumb, title, 4-column metric bar, and side-by-side interactive Stage 1 & Stage 2 cards with status badges)
UI/Views/Stage1View.xaml (Decoupled Stage 1 detail workspace with back navigation, linked sheet bar, sheet health panel, verification command center, 3 mini-dashboard cards, automated OCR bar, and in-app preview modal)
UI/Views/Stage2View.xaml (Dedicated Stage 2 detail workspace with back navigation, results upload card, active results state, and credit mapping placeholder)
NPTEL-Manager.ps1 (Refactored Select-Course to populate WorkspaceView, Stage1View, Stage2View; wired stage card navigation; separated Wire-ViewEvents per view; added $script:currentView tracking; fixed Unicode escape sequences with [char]0x2014 and [char]0x2713; guarded Select-Course against unwanted view switching on in-stage operations)
notes/Branch_3(Session_3).md (Web developer notes on stage pipeline UI architecture, SPA view lifecycle, cross-version PowerShell encoding traps, and context-aware state retention)
Progress.md (Recorded Session 3 completion, updated repo layout, added Branch 3 extra tasks, and updated session log)
```

**Decisions made this session**
- *Pipeline Stage Decoupling*: Decomposed the 700+ line monolithic `DashboardView.xaml` into a dedicated workspace hub (`WorkspaceView.xaml`) and focused stage-specific child views (`Stage1View.xaml` and `Stage2View.xaml`), matching the coordinator's mental model of the semester lifecycle.
- *Workspace Overview as Mission Control*: The top 4-column metrics bar (Total Registered, Exam Registered, Action Needed, Stage 2 Results) remains prominent on the Workspace landing page, while actionable sheets and heavy tooling (OCR, Health Check, Preview Modal) are neatly tucked inside their respective stages.
- *Dynamic Stage Status Computation*: Stage 1 card automatically displays `Complete ✓` (Sage Green) if all registered students have been verified, or `In Progress` (Warm Amber) if audits or receipts remain unverified. Stage 2 displays `Complete ✓` once official results are uploaded, otherwise `Pending`.
- *Cross-Version Character Robustness*: Replaced PowerShell 7-only `\u{...}` / `` `u{...} `` escape strings with native `[char]0x2014` (em-dash `—`) and `[char]0x2713` (checkmark `✓`), resolving raw `u{2014}` / `u{2713}` rendering bugs on Windows PowerShell 5.1 without requiring BOM encoding.
- *Context-Aware View Retention*: Introduced `$script:currentView` state tracking in `Navigate-To`. Enhanced `Select-Course` so in-stage actions (e.g. `[ ▶ Verify All (OCR) ]`, `[ Recheck Health ]`, `[ Replace Sheet... ]`) update all UI bindings in-place and keep the coordinator on their active stage view rather than jarringly routing back to the Workspace cards.
- *Preserved Legacy Compatibility*: Retained `DashboardView.xaml` safely on disk while cleanly redirecting all application routes and event listeners to the new decoupled view architecture.

**Known issues / TODO carried forward**
```
- Completed Phase D, 5-Rule Matcher, and Stage-Based Workspace Redesign in Sessions 2 & 3.
```

### Session 4 (Branch 3 (Student Verification System)) — Review Workspace, Decoupled Pipeline, Resubmission De-Duplication & "Update Sheet" Engine

**Files created/updated**
```
UI/Views/ReviewView.xaml (Added TxtReviewBreadcrumb, TxtReviewCountBadge styling, and BtnBackToStage1; built 2-state split-screen ReviewWorkspaceGrid with student info, verification diagnostics, and zoomable receipt viewer with ScaleTransform)
UI/Views/WorkspaceView.xaml (Added Delete Course button to workspace header)
UI/Views/Stage1View.xaml (Modernized Automated Engine into 2-step pipeline with BtnDownloadReceipts, BtnVerifyAll, and dynamic TxtPipelineStatus cache label; replaced separate Replace Sheet / Sync with unified BtnUpdateSheet)
UI/Views/DashboardView.xaml (Added BtnDownloadReceipts and unified BtnUpdateSheet to match Stage1View)
modules/Import-StudentSheet.ps1 (Enhanced Get-CourseStudentsFilePath; implemented smart de-duplication in Import-StudentSheet where later rows overwrite earlier submissions by RollNo, tracking DuplicateCount and SupersededRolls; initialized DuplicateCount and SupersededRolls on PSCustomObject result to fix property assignment error)
modules/VerificationEngine.ps1 (Added -SkipDownload switch to Invoke-CourseVerificationPipeline; updated Sync-CourseResponses to de-duplicate rows, track DuplicateCount, and automatically delete old cached receipt files for resubmitted students)
NPTEL-Manager.ps1 (Cleaned non-ASCII characters; evaluated MessageBox arguments outside call to fix PS5.1 syntax error; wired BtnDownloadReceipts and SkipDownload in BtnVerifyAll; implemented unified Update Sheet handler with choice dialog to re-scan current file or browse new file, de-duplicate rows, purge old receipts, and re-sync metrics)
notes/Branch_3(Session_4).md (Comprehensive educational notes covering Review Workspace, Decoupled Pipeline, Resubmission De-Duplication, and Update Sheet Engine)
Progress.md (Recorded Session 4 progress, checked off Phase E Items 1 & 2, logged Course Deletion, Metric Sync fix, Decoupled 2-Step Pipeline, and Smart Resubmission De-Duplication & Update Sheet Workflow)
```

**Decisions made this session**
- *Dedicated Review Flow*: Routed the Stage 1 `UNDER REVIEW` mini-dashboard card directly to `ReviewView.xaml`, ensuring coordinators can seamlessly jump from status metrics into flagged submissions.
- *In-Place Metric Sync on Return*: Wired `BtnBackToStage1` to invoke `Select-Course` with `-TargetView "Stage1View"`, guaranteeing that any modifications made during review immediately synchronize back with the Stage 1 dashboard.
- *Dynamic Review Queue Cards*: Designed card components in `ReviewItemsListHost` displaying Roll Number, Student Name, Warm Amber Review Badge, and discrepancy remark snippets, with zero mock data and automatic empty state handling ("Queue is Clear").
- *Split-Screen Review Workspace*: Implemented a 2-column layout inside the review workspace separating student registration metadata & diagnostics on the left from interactive receipt viewing on the right.
- *Native Zoom & File Release*: Used WPF `ScaleTransform` inside a `ScrollViewer` for zoom controls (25% to 400%), loaded bitmaps with `CacheOption = OnLoad` and `.Freeze()` to release file locks immediately, and integrated single-receipt fallback download and external viewer launching.
- *Safe Course Deletion Workflow*: Added a confirmation dialog guarding against accidental deletion, removed courses cleanly from `courses.json`, cleared local student caches (`data/Courses/<CourseName>`), updated active state and header badges, and added Delete buttons to both `CoursesView` cards and the `WorkspaceView` header.
- *Metric Synchronization & Store Path Hardening*: Fixed parameter omissions in `Select-Course` and related store calls by explicitly forwarding `-CourseName` to `Get-CourseStudentStore` and `Save-CourseStudents`. Hardened `ArrayList` type preservation during course deletion and creation, ensuring Stage 1 dashboard mini-cards accurately read verified counts (4 Verified, 2 Under Review) from `data/Courses/<CourseName>/students.json` without raw GUID duplication.
- *Decoupled 2-Step Verification Pipeline*: Separated receipt downloading from OCR verification. Added `[ 📥 Download Receipts ]` to fetch missing files with Google Drive permission failure reporting, and modernized `[ ▶ Run Verification (OCR) ]` with an on-disk cache check and `-SkipDownload` offline execution mode. Dynamic status label `TxtPipelineStatus` tracks the number of on-disk receipts in real-time.
- *Smart Resubmission De-Duplication & "Update Sheet" Workflow*: Replaced confusing separate "Replace Sheet" and "Sync" buttons with a single, clear "Update Sheet" action. The parser automatically de-duplicates entries by Roll No (or Email) where the latest submission wins. When a student resubmits a new receipt URL, the old receipt file on disk is deleted so stale OCR data is purged, and the student's status is reset for re-verification. An interactive prompt lets the coordinator either re-scan the currently attached sheet or browse a newly downloaded file.

**Known issues / TODO carried forward**
```
- Completed Phase E Review Queue & Split-Screen Workspace in Session 4.
```

### Session 5 (Branch 3 (Student Verification System)) — Phase E Completion: 1-Click Actions, Review Mini Dashboard & Staged Push Workflow

**Files created/updated**
```
UI/Views/ReviewView.xaml (Overhauled with 2-mode architecture based on coordinator sketch: Mode A Review Queue Overview with 3-card Mini Dashboard [TOTAL ISSUES, SOLVED IN THIS SESSION, PENDING], Push Changes to Main Sheet bar with live ready badge, and 3-column table header [ENROLLMENT, STUDENT NAME, QUICK ACTIONS with Width="Auto"]; upgraded heading typography to Segoe UI SemiBold 26pt #FFFFFF; Mode B split-screen student inspection workspace with Back to Queue button, zoomable viewer, and ModalFlagResubmit)
modules/VerificationEngine.ps1 (Added Export-CourseVerificationSheetData helper to synchronize updated student verification remarks and statuses to the course verification spreadsheet)
modules/OcrEngine.ps1 (Added [switch]$Force parameter to ConvertTo-ReceiptImage to support force-rendering staged receipts; added timestamp-aware cache invalidation; added Get-ReceiptText compatibility wrapper function forwarding to Invoke-ReceiptOcr)
NPTEL-Manager.ps1 (Added review session tracking state [$script:reviewSessionSolvedRolls, $script:reviewStagedSolved]; refactored Update-ReviewView to calculate Mini Dashboard metrics, manage Push Action Bar state, and dynamically render 3-column student card rows with 4 Quick Actions [Issues, Receipt, Approve/Unapprove toggle, Open Student]; wired toggleable [ Approve ] ⇄ [ Unapprove ] with full status/remarks restoration; simplified staged badge to strictly 'Solved' [no tick, no extra text]; wired Push Changes to Main Sheet to commit staged students to students.json and sync <CourseName>_Verification_Sheet.xlsx; wired Mode B navigation with Back to Queue; wired BtnAttachLocalReceipt with safe staging, 5-rule OCR, and safe purge on approval; zero-lock MemoryStream loading; 100% clean ASCII)
notes/Branch_3(Session_5).md (Created comprehensive educational notes for Session 5 including documentation of the 2-mode Review View Mini Dashboard architecture, toggleable approval, simplified badge, and heading typography polish)
Progress.md (Completed Phase E checklist, recorded Session 5 progress and ad-hoc tasks, and targeted Phase F Student Roster & Export)
```

**Decisions made this session**
- *2-Mode Review View Architecture (Coordinator Sketch)*: Transformed `ReviewView.xaml` into a 2-mode system: Mode A presents the Review Queue Overview Table with the Review Progress Mini Dashboard and Push Bar, while Mode B offers the detailed split-screen workspace with `[ ← Back to Queue ]` navigation.
- *Review Progress Mini Dashboard*: Displays 3 key session metrics: `TOTAL ISSUES`, `SOLVED IN THIS SESSION`, and `PENDING`. Formulas dynamically ensure mathematical consistency (`Pending = Total - Solved in Session`).
- *Staged Push Workflow (`BtnPushSolvedChanges`)*: Rather than immediately writing each individual override directly to Excel, approvals stage the student in session memory with a visible `Solved` badge (no checkmark, no extra text). Clicking `[ Push Changes to Main Sheet ]` commits all staged students in a single batch, updating `students.json` and synchronizing the verification spreadsheet, which immediately decrements `Under Review` and increments `Verified` on the Stage 1 panel.
- *Streamlined 3-Column Review Queue Table & 4 Quick Actions*: Each student appears as an individual card row with dividers: `ENROLLMENT` (monospace), `STUDENT NAME` (with hover tooltip displaying issues summary), and `QUICK ACTIONS` (`Width="Auto"`, right-aligned to eliminate badge clipping) featuring 4 Quick Action buttons:
  - `[ Issues ]`: Displays clean dialog detailing the verification failure reasons and OCR diagnostics (renamed from Diagnostics).
  - `[ Receipt ]`: Opens the student's saved receipt file directly in the Windows default viewer.
  - `[ Approve ]` ⇄ `[ Unapprove ]`: Dynamic toggle button. Clicking `[ Approve ]` stages the student and turns into `[ Unapprove ]`; clicking `[ Unapprove ]` prompts for confirmation and cleanly restores original remarks/status and decrements session count.
  - `[ Open Student ]`: Transitions into Mode B to inspect the full split-screen details.
- *In-App Flag for Resubmit Modal*: Rather than clunky external dialogs, designed an in-app dark modal overlay (`ModalFlagResubmit`) equipped with 4 one-click preset buttons (*Blurry Receipt*, *Wrong Course Name*, *Drive Access Denied*, *Fee Incomplete*) plus a custom multi-line text input.
- *Automated OCR & Safe Staged Replacement*: When attaching a receipt (PDF or image), the new file is staged first without deleting the old receipt. The system automatically runs OCR against the 5 verification rules. If all rules match, an approval prompt appears (*"All 5 rules matched! Approve now?"*). Only upon approval are old receipts safely purged, preventing any data loss from accidental file selections.
- *Zero-Lock Memory Streaming & De-Duplication*: Fixed WPF unmanaged image handle locking and URI memory caching by loading receipt images through `[System.IO.File]::ReadAllBytes` and an unmanaged `MemoryStream`. Purged old receipts across all extensions (`${cleanRoll}_receipt*`) on replacement, and prioritized newest files via `Sort-Object LastWriteTime -Descending`.
- *Zero-Encoding-Risk ASCII UI*: Preserved 100% clean ASCII throughout all `.ps1` code strings (`[char]0x2014`, `[char]0x25CF`, `[char]0x2713`) to prevent Windows PowerShell 5.1 ANSI decoding issues.

### Session 6 (Branch 3 (Student Verification System)) — Collapsible Sheet Health, Local/ZIP Receipt Ingestion, Adaptive Pipeline Bar & PS 5.1 Hardening [COMPLETED]

**Files created/updated**
```
modules/Download-Receipts.ps1 (Enhanced Find-LocalReceiptMatch with multi-token name matching; added Import-ReceiptsFromLocalSource supporting both local folders and auto-extracted .zip archives with 4-tier matching [RollNo, Full Name, First+Last token, Unique First Name] and temp folder cleanup)
UI/Views/Stage1View.xaml (Added BtnImportReceipts toolbar button; collapsible Sheet Health Details panel with toggle button [View Details ▼ / Hide Details ▲]; decluttered Automated Verification Pipeline removing Step 1/Step 2 text clutter; added single collapsible adaptive PanelPipelineProgress bar with live percentage and student ticker)
NPTEL-Manager.ps1 (Wired BtnImportReceipts with dual-source picker [.zip archive or folder]; integrated Import-ReceiptsFromLocalSource; fixed scope closure bug on BtnToggleHealthDetails using $this; script-scoped Update-PipelineBarState with 60fps WPF Dispatcher render queue pumping; fixed PS 5.1 UnexpectedToken syntax errors by pre-evaluating ternary string fragments; sanitized multi-byte characters to safe ASCII)
modules/Import-StudentSheet.ps1 (Added defensive property initialization for VerificationStatus and VerificationRemarks; widened IsRegistered regex to tolerate typos like "Reistration Done")
modules/VerificationEngine.ps1 (Defensive Add-Member checks on VerificationStatus to prevent property assignment errors; expanded Rule 2 for SC/ST/PwD ₹500/₹550 fee concessions with comma/decimal normalization)
notes/Branch_3(Session_6).md (Comprehensive educational notes covering 10 topics: Defensive Property Injection, WPF Scope Closures, Collapsible Sheet Health, Direct Native File Explorer, Local Ingestion Engine, Fee Concession Matching, PS 5.1 ASCII Encoding, Clean Adaptive Pipeline Bar, Script-Scope State Managers & Dispatcher Pumping, and PS 5.1 Pre-Evaluation Pattern)
Progress.md (Recorded Session 6 progress and closed Session 6)
```

**Decisions made this session**
- *Pipeline Button Placement*: Positioned `[ 📁 Import Receipts ]` to the left of `[ 📥 Download Receipts ]` in Stage 1, providing coordinators with an immediate local alternative when Google Drive links have restricted permissions.
- *Dual-Source Ingestion (ZIP or Folder)*: Coordinators can either point to an unzipped folder or directly pick a downloaded Google Drive `.zip` file without manual extraction. The engine unpacks archives into a secure temp directory and cleans it up in a `finally` block.
- *4-Tier Smart Matching Engine*: Implemented high-confidence matching across:
  - Tier 1: Clean Roll Number match (100% confidence).
  - Tier 2: Clean Student Full Name match (98% confidence, matching Google Forms `<filename> - <Student Name>.<ext>` pattern).
  - Tier 3: First + Last token match (95% confidence).
  - Tier 4: Unique First Name match (90% confidence, only if the first name is unique among registered students).
- *Collision & Duplication Prevention*: Used hash-set tracking to ensure each file in the source is assigned to at most one student, and existing on-disk receipts are preserved by default.
- *Collapsible Sheet Health Panel*: Added a compact, collapsed-by-default Sheet Health header displaying live metrics (`Total Students • Exam Registered • Detected/7 Standard Columns`) with a toggle button `[ View Details ▼ ]` ⇄ `[ Hide Details ▲ ]` and categorized impact guidance for Critical vs Optional columns.
- *Fee Rule Concession Support (Rule 2)*: Expanded Rule 2 in `modules/VerificationEngine.ps1` to accept both standard NPTEL fees (₹1,000 / ₹1,100 late fee) and official SC/ST/PwD 50% concession fees (₹500 / ₹550 late fee). Made amount matching robust against comma separators (`1,000`), decimals (`1000.00`), and spaces. Automatically records `Fee: Rs. 500 (Concession)` in verified remarks. Ready for future configurable course fee settings.
- *Clean & Adaptive Verification Pipeline Bar*: Replaced multi-step text overhead ("Step 1...", "Step 2...", duplicate titles) with a unified card title (*Automated Verification Pipeline*), a single status pill (*IDLE / READY*), and a single collapsible progress container (`PanelPipelineProgress`). The container dynamically morphs its headline, accent brush, and live monospace student ticker across Import, Download, and OCR verification.
- *Script-Scoped Pipeline State & 60fps Dispatcher Render Pumping*: Promoted `Update-PipelineBarState` to script scope (`$script:`) to prevent runtime closure scope loss (`Update-PipelineBarState is not recognized`). Implemented `[System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)` on each student tick to guarantee smooth non-blocking 60fps UI repaints during long-running verification loops.
- *Windows PowerShell 5.1 Parser Compatibility & Pre-Evaluation Pattern*: Eliminated inline ternary concatenations (`"$stRoll" + (if ($stName) ... )`) which trigger `Unexpected token 'if'` errors in the Windows PowerShell 5.1 language parser. Standardized on intermediate pre-evaluated local variables (`$nameStr = if ($stName) { " - $stName" } else { "" }`), ensuring 100% crash-free execution across all Windows machines out of the box.
- *Session 6 Closed*: Successfully completed all Stage 1 verification pipeline enhancements, fee concession support, local ingestion mechanics, and PS 5.1 parser resilience.

**Known issues / TODO carried forward**
```
- Completed Session 6 (Branch 3).
```

### Session 1 (Branch 4 (Send Email)) — Dedicated Email UI, Review Entry Point & Zero-Password Browser Dispatch [COMPLETED]

**Files created/updated**
```
UI/Views/EmailView.xaml (Created dedicated Email Management Center view: 2-column layout with 3-card mini dashboard [Flagged Recipients, Already Notified, Discrepancy Summary], interactive student recipient roster with batch Select All / Clear All, multi-template notice composer [Missing Receipt, Fee Mismatch, General Notice], live monospace body preview, and dispatch action bar)
UI/Views/ReviewView.xaml (Added responsive [✉ Send Email to Flagged Students] action bar button in ReviewQueueOverviewPanel alongside Push Changes)
NPTEL-Manager.ps1 (Wired [✉ Send Email to Flagged Students] to Open-EmailView; implemented Open-EmailView and Update-EmailView with automatic roster filtering for 'Under Review' students; added Update-EmailComposerPreview for dynamic template generation; added Update-EmailSelectionMetrics for live student count badges; wired [📋 Copy Notice Text] for WhatsApp/Telegram; wired [📋 Copy BCC Emails] with clipboard export; implemented 1-click [✉ Open in Gmail (Web Draft)] URL compose with BCC list, auto-marking students as Notified with timestamp in students.json; updated Navigate-To to maintain active tab styling on EmailView)
notes/Branch_4(Session_1).md (Educational documentation for Branch 4 Session 1)
Progress.md (Updated Branch 4 checklist and logged Session 1)
```

**Decisions made this session**
- *Review Queue Action Bar Integration*: Placed `[ ✉ Send Email to Flagged Students ]` directly on the primary Mode A action bar in `ReviewView.xaml`, dynamically indicating the exact number of flagged students needing outreach (e.g. `✉ Send Email to Flagged (3 Students)`). Disabled cleanly when the queue is clear.
- *Two-Column Responsive Email Management Center*: Designed `EmailView.xaml` following the Zinc Warm Dark aesthetic with a 420px left-hand Recipient Roster and a flexible right-hand Notice Composer & Live Preview panel.
- *Discrepancy Category Extraction*: `Update-EmailView` scans verification remarks to automatically categorize issues into *Missing Receipt* vs *Fee Discrepancy* and displays a live mini-metric breakdown (`2 Missing Receipt • 1 Fee Discrepancy`).
- *Two-Function Composer Architecture*: Consolidated the notice composer into two clear functions:
  1. `[ 📋 Standard Template (5 Rules) ]`: Automatically pre-fills an authoritative institutional resubmission notice detailing the 5 mandatory verification criteria (Payment Status, Fee Amount, Course Name, Platform Authenticity, Student Identity) and common rejection reasons, covering all discrepancy scenarios in a single BCC notice.
  2. `[ ✏️ Custom Draft Mail ]`: Provides an editable canvas with dynamic subject line and starter skeleton for custom announcements (e.g. Google Form resubmission links, physical lab verification schedules, deadline extensions).
- *Unique Student Identification & Shared Email Resolution*: Fixed bug where multiple students sharing a test or common email address caused `break` to prematurely terminate evaluation and accidentally tag `Verified` students. Refactored `Get-SelectedStudents` to extract student objects and `Mark-SelectedStudentsNotified` to match strictly by unique `RollNo` and `Under Review` status.
- *Zero-Password Browser Draft Launcher (Sub-Branch 4.1)*: Coordinators can dispatch notices without configuring any SMTP credentials or App Passwords. Clicking `[ ✉ Open in Gmail (Web Draft) ]` constructs an RFC-compliant Gmail Web Compose URL (`https://mail.google.com/mail/?view=cm...`) with all checked students placed in the `BCC` line (protecting student privacy) and opens the default web browser.
- *Multi-Channel Outreach (WhatsApp / Telegram / Circulars)*: Provided `[ 📋 Copy Notice Text ]` for instant copy-pasting into class groups or messaging apps, and `[ 📋 Copy BCC Emails ]` for standalone email clients.
- *Delivery & Audit Tracking*: Launching the draft marks students as `Notified = $true` with a formatted timestamp (`NotifiedTimestamp = "YYYY-MM-DD HH:mm"`) in `students.json`, instantly rendering a green `✓ Notified` badge in both the roster and the dashboard.
- *Seamless SPA Navigation Triangle*: Enabled bidirectional routing between `Stage1View` ⇄ `ReviewView` ⇄ `EmailView`, maintaining tab highlighting on the Courses tab.
- *WPF Event Scope Closure Elimination*: Promoted `Set-EmailTemplate` to a dedicated script-scoped function, eliminating a runtime `The expression after '&' in a pipeline element produced an object that was not valid` exception caused by invoking an out-of-scope local scriptblock on button click.
- *Email Center UI Declutter & Modernization*: Streamlined `EmailView.xaml` following coordinator feedback: shortened main title to `Email Center`, deleted paragraph subtitles, removed the redundant gray info pill from the roster (gaining 30px vertical viewport), simplified metric card headers (`FLAGGED`, `NOTIFIED`, `ISSUES`), shortened template toggle buttons to `[ 📋 Standard (5 Rules) ]` and `[ ✏️ Custom Draft ]`, and streamlined action bar buttons (`[ 📋 Copy Notice ]`, `[ ✉ Open in Gmail ]`).
- *2-Way Delivery Status Management*: Introduced a dual-path delivery audit architecture. Way 1 (Automated): `[ ✉ Open in Gmail ]` launches the browser draft and flags records as notified with an informative rollback tip. Way 2 (Manual): Added `[ ✓ Mark Notified ]` and `[ ↺ Unmark ]` toolbar controls above the recipient roster, allowing the coordinator to manually verify delivery across other email channels (Outlook, college portal) and instantly undo/revert notifications if an external send was canceled or failed.
- *Decommissioned Redundant 'Flag for Resubmit' Workflow*: Removed the redundant `[ Flag for Resubmit ]` button and `ModalFlagResubmit` popup dialog from `ReviewView.xaml` and `NPTEL-Manager.ps1`. Since every student appearing in the Review Queue is already marked `Under Review` (flagged), re-flagging was redundant and conceptually confused coordinators. Mode B now has a clear single primary decision: `[ Approve (Override) ]` (or do nothing to leave them flagged for batch email notice).

**Known issues / TODO carried forward**
```
- Sub-Branch 4.2: Direct in-app SMTP background dispatch with Windows DPAPI encryption in SettingsView.xaml and modules/EmailEngine.ps1.
```

### Session 1 (Branch 5 (Stage 2: Examination Results & Final Sheet)) — Ingestion Engine, Health Auditing, Result Verification Sheet & Collapsible Workspace [COMPLETED]

**Files created/updated**
```
modules/Import-StudentSheet.ps1 (Added Get-ExamResultsColumnMapping with defensive whitespace/colon trimming; added Import-ExamResultsSheet with Excel serial date conversion, declared marks extraction [/25, /75, /100], and Roll No de-duplication; added Get-CourseExamResultsStore and Save-CourseExamResultsStore persisting to data/Courses/<CourseName>/exam_results.json)
UI/Views/Stage2View.xaml (Replaced placeholder with complete 3-card stack: Stage 2 Attachment Card with raw sheet update/open/preview; Examination Sheet Health panel with collapsible 9-column detection badges including Email and duplicate counter; Result Verification Sheet panel with State A [Prompt] and State B [Active with File Location Bar, pipeline bar, adaptive progress bar, 3-card mini dashboard: VERIFIED, UNDER REVIEW, CERTIFICATE MISSING, and export strip]; and in-app modal preview overlay)
UI/Views/Stage1View.xaml (Added BtnToggleVerificationPanel ['Open Sheet ▼' / 'Close Sheet ▲'] and wrapped pipeline bar, mini cards, and summary strip inside collapsible VerificationSheetDetailsContainer)
NPTEL-Manager.ps1 (Added New-CourseExamVerificationSheet duplicating exam responses and appending 'Verification Status' and 'Verification Remarks' columns; updated Update-Stage2View with breadcrumb, health numbers, column badge binding, and state toggle; sanitized non-ASCII strings to [string][char]0x2014 for Windows PowerShell 5.1; applied Skill 1 dynamic control resolution across all Stage 1 & Stage 2 event handlers)
Progress.md (Registered Branch 5 phases A-F; logged Session 1; added ## 7. Skill with Skill 1: WPF Event Scoping & Dynamic Control Resolution in PowerShell)
```

**Decisions made this session**
- *Non-Intrusive Email Column*: Included `Email` as an optional 9th standard column in Stage 2 health detection to assist coordinator communications without failing the critical health audit or blocking certificate OCR.
- *Strict Under Review Policy for Decimal Marks*: Re-affirmed that student marks differences (including decimal/rounding mismatches like 25 vs 24.67) must strictly route to `Under Review` with detailed remarks, rather than being auto-rounded.
- *College Final Result Sheet — No Medal Tiers*: Per college guidelines, the generated final result sheet will strictly list academic marks and credits without medal designations (Elite / Silver / Gold).
- *Explicit Result Verification Sheet Generation*: Rather than automatically exposing the raw responses as the verification sheet, Card D starts in State A (`[ + Generate Result Verification Sheet ]`). Clicking this generates `<Course>_Result_Verification_Sheet.xlsx` alongside the raw responses sheet, appending official `Verification Status` and `Verification Remarks` columns.
- *Collapsible Verification Sheet Panel Architecture*: Both Stage 1 and Stage 2 active verification panels are collapsed by default upon generation, displaying only the compact File Location Bar. Clicking `[ Open Sheet ▼ ]` dynamically expands the pipeline controls, mini dashboard cards, and export strip, and morphs the button to `[ Close Sheet ▲ ]`.
- *Windows PowerShell 5.1 Parse Hardening*: Replaced non-ASCII literal Unicode characters (`—`, `₹`, `↺`) with runtime tokens (`[string][char]0x2014`) to prevent Windows PowerShell 5.1 from misinterpreting multi-byte UTF-8 sequences as Windows-1252 quotes.
- *Skill 1: WPF Event Scoping in PowerShell*: Documented and applied the mandatory rule that `.NET` event scriptblocks (`Add_Click`) must dynamically resolve controls via `$script:views[...]` and `$this` rather than referencing outer function-local variables that evaluate to `$null`.

**Known issues / TODO carried forward**
```
- Next piece: Branch 5 Phase B (Certificate Ingestion & 4-Tier Matching via modules/Download-Receipts.ps1).
- Next unchecked checklist item for Branch 5: Task B.1 (Reuse Google Drive direct batch downloader from modules/Download-Receipts.ps1).
```

---


## 4. Project-Wide Decisions

- **Color Palette & Theme**: Zinc Warm Dark Minimalism based on `Design.md` (`#151513` canvas, `#1E1E1B` panel, `#E8B04B` warm amber accent, `#5B8C7B` sage green, `#EAE6DD` bone white text, `#2A2A24` borders).
- **Desktop Architecture**: Native PowerShell 5.1/7 + WPF. Zero cloud dependencies, zero hosting cost, runs directly on coordinator's Windows PC.
- **Storage Strategy**: Local lightweight JSON database (`data/courses.json` and `data/students_<courseId>.json`) and human-readable course folders (`data/Courses/<CourseName>/receipts/`). No SQL server setup required.
- **Workflow Scope**: Course-centric workspace model. Every course has its own scoped enrollment sheet, verification queue, and eventual exam results.

---

## 5. Session Rules (How Assistant Must Work)

- **Opening handshake — before writing or touching any code:**
  1. Ask which branch I'm working on. Find that branch's highest `### Session N (Branch N (Name))` heading.
  2. State back: *"Branch [N] ([Name]) — last recorded Session [N]. Last unchecked checklist item for this branch: [X]."*
  3. Wait for confirmation before touching any code.

- **One piece at a time & Ask Before Coding**: Build only the next unchecked item. Always explain what will be built and wait for explicit confirmation from the user BEFORE implementing or writing any code. No jumping ahead.

- **Incremental writes — never batch at the end.** After each file/task is finished, give a small paste-ready update:
  ```
  ✅ Done: <file> — <what/why, one line>
  → 1. Tick the box in Section 2, that branch's checklist:
       - [x] <checklist item> [Session N]
  → 2. Add to that branch's Sessions Log under "### Session N (Branch N (Name))":
       - <file>: <what/why>
  ```

- **Empty branch?** If the chosen branch has no tasks in its checklist, ask for tasks before building.

- **Ad-Hoc / "Extra" Tasks Rule**: If during a session work diverts to an unlisted or ad-hoc task requested by the user instead of the next scheduled checklist item:
  1. Always propose the plan and ask for confirmation before coding.
  2. Implement and verify the task.
  3. By default, add it to the active branch's checklist under `#### Extra / Ad-Hoc Completed Tasks`, marked `[x] <task> [Session N]`.
  4. Record the file and decisions in the active session's log and session notes.
  5. Resume the scheduled roadmap.

- **End of session:** Provide the exact text to paste into Files, Decisions, Repo layout, and the checklist.

---

## 6. Session Prompt (Copy-Paste for New Sessions)

```
Continue the NPTEL Management System project from where Progress.md leaves off.

Attached/linked: my repo and Progress.md.

Rules for this session:

0. OPENING HANDSHAKE — before touching any code:
   a. State back: "Branch [N] ([Name]) — last recorded Session [N]. Last unchecked checklist item for this branch: [Task]."
   b. Wait for me to confirm or correct.
   c. Only start proposing the first task after I confirm.

1. Read Progress.md fully — the checklist, decisions, and repo layout are your only memory of this project.
2. Build ONLY the next unchecked item for that branch. One piece at a time.
3. ALWAYS ask before coding: Propose what you plan to do for the task and wait for my explicit confirmation BEFORE implementing or writing any code.
4. Handling Extra Tasks: If I ask to work on an ad-hoc or unlisted task, propose the plan, ask before coding, implement it, and by default add it under '#### Extra / Ad-Hoc Completed Tasks' marked [x] ... [Session N], then resume the scheduled roadmap.
5. Write the simplest, most beginner-friendly code possible.
6. Don't scaffold future folders. Only create files this piece needs.
7. INCREMENTAL WRITES — after each finished file/task, give me a paste-ready update.
8. When done, give me: new/changed files, plus the exact text to paste into Files, Decisions, Repo layout, and the checklist.
```

---

## 7. Skill

### Skill 1: WPF Event Scoping & Dynamic Control Resolution in PowerShell

**The Golden Rule:**  
Never reference local outer-scope variables inside a `.NET` / WPF event scriptblock (e.g. `Add_Click({ ... })`, `Add_TextChanged({ ... })`, `Add_MouseLeftButtonUp({ ... })`). Event scriptblocks in PowerShell do NOT automatically close over outer function-local variables; at the time of execution, those local variables evaluate to `$null`, causing:
`The property 'Visibility' cannot be found on this object` or `The property 'Content' cannot be found on this object`.

**The Mandatory Resolution Pattern:**
Whenever writing or modifying an event handler inside a view:
1. **Always use `$this`** to access the element that triggered the event (e.g. the clicked Button, TextBox, or CheckBox):
   ```powershell
   $btn = $this
   ```
2. **Always resolve sibling/child controls dynamically** from the view container stored in `$script:views`:
   ```powershell
   # BAD (DO NOT DO THIS):
   $btnToggle.Add_Click({
       if ($detailsContainer.Visibility -eq [System.Windows.Visibility]::Visible) { ... }
   })

   # GOOD (ALWAYS DO THIS):
   $btnToggle.Add_Click({
       $view = $script:views["Stage2View"]
       $container = if ($view) { $view.FindName("ExamHealthDetailsContainer") } else { $null }
       $btn = $this
       if ($container -and $btn) {
           if ($container.Visibility -eq [System.Windows.Visibility]::Visible) {
               $container.Visibility = [System.Windows.Visibility]::Collapsed
               $btn.Content = "View Details " + [char]0x25BC
           } else {
               $container.Visibility = [System.Windows.Visibility]::Visible
               $btn.Content = "Hide Details " + [char]0x25B2
           }
       }
   })
   ```
3. **Pass contextual metadata via `.Tag`**:
   If an element needs specific record data (like a student Roll No or file path), bind it to `$element.Tag` at initialization time and read `$this.Tag` inside the event handler.

