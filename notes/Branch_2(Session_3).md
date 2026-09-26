# Branch 2 (Session 3) — Local JSON Course Database & Decoupled State Architecture

> **Target Audience:** Web Developer learning Desktop Engineering (PowerShell + WPF)  
> **Topic:** Local Storage Caching, Lazy Ingestion, File Locking Protection, and Decoupled Database Design  
> **Date:** September 2026  

---

## 1) The Excel Re-Parsing Bottleneck vs. Local JSON Storage

### 1.1 The Problem
In web development, when a user uploads a CSV file through an `<input type="file" />`, you never re-parse the raw file from disk every time the user navigates between dashboard tabs. Instead, you parse the CSV once, insert the records into your database (e.g. PostgreSQL or MongoDB), and query the database.

In our desktop app, previously the dashboard was re-running `Import-StudentSheet` on the raw `.xlsx` file whenever a course workspace was opened. This introduced three major problems:
1. **Performance Lag**: Reading and unzipping an XML `.xlsx` archive with 200+ rows takes 500ms–1500ms, causing UI stuttering.
2. **File Locking (`EBUSY` / IOException)**: If the coordinator opens their spreadsheet in Microsoft Excel, Windows places an exclusive write-lock on the file. If our app tries to read or modify it, the app crashes or throws access violations.
3. **No Place to Save Coordinator Decisions**: When a coordinator marks a student as `[Verified]` or flags an exception, we cannot and should not write custom application metadata back into the coordinator's personal Excel file.

### 1.2 The Fix — Local Scoped JSON Databases
We introduce a local JSON storage pattern scoped per course:  
**`data/students_<courseId>.json`**

Whenever a sheet is attached or loaded, the normalized student records are written to this JSON file. Subsequent reads load directly from JSON in under `2ms`.

```powershell
function Get-CourseStudentsFilePath {
    param([string]$CourseId)
    return (Join-Path $dataDir "students_$CourseId.json")
}

function Save-CourseStudents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CourseId,
        [Parameter(Mandatory = $true)]
        $Students
    )
    $filePath = Get-CourseStudentsFilePath $CourseId
    $json = ConvertTo-Json @($Students) -Depth 6
    Set-Content -Path $filePath -Value $json -Encoding UTF8
}
```

```text
❌ WRONG:  Re-reading the raw .xlsx spreadsheet from disk on every page view or tab switch:
           Import-Excel $Course.RegistrationSheet (Slow, prone to file-locking crashes)

✅ RIGHT:  Loading from pre-parsed local JSON cache:
           Get-CourseStudents -CourseId $Course.Id (Instant 2ms read, zero file lock risks)
```

**Rule:** Treat user spreadsheets as read-only import sources, never as live operational databases. Always ingest them once into your own local data store.

**Why?** Converting imported spreadsheets to local JSON decouples our application from Microsoft Office, eliminates file-locking conflicts, and provides instant `0ms` load times.

---

## 2) Lazy Ingestion & Auto-Healing Cache Strategy

### 2.1 The Problem
What happens if:
- A course was created before this caching feature existed?
- The coordinator cleared their `data/` folder?
- The JSON file was accidentally deleted?

If `Get-CourseStudents` strictly checked for the JSON file and failed, the course workspace would appear empty with `0` students, even though a valid spreadsheet was still attached on disk.

### 2.2 The Solution — Lazy Ingestion with Self-Healing
We designed `Get-CourseStudents` with a lazy-loading fallback:
1. First, check if `data/students_<courseId>.json` exists. If it does, return the parsed JSON array immediately.
2. If missing, check if `RegistrationSheet` exists on disk.
3. If the sheet exists, automatically parse it, generate the normalized students, write the JSON cache to disk, and return the data.

```powershell
function Get-CourseStudents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CourseId,
        [string]$RegistrationSheet = $null
    )
    $filePath = Get-CourseStudentsFilePath $CourseId
    
    # 1. Fast path: Read from cached JSON database
    if (Test-Path -LiteralPath $filePath) {
        try {
            $raw = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
            if ($raw -and $raw.Trim()) {
                $parsed = ConvertFrom-Json $raw
                if ($parsed -is [System.Array]) { return @($parsed) }
                elseif ($parsed) { return @($parsed) }
            }
        } catch { }
    }

    # 2. Self-healing fallback: Parse sheet and persist cache once
    if ($RegistrationSheet -and (Test-Path -LiteralPath $RegistrationSheet)) {
        $sheetResult = Import-StudentSheet -Path $RegistrationSheet
        if ($sheetResult.Success -and $sheetResult.Students.Count -gt 0) {
            Save-CourseStudents -CourseId $CourseId -Students $sheetResult.Students
            return @($sheetResult.Students)
        }
    }

    return @()
}
```

```text
❌ WRONG:  Crashing or showing an empty screen when the cache file is absent.

✅ RIGHT:  Checking the cache first, but falling back to auto-parsing and regenerating the cache on the fly.
```

**Rule:** Robust caching functions should be self-healing: if the cache is missing, regenerate it transparently from the source of truth.

**Why?** Coordinators never have to manually run an "Ingest" command for older courses—the app detects missing cache files and transparently heals itself.

---

## 3) Decoupling Application State from Source Documents

### 3.1 The Problem
In upcoming phases, coordinators will perform several actions:
- Verify students whose fee receipt matches the registration.
- Approve manual overrides for students with blurry documents.
- Flag students who completed enrollment but skipped exam registration.
- Add notes and remarks.

If we tried to write this status data back into the coordinator's original `.xlsx` file:
1. We might corrupt complex Excel formulas or macros.
2. The user might have opened the file in Excel, causing write permission errors.
3. Different versions of the sheet would be impossible to synchronize cleanly.

### 3.2 The Architecture — Source vs. State
By persisting student records inside `data/students_<courseId>.json`, we separate:
* **The Source of Truth for Uploads**: The original Google Form Excel sheet (remains pristine and read-only).
* **The Application State**: The local JSON document containing student records plus app-specific state (`Status`, `VerificationReason`, `CoordinatorNotes`).

```text
[ Coordinator's Excel Sheet ]  ──(One-time Import)──>  [ data/students_<id>.json ]
       (Read-Only)                                             │
                                                               ▼
                                                  [ Coordinator Actions ]
                                                  • Verify
                                                  • Flag Exception
                                                  • Add Remarks
```

**Rule:** Never mutate imported customer spreadsheets. Always isolate operational workflow state inside your application's own database.

**Why?** This guarantees data integrity, prevents Excel file corruption, and gives our system full freedom to extend the student data model with verification flags and audit logs.

---

## Topics Covered in This Chapter

1) The Excel Re-Parsing Bottleneck vs. Local JSON Storage
   - 1.1 The Problem
   - 1.2 The Fix — Local Scoped JSON Databases
2) Lazy Ingestion & Auto-Healing Cache Strategy
   - 2.1 The Problem
   - 2.2 The Solution — Lazy Ingestion with Self-Healing
3) Decoupling Application State from Source Documents
   - 3.1 The Problem
   - 3.2 The Architecture — Source vs. State
