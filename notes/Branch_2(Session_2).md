# Branch 2 (Session 2) — Excel Serial Timestamps, Smart Column Detection & The Raw Bucket Pattern

> **Target Audience:** Web Developer learning Desktop Engineering (PowerShell + WPF)  
> **Topic:** Excel OADate Conversion, Schema Normalization, Fuzzy Column Mapping, and Data Retention  
> **Date:** September 2026  

---

## 1) Excel Serial Dates vs. Web Timestamps (The 46035.68 Mystery)

### 1.1 The Problem
In web development (JavaScript/Node.js), timestamps are almost universally represented as ISO 8601 strings (`"2026-01-13T16:25:27Z"`) or Unix Epoch milliseconds (`1768321527000` — milliseconds elapsed since January 1, 1970).

When we read Excel files (`.xlsx`) directly with tools like `ImportExcel` (or SheetJS in Node), dates often look completely unrecognizable:
```text
46035.6843491551
```
If this value is rendered directly in our app's DataGrid, users see confusing floating-point numbers instead of when the student actually registered.

### 1.2 The Fix — OLE Automation Dates (OADate)
Excel does not store dates as strings or Unix timestamps. It stores them as **OADate serial numbers** (floating-point days elapsed since December 30, 1899):
- The whole integer part (`46035`) represents the number of days: **January 13, 2026**.
- The decimal fractional part (`.6843491551`) represents the fraction of a 24-hour day: `0.6843491551 * 24` hours = **16:25:27** (4:25 PM).

In .NET / PowerShell, we convert this with `[DateTime]::FromOADate()`:

```powershell
function ConvertTo-ReadableDate {
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return ""
    }

    # 1. If it's already a native .NET DateTime object
    if ($Value -is [DateTime]) {
        return $Value.ToString("dd/MM/yyyy HH:mm:ss")
    }

    # 2. If it's an Excel OADate numeric serial (between years 1982 and 2064)
    $num = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
        if ($num -ge 30000 -and $num -le 60000) {
            try {
                return [DateTime]::FromOADate($num).ToString("dd/MM/yyyy HH:mm:ss")
            }
            catch { }
        }
    }

    # 3. If it's already a standard date string
    $parsedDate = [DateTime]::MinValue
    if ([DateTime]::TryParse([string]$Value, [ref]$parsedDate)) {
        return $parsedDate.ToString("dd/MM/yyyy HH:mm:ss")
    }

    return [string]$Value
}
```

```text
❌ WRONG:  Assuming all numeric timestamps are Unix timestamps in milliseconds:
           new Date(46035.68) -> outputs 1970-01-01!

✅ RIGHT:  Converting Excel numbers as OADates:
           [DateTime]::FromOADate(46035.6843491551) -> outputs 13/01/2026 16:25:27
```

**Rule:** Excel serial dates count days from December 30, 1899; Unix timestamps count seconds or milliseconds from January 1, 1970. Never confuse the two.

**Why?** Checking `$num -ge 30000 -and $num -le 60000` guards against accidentally converting other numbers (like fees `1000` or phone numbers) into nonsensical dates.

---

## 2) Smart Column Detection (Schema Normalization)

### 2.1 The Problem
In real college workflows, every department or professor creates their Google Form slightly differently. For example, in our actual test sheet:
- The roll number column was named `"Enrollment Number"`.
- The enrollment completion column had a spelling error: `"Enrollnment completed"` (with two `n`s).
- The proof of registration column had an invisible trailing space: `"Upload proof of registration "`.
- The course column was named `"Subject"` instead of `"Course Name"`.

If our application hardcoded `$row.'Roll Number'`, the entire import would fail or produce blank values.

### 2.2 The Solution — Regex Pattern Mapping (`Get-ColumnMapping`)
Instead of forcing coordinators to rename their columns manually, we use a smart regex dictionary that identifies columns by common variations, ignoring case and trimming extra whitespace:

```powershell
function Get-ColumnMapping {
    [CmdletBinding()]
    param([string[]]$Headers)

    $patterns = [ordered]@{
        RollNo       = '^(enrollment|roll\s*no|urn|reg(istration)?\s*no|student\s*id)'
        Name         = '^(name|student\s*name|candidate\s*name|full\s*name)$'
        Email        = '^(email|email\s*address|mail)$'
        Subject      = '^(subject|course\s*name|course\s*title|course|elective)$'
        IsEnrolled   = 'enroll.*complete|enrolled'
        IsRegistered = 'registration\s*done|registered'
        ProofUrl     = 'upload.*(proof|certificate|receipt)|proof|receipt|drive\.google'
        Timestamp    = 'timestamp|submission\s*time'
    }

    $mapping = [ordered]@{}
    foreach ($key in $patterns.Keys) {
        $pattern = $patterns[$key]
        $matchedHeader = $null
        foreach ($h in $Headers) {
            $cleanH = $h.Trim()
            if ($cleanH -match "(?i)$pattern") {
                $matchedHeader = $h
                break
            }
        }
        $mapping[$key] = $matchedHeader
    }

    return $mapping
}
```

```text
❌ WRONG:  Hardcoding exact column strings:
           $roll = $row."Roll Number" (Returns $null if header is "Enrollment Number")

✅ RIGHT:  Mapping through dynamic pattern resolution:
           $rollHeader = $mapping.RollNo
           $roll = $row.$rollHeader
```

**Rule:** Never rely on exact string equality when ingesting user spreadsheets. Always trim whitespace, ignore case, and use regex patterns.

**Why?** This gives the app high resilience: whether a coordinator uses `"Enrollment Number"`, `"Roll No"`, or `"Student ID"`, the app seamlessly normalizes it to `RollNo`.

---

## 3) Boolean Coercion ("Yes" / "No" to True / False)

### 3.1 The Problem
Google Forms exports checkboxes and multiple-choice answers as text strings like `"Yes"`, `"No"`, `"Completed"`, or `""`.
In code, checking `if ($student.IsRegistered)` in PowerShell or JavaScript evaluates any non-empty string as truthy:
- `"Yes"` evaluates to `$true`.
- **`"No"` ALSO evaluates to `$true`** because non-empty strings are truthy!

This would cause students who explicitly replied `"No"` to be mistakenly treated as registered.

### 3.2 The Fix — `ConvertTo-BooleanValue`
We explicitly coerce human responses into true booleans:

```powershell
function ConvertTo-BooleanValue {
    param($Value)
    if ($null -eq $Value) { return $false }
    $s = [string]$Value.ToString().Trim().ToLower()
    if ($s -in @('yes', 'true', 'y', '1', 'done', 'completed')) {
        return $true
    }
    return $false
}
```

In our test dataset of 150 students, this cleanly isolated:
- **144 students** with `IsRegistered: True`
- **6 students** with `IsRegistered: False`

Those 6 students enrolled in the NPTEL portal but replied "No" to registering for the exam—giving our verification engine exact data to flag them for coordinator review!

```text
❌ WRONG:  Checking string truthiness directly:
           if ("No") { ... }  # In PowerShell and JS, "No" is TRUTHY!

✅ RIGHT:  Converting to an explicit boolean first:
           $isRegistered = ConvertTo-BooleanValue "No" # Returns $false
```

**Rule:** In weakly-typed languages, non-empty strings are always truthy. Always coerce `"Yes"` / `"No"` into real boolean values before logic checks.

**Why?** Without explicit boolean coercion, exceptional cases (students who answered "No") would slip through verification completely undetected.

---

## 4) The "Raw" Pattern for Extra Unmapped Columns

### 4.1 The Problem
When you normalize data into standard fields (`RollNo`, `Name`, `Email`, etc.), a spreadsheet might include extra columns that your schema wasn't expecting:
- `"Mobile Number"`
- `"Hostel vs Day Scholar"`
- `"Father's Name"`
- `"Remarks"`

If you only copy known fields into your clean object, you lose that extra information forever. If you don't normalize, your code is messy and unpredictable.

### 4.2 The Solution — Clean Core Fields + `Raw` Bucket
We extract standard fields to the root of the student object, and gather all leftover unmapped columns into a `Raw` dictionary:

```powershell
# Gather unmapped extra headers
$mappedHeaders = @($colMap.Values | Where-Object { $_ })
$rawDict = [ordered]@{}
foreach ($prop in $row.PSObject.Properties) {
    if ($prop.Name -notin $mappedHeaders) {
        $rawDict[$prop.Name] = $prop.Value
    }
}

# Clean student record
$student = [PSCustomObject]@{
    RollNo       = $rollNo.Trim()
    Name         = $name.Trim()
    Email        = $email.Trim()
    Subject      = $subject.Trim()
    IsEnrolled   = $isEnrolled
    IsRegistered = $isRegistered
    ProofUrl     = $proofUrl.Trim()
    Timestamp    = $timestamp.Trim()
    Raw          = $rawDict
}
```

```text
❌ WRONG:  Discarding unmapped columns, losing student contact or department details.

✅ RIGHT:  Keeping standardized root properties for app logic, with unmapped columns safely preserved inside $student.Raw.
```

**Rule:** Core business logic should only depend on standardized root properties; unexpected custom fields belong in an unmapped `Raw` bucket.

**Why?** This gives the best of both worlds: strict consistency for UI and verification algorithms, with zero data loss for unpredictable college-specific fields.

---

## Topics Covered in This Chapter

1) Excel Serial Dates vs. Web Timestamps (The 46035.68 Mystery)
   - 1.1 The Problem
   - 1.2 The Fix — OLE Automation Dates (OADate)
2) Smart Column Detection (Schema Normalization)
   - 2.1 The Problem
   - 2.2 The Solution — Regex Pattern Mapping (`Get-ColumnMapping`)
3) Boolean Coercion ("Yes" / "No" to True / False)
   - 3.1 The Problem
   - 3.2 The Fix — `ConvertTo-BooleanValue`
4) The "Raw" Pattern for Extra Unmapped Columns
   - 4.1 The Problem
   - 4.2 The Solution — Clean Core Fields + `Raw` Bucket
