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
│   └── Branch_3(Session_3).md     # Notes for Branch 3 Session 3 (Stage-Based Workspace & Router)
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

**Notes tracking:** Session notes in `notes/` directory: `Branch_1(Session_1).md`, `Branch_2(Session_1).md`, `Branch_2(Session_2).md`, `Branch_2(Session_3).md`, `Branch_2(Session_4).md`, `Branch_3(Session_1).md`, `Branch_3(Session_2).md`, `Branch_3(Session_3).md`.

---

## 1. Branches & Numbering

| # | Name | Purpose | Status |
|---|------|---------|--------|
| 1 | Main | Core build, in planned order | Paused |
| 2 | Dealing with sheet in our app | Import, parse, validate student enrollment sheet & handle sheet operations | Paused |
| 3 | Student Verification System | Batch download receipts, OCR extraction, rule-based verification, and discrepancy review | In progress |

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
- [ ] Wire Mini Dashboard `[ UNDER REVIEW ]` card to navigate to `ReviewView.xaml`
- [ ] Build split-screen review workspace: student details on left, zoomable receipt image on right
- [ ] Implement 1-click coordinator actions: `[ Approve Override ]` and `[ Flag for Resubmit ]`
- [ ] Add `[ ← Back to Dashboard ]` header navigation button with instant metric synchronization

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
- Next piece: Phase E — Review & Discrepancy Queue (ReviewView.xaml) to inspect students in "Under Review" state with split-screen receipt zoom and coordinator override actions.
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
