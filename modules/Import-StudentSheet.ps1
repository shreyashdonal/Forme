<#
.SYNOPSIS
    Reads and extracts student row data from .xlsx, .xls, or .csv files.
.DESCRIPTION
    Parses spreadsheets without requiring Microsoft Office/Excel to be installed.
    Uses the ImportExcel module or native CSV reader.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Path
)

function ConvertTo-ReadableDate {
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return ""
    }

    # 1. Already a DateTime instance
    if ($Value -is [DateTime]) {
        return $Value.ToString("dd/MM/yyyy HH:mm:ss")
    }

    # 2. Excel OLE Automation numeric date (e.g., 46035.6843491551)
    $num = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
        if ($num -ge 30000 -and $num -le 60000) {
            try {
                return [DateTime]::FromOADate($num).ToString("dd/MM/yyyy HH:mm:ss")
            }
            catch { }
        }
    }

    # 3. Standard string date parseable
    $parsedDate = [DateTime]::MinValue
    if ([DateTime]::TryParse([string]$Value, [ref]$parsedDate)) {
        return $parsedDate.ToString("dd/MM/yyyy HH:mm:ss")
    }

    return [string]$Value
}

function ConvertTo-BooleanValue {
    param($Value)
    if ($null -eq $Value) { return $false }
    $s = [string]$Value.ToString().Trim().ToLower()
    if ($s -in @('yes', 'true', 'y', '1', 'done', 'completed')) {
        return $true
    }
    return $false
}

function Get-ColumnMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Headers
    )

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
                $matchedHeader = $cleanH
                break
            }
        }
        $mapping[$key] = $matchedHeader
    }

    return $mapping
}

function Import-StudentSheet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $result = [PSCustomObject]@{
        Success         = $false
        FilePath        = $Path
        RowCount        = 0
        Headers         = @()
        ColumnMap       = [ordered]@{}
        Students        = @()
        DuplicateCount  = 0
        SupersededRolls = @()
        Rows            = @()
        Error           = $null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        $result.Error = "File not found at specified path: $Path"
        return $result
    }

    $ext = [System.IO.Path]::GetExtension($Path).ToLower()
    if ($ext -notin @('.xlsx', '.xls', '.csv')) {
        $result.Error = "Unsupported file format '$ext'. Please provide an .xlsx, .xls, or .csv file."
        return $result
    }

    try {
        $rawRows = @()
        if ($ext -eq '.csv') {
            $rawRows = @(Import-Csv -LiteralPath $Path -ErrorAction Stop)
        }
        else {
            # Excel format (.xlsx / .xls)
            if (Get-Module -ListAvailable -Name ImportExcel) {
                Import-Module ImportExcel -ErrorAction Stop
                $rawRows = @(Import-Excel -Path $Path -ErrorAction Stop)
            }
            else {
                throw "The 'ImportExcel' PowerShell module is required to read Excel files. Please run: Install-Module ImportExcel -Scope CurrentUser"
            }
        }

        # Filter out completely blank rows, trim property names, and format date/timestamp values
        $validRows = @()
        foreach ($row in $rawRows) {
            $hasData = $false
            $cleanRowDict = [ordered]@{}
            if ($row -is [System.Management.Automation.PSCustomObject]) {
                foreach ($prop in $row.PSObject.Properties) {
                    $val = $prop.Value
                    if (-not [string]::IsNullOrWhiteSpace($val)) {
                        $hasData = $true
                    }
                    # Format timestamp/date columns into human-readable strings
                    if ($prop.Name -match '(?i)timestamp|date') {
                        $val = ConvertTo-ReadableDate -Value $val
                    }
                    # Trim property name so WPF DataGrid data-binding matches accurately (prevents empty cell bug on trailing spaces)
                    $cleanPropName = $prop.Name.Trim()
                    $cleanRowDict[$cleanPropName] = $val
                }
            }
            if ($hasData) {
                $validRows += [PSCustomObject]$cleanRowDict
            }
        }

        # Extract headers (all trimmed)
        $headers = @()
        if ($validRows.Count -gt 0) {
            $headers = @($validRows[0].PSObject.Properties | Select-Object -ExpandProperty Name)
        }
        elseif ($rawRows.Count -gt 0) {
            $headers = @($rawRows[0].PSObject.Properties | ForEach-Object { $_.Name.Trim() })
        }

        # Detect smart column mappings
        $colMap = Get-ColumnMapping -Headers $headers

        # Build normalized Students collection with smart de-duplication (latest submission wins)
        $studentMap = [ordered]@{}
        $duplicateCount = 0
        $supersededRolls = [System.Collections.ArrayList]@()
        $mappedHeaders = @($colMap.Values | Where-Object { $_ })

        foreach ($row in $validRows) {
            $rollNo       = if ($colMap.RollNo)       { [string]$row.($colMap.RollNo) }       else { "" }
            $name         = if ($colMap.Name)         { [string]$row.($colMap.Name) }         else { "" }
            $email        = if ($colMap.Email)        { [string]$row.($colMap.Email) }        else { "" }
            $subject      = if ($colMap.Subject)      { [string]$row.($colMap.Subject) }      else { "" }
            $isEnrolled   = if ($colMap.IsEnrolled)   { ConvertTo-BooleanValue $row.($colMap.IsEnrolled) }   else { $null }
            $isRegistered = if ($colMap.IsRegistered) { ConvertTo-BooleanValue $row.($colMap.IsRegistered) } else { $null }
            $proofUrl     = if ($colMap.ProofUrl)     { [string]$row.($colMap.ProofUrl) }     else { "" }
            $timestamp    = if ($colMap.Timestamp)    { [string]$row.($colMap.Timestamp) }    else { "" }

            # Store any extra unmapped columns in Raw dictionary
            $rawDict = [ordered]@{}
            foreach ($prop in $row.PSObject.Properties) {
                if ($prop.Name -notin $mappedHeaders) {
                    $rawDict[$prop.Name] = $prop.Value
                }
            }

            $stObj = [PSCustomObject]@{
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

            # De-duplication: match by RollNo (case-insensitive), fallback to Email
            $key = if ($stObj.RollNo) { $stObj.RollNo.ToLower() } elseif ($stObj.Email) { $stObj.Email.ToLower() } else { [Guid]::NewGuid().ToString() }

            if ($studentMap.Contains($key)) {
                # A previous submission exists for this student; latest row supersedes earlier row
                $duplicateCount++
                $dispRoll = if ($stObj.RollNo) { $stObj.RollNo } else { $stObj.Email }
                if ($dispRoll -notin $supersededRolls) {
                    $null = $supersededRolls.Add($dispRoll)
                }
                $studentMap[$key] = $stObj
            } else {
                $studentMap[$key] = $stObj
            }
        }

        $students = @($studentMap.Values)

        $result.Success         = $true
        $result.RowCount        = $validRows.Count
        $result.Headers         = $headers
        $result.ColumnMap       = $colMap
        $result.Students        = $students
        $result.DuplicateCount  = $duplicateCount
        $result.SupersededRolls = @($supersededRolls)
        $result.Rows            = $validRows
        return $result
    }
    catch {
        $result.Success = $false
        $result.Error   = $_.Exception.Message
        return $result
    }
}

# ==============================================================================
# Course Student Store Persistence Helpers
# ==============================================================================

function Get-CourseStudentsFilePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CourseId,
        [string]$CourseName = $null,
        [string]$DataDir = $null
    )
    if (-not $DataDir) {
        $appRoot = Split-Path -Parent $PSScriptRoot
        $DataDir = Join-Path $appRoot "data"
    }

    $coursesParent = Join-Path $DataDir "Courses"

    # 1. If CourseName is missing, check $script:courses if loaded
    if (-not $CourseName -and $script:courses) {
        foreach ($c in $script:courses) {
            if ([string]$c.Id -eq $CourseId) {
                $CourseName = $c.Name
                break
            }
        }
    }

    # 2. If still missing, inspect existing named folders under data/Courses/ to find matching CourseId
    if (-not $CourseName -and (Test-Path -LiteralPath $coursesParent)) {
        $namedDirs = Get-ChildItem -LiteralPath $coursesParent -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^[0-9a-fA-F-]{36}$' }
        foreach ($nd in $namedDirs) {
            $candidateJson = Join-Path $nd.FullName "students.json"
            if (Test-Path -LiteralPath $candidateJson) {
                try {
                    $peek = Get-Content -LiteralPath $candidateJson -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($peek.CourseId -eq $CourseId) {
                        $CourseName = $nd.Name
                        break
                    }
                } catch {}
            }
        }
    }

    $cleanCourseName = if ($CourseName) { ($CourseName -replace '[\\/:*?"<>|]', '_').Trim() } else { $null }
    if (-not $cleanCourseName) { $cleanCourseName = $CourseId }

    $courseDir = Join-Path $coursesParent $cleanCourseName
    if (-not (Test-Path -LiteralPath $courseDir)) {
        $null = New-Item -ItemType Directory -Path $courseDir -Force
    }

    $modernPath = Join-Path $courseDir "students.json"

    # Backward compatibility: automatically migrate legacy data/students_<CourseId>.json if found
    $legacyPath = Join-Path $DataDir "students_$CourseId.json"
    if ((Test-Path -LiteralPath $legacyPath) -and (-not (Test-Path -LiteralPath $modernPath))) {
        Move-Item -LiteralPath $legacyPath -Destination $modernPath -Force
    }

    # Clean up duplicate raw-GUID folder if a named folder exists for this CourseId
    if ($cleanCourseName -ne $CourseId) {
        $guidDir = Join-Path $coursesParent $CourseId
        if (Test-Path -LiteralPath $guidDir) {
            Remove-Item -LiteralPath $guidDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    return $modernPath
}

function Save-CourseStudents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CourseId,
        [Parameter(Mandatory = $true)]
        $Students,
        $ColumnMap = $null,
        [string]$CourseName = $null,
        [string]$DataDir = $null
    )
    $filePath = Get-CourseStudentsFilePath -CourseId $CourseId -CourseName $CourseName -DataDir $DataDir
    $payload = [PSCustomObject]@{
        CourseId  = $CourseId
        LastSync  = (Get-Date).ToString("yyyy-MM-dd HH:mm")
        ColumnMap = $ColumnMap
        Students  = @($Students)
    }
    $json = ConvertTo-Json $payload -Depth 6
    Set-Content -Path $filePath -Value $json -Encoding UTF8
}

function Get-CourseStudentStore {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CourseId,
        [string]$RegistrationSheet = $null,
        [string]$CourseName = $null,
        [string]$DataDir = $null,
        [switch]$Force
    )
    $filePath = Get-CourseStudentsFilePath -CourseId $CourseId -CourseName $CourseName -DataDir $DataDir
    $cachedStudents = @()
    $cachedSync = $null

    if (-not $Force -and (Test-Path -LiteralPath $filePath)) {
        try {
            $raw = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
            if ($raw -and $raw.Trim()) {
                $parsed = ConvertFrom-Json $raw
                # If modern store format with populated ColumnMap
                if ($parsed.PSObject.Properties['Students'] -and $parsed.ColumnMap) {
                    $hasAnyKey = $false
                    if ($parsed.ColumnMap -is [System.Collections.IDictionary] -and $parsed.ColumnMap.Count -gt 0) {
                        $hasAnyKey = $true
                    } elseif ($parsed.ColumnMap.PSObject -and $parsed.ColumnMap.PSObject.Properties.Count -gt 0) {
                        $hasAnyKey = $true
                    }
                    if ($hasAnyKey) {
                        return $parsed
                    }
                }
                if ($parsed.PSObject.Properties['Students']) {
                    $cachedStudents = @($parsed.Students)
                    $cachedSync = $parsed.LastSync
                } elseif ($parsed -is [System.Array]) {
                    $cachedStudents = @($parsed)
                }
            }
        } catch { }
    }

    # If Force, or cache was missing ColumnMap or didn't exist, and sheet is on disk, re-ingest and persist
    if ($RegistrationSheet -and (Test-Path -LiteralPath $RegistrationSheet)) {
        $sheetResult = Import-StudentSheet -Path $RegistrationSheet
        if ($sheetResult.Success) {
            Save-CourseStudents -CourseId $CourseId -Students $sheetResult.Students -ColumnMap $sheetResult.ColumnMap -CourseName $CourseName -DataDir $DataDir
            return [PSCustomObject]@{
                CourseId  = $CourseId
                LastSync  = (Get-Date).ToString("yyyy-MM-dd HH:mm")
                ColumnMap = $sheetResult.ColumnMap
                Students  = @($sheetResult.Students)
            }
        }
    }

    # Fallback if sheet is not on disk but we had cached students
    return [PSCustomObject]@{
        CourseId  = $CourseId
        LastSync  = $cachedSync
        ColumnMap = $null
        Students  = $cachedStudents
    }
}

function Get-CourseStudents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CourseId,
        [string]$RegistrationSheet = $null,
        [string]$CourseName = $null,
        [string]$DataDir = $null
    )
    $store = Get-CourseStudentStore -CourseId $CourseId -RegistrationSheet $RegistrationSheet -CourseName $CourseName -DataDir $DataDir
    if ($store -and $store.Students) {
        return @($store.Students)
    }
    return @()
}

# If executed directly with a Path parameter, run and return the result
if ($Path) {
    Import-StudentSheet -Path $Path
}

