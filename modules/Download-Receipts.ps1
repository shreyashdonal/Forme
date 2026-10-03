# ==============================================================================
# NPTEL Operations Studio — Batch Receipt Downloader & Ingestion Engine
# File: modules/Download-Receipts.ps1
# Purpose: Downloads student payment receipts from Google Drive links or ingests
#          them from a local folder into data/receipts/<CourseId>/ with caching.
# ==============================================================================

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

function Get-DriveFileId {
    param([string]$Url)
    if (-not $Url) { return $null }

    # Pattern 1: id=FILE_ID (e.g. open?id=..., uc?id=..., uc?export=download&id=...)
    if ($Url -match '(?i)[?&]id=([a-zA-Z0-9_-]{20,})') {
        return $matches[1]
    }
    # Pattern 2: /file/d/FILE_ID or /d/FILE_ID
    if ($Url -match '(?i)/d/([a-zA-Z0-9_-]{20,})') {
        return $matches[1]
    }

    return $null
}

function Get-ReceiptFileExtension {
    param(
        [string]$Path,
        [byte[]]$Bytes = $null
    )
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        $ext = [System.IO.Path]::GetExtension($Path).ToLower()
        if ($ext -in @('.png', '.jpg', '.jpeg', '.pdf', '.webp')) {
            return $ext
        }
        if (-not $Bytes) {
            $Bytes = [System.IO.File]::ReadAllBytes($Path)
        }
    }

    if ($Bytes -and $Bytes.Length -ge 4) {
        # PDF magic bytes: %PDF (0x25 0x50 0x44 0x46)
        if ($Bytes[0] -eq 0x25 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x44 -and $Bytes[3] -eq 0x46) {
            return '.pdf'
        }
        # PNG magic bytes: \x89PNG (0x89 0x50 0x4E 0x47)
        if ($Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47) {
            return '.png'
        }
        # JPEG magic bytes: 0xFF 0xD8 0xFF
        if ($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF) {
            return '.jpg'
        }
    }

    return '.png' # Default fallback
}

function Find-LocalReceiptMatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SearchFolder,
        [string]$RollNo,
        [string]$Name
    )
    if (-not (Test-Path -LiteralPath $SearchFolder)) { return $null }

    $allFiles = Get-ChildItem -LiteralPath $SearchFolder -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $_.Extension -in @('.png', '.jpg', '.jpeg', '.pdf', '.webp')
    }

    # 1. Match by clean Roll Number (highest priority - 100% confidence)
    if ($RollNo) {
        $cleanRoll = ($RollNo -replace '[^a-zA-Z0-9]', '').ToLower()
        if ($cleanRoll.Length -ge 3) {
            foreach ($f in $allFiles) {
                $fClean = ($f.BaseName -replace '[^a-zA-Z0-9]', '').ToLower()
                if ($fClean -match [regex]::Escape($cleanRoll) -or $cleanRoll -match [regex]::Escape($fClean)) {
                    return $f.FullName
                }
            }
        }
    }

    # 2. Match by student Full Name (alphanumeric clean - 98% confidence)
    if ($Name) {
        $cleanName = ($Name -replace '[^a-zA-Z0-9]', '').ToLower()
        if ($cleanName.Length -ge 3) {
            foreach ($f in $allFiles) {
                $fClean = ($f.BaseName -replace '[^a-zA-Z0-9]', '').ToLower()
                if ($fClean -match [regex]::Escape($cleanName)) {
                    return $f.FullName
                }
            }
        }

        # 3. Match by First Token + Last Token (95% confidence for Google Forms file naming)
        $tokens = @($Name.Trim() -split '\s+' | Where-Object { $_.Length -ge 2 })
        if ($tokens.Count -ge 2) {
            $firstTok = ($tokens[0] -replace '[^a-zA-Z0-9]', '').ToLower()
            $lastTok = ($tokens[-1] -replace '[^a-zA-Z0-9]', '').ToLower()
            foreach ($f in $allFiles) {
                $fClean = ($f.BaseName -replace '[^a-zA-Z0-9]', '').ToLower()
                if ($fClean -match [regex]::Escape($firstTok) -and $fClean -match [regex]::Escape($lastTok)) {
                    return $f.FullName
                }
            }
        }
    }

    return $null
}

function Download-GoogleDriveFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileId,
        [Parameter(Mandatory = $true)]
        [string]$DestinationBaseWithoutExt
    )

    $result = [PSCustomObject]@{
        Success   = $false
        SavedPath = $null
        Error     = $null
    }

    $downloadUrl = "https://drive.google.com/uc?export=download&id=$FileId"
    $tempFile = [System.IO.Path]::GetTempFileName()

    try {
        $client = New-Object System.Net.WebClient
        $client.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        $client.DownloadFile($downloadUrl, $tempFile)

        $bytes = [System.IO.File]::ReadAllBytes($tempFile)
        if ($bytes.Length -eq 0) {
            $result.Error = "Empty file received from Google Drive"
            return $result
        }

        # Check if Google returned an HTML page instead of the actual file (e.g. Sign-in or Virus Warning)
        $textCheck = [System.Text.Encoding]::UTF8.GetString($bytes, 0, [Math]::Min($bytes.Length, 2048))
        if ($textCheck -match '(?i)<html' -or $textCheck -match '(?i)Google Drive: Sign-in' -or $textCheck -match '(?i)Access Denied') {
            # Check for virus warning confirmation token (common on files > 100MB)
            if ($textCheck -match 'confirm=([a-zA-Z0-9_-]+)') {
                $confirmToken = $matches[1]
                $confirmUrl = "https://drive.google.com/uc?export=download&confirm=$confirmToken&id=$FileId"
                $client.DownloadFile($confirmUrl, $tempFile)
                $bytes = [System.IO.File]::ReadAllBytes($tempFile)
            } else {
                $result.Error = "Private link (Google Drive sign-in required). File is not publicly shared."
                return $result
            }
        }

        # Determine real extension from file bytes
        $ext = Get-ReceiptFileExtension -Bytes $bytes
        $finalPath = "${DestinationBaseWithoutExt}${ext}"

        [System.IO.File]::WriteAllBytes($finalPath, $bytes)
        $result.Success   = $true
        $result.SavedPath = $finalPath
        return $result
    }
    catch {
        $result.Error = $_.Exception.Message
        return $result
    }
    finally {
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-CourseReceiptsDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CourseId,
        [string]$CourseName = $null,
        [string]$DataDir = $null
    )
    if (-not $DataDir) {
        $DataDir = Join-Path (Split-Path -Parent $PSScriptRoot) "data"
    }
    $cleanCourseName = if ($CourseName) { ($CourseName -replace '[\\/:*?"<>|]', '_').Trim() } else { $null }
    if (-not $cleanCourseName) { $cleanCourseName = $CourseId }

    $coursesDir = Join-Path $DataDir "Courses"
    $courseDir = Join-Path $coursesDir $cleanCourseName
    $dir = Join-Path $courseDir "receipts"
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    return $dir
}

function Invoke-ReceiptBatchDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CourseId,
        [string]$CourseName = $null,
        [Parameter(Mandatory = $true)]
        [array]$Students,
        [string]$DataDir = $null,
        [string]$LocalReceiptsFolder = $null,
        [scriptblock]$ProgressCallback = $null,
        [switch]$Force
    )

    if (-not $DataDir) {
        $DataDir = Join-Path (Split-Path -Parent $PSScriptRoot) "data"
    }

    $receiptsDir = Get-CourseReceiptsDirectory -CourseId $CourseId -CourseName $CourseName -DataDir $DataDir

    $results = [System.Collections.ArrayList]@()
    $totalCount = $Students.Count
    $index = 0
    $downloadedCount = 0
    $cachedCount = 0
    $localCount = 0
    $failedCount = 0
    $skippedCount = 0

    foreach ($student in $Students) {
        $index++
        $rollNo = if ($student.RollNo) { [string]$student.RollNo } else { "Unknown_$index" }
        $name = if ($student.Name) { [string]$student.Name } else { "" }
        $proofUrl = if ($student.ProofUrl) { [string]$student.ProofUrl } else { "" }
        $isReg = if ($student.PSObject.Properties['IsRegistered']) { $student.IsRegistered } else { $true }

        $cleanRoll = ($rollNo -replace '[\\/:*?"<>|]', '_').Trim()
        $destBase = Join-Path $receiptsDir "${cleanRoll}_receipt"

        $studentResult = [PSCustomObject]@{
            RollNo     = $rollNo
            Name       = $name
            ProofUrl   = $proofUrl
            Success    = $false
            LocalPath  = $null
            FromCache  = $false
            Source     = "None"
            Error      = $null
        }

        # 1. Skip students who did not register for the exam
        if ($isReg -eq $false) {
            $studentResult.Source = "Skipped"
            $studentResult.Error  = "Did Not Register for exam"
            $skippedCount++
            $null = $results.Add($studentResult)
            if ($ProgressCallback) {
                & $ProgressCallback $index $totalCount $student "Skipped (Not Registered)"
            }
            continue
        }

        # 2. Check Resumable Cache (if already downloaded)
        $existing = Get-ChildItem -LiteralPath $receiptsDir -Filter "${cleanRoll}_receipt.*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $Force -and $existing -and $existing.Length -gt 0) {
            $studentResult.Success   = $true
            $studentResult.LocalPath = $existing.FullName
            $studentResult.FromCache = $true
            $studentResult.Source    = "Cache"
            $cachedCount++
            $null = $results.Add($studentResult)
            if ($ProgressCallback) {
                & $ProgressCallback $index $totalCount $student "Cached ($($existing.Name))"
            }
            continue
        }

        # 3. Check Local Receipts Folder (offline matching by Roll No / Name)
        $localMatch = $null
        if ($LocalReceiptsFolder -and (Test-Path -LiteralPath $LocalReceiptsFolder)) {
            $localMatch = Find-LocalReceiptMatch -SearchFolder $LocalReceiptsFolder -RollNo $rollNo -Name $name
        }

        if ($localMatch) {
            $ext = [System.IO.Path]::GetExtension($localMatch)
            $destFile = "${destBase}${ext}"
            try {
                Copy-Item -LiteralPath $localMatch -Destination $destFile -Force
                $studentResult.Success   = $true
                $studentResult.LocalPath = $destFile
                $studentResult.Source    = "LocalFolder"
                $localCount++
                $null = $results.Add($studentResult)
                if ($ProgressCallback) {
                    & $ProgressCallback $index $totalCount $student "Matched local file"
                }
                continue
            } catch {
                # Fall through to try online URL
            }
        }

        # 4. Check if ProofUrl is an existing local file path on this computer
        if ($proofUrl -and (Test-Path -LiteralPath $proofUrl)) {
            $ext = [System.IO.Path]::GetExtension($proofUrl)
            $destFile = "${destBase}${ext}"
            try {
                Copy-Item -LiteralPath $proofUrl -Destination $destFile -Force
                $studentResult.Success   = $true
                $studentResult.LocalPath = $destFile
                $studentResult.Source    = "LocalFile"
                $localCount++
                $null = $results.Add($studentResult)
                if ($ProgressCallback) {
                    & $ProgressCallback $index $totalCount $student "Copied direct file"
                }
                continue
            } catch {
                # Fall through
            }
        }

        # 5. Check if ProofUrl is a Google Drive Link
        $driveId = Get-DriveFileId -Url $proofUrl
        if ($driveId) {
            if ($ProgressCallback) {
                & $ProgressCallback $index $totalCount $student "Downloading from Drive..."
            }
            $dlResult = Download-GoogleDriveFile -FileId $driveId -DestinationBaseWithoutExt $destBase
            if ($dlResult.Success) {
                $studentResult.Success   = $true
                $studentResult.LocalPath = $dlResult.SavedPath
                $studentResult.Source    = "GoogleDrive"
                $downloadedCount++
            } else {
                $studentResult.Success = $false
                $studentResult.Error   = $dlResult.Error
                $failedCount++
            }
            $null = $results.Add($studentResult)
            continue
        }

        # 6. Fallback if no matching URL or file found
        $studentResult.Success = $false
        $studentResult.Error   = if (-not $proofUrl) { "No receipt URL provided in sheet" } else { "Unsupported or invalid receipt link: $proofUrl" }
        $failedCount++
        $null = $results.Add($studentResult)

        if ($ProgressCallback) {
            & $ProgressCallback $index $totalCount $student "Failed ($($studentResult.Error))"
        }
    }

    return [PSCustomObject]@{
        CourseId    = $CourseId
        Total       = $totalCount
        Processed   = ($downloadedCount + $cachedCount + $localCount + $failedCount)
        Downloaded  = $downloadedCount
        FromCache   = $cachedCount
        FromLocal   = $localCount
        Failed      = $failedCount
        Skipped     = $skippedCount
        Results     = @($results)
    }
}

function Import-ReceiptsFromLocalSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CourseId,
        [string]$CourseName = $null,
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [array]$Students,
        [string]$DataDir = $null,
        [scriptblock]$ProgressCallback = $null,
        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Specified source path does not exist: $SourcePath"
    }

    if (-not $DataDir) {
        $DataDir = Join-Path (Split-Path -Parent $PSScriptRoot) "data"
    }

    $receiptsDir = Get-CourseReceiptsDirectory -CourseId $CourseId -CourseName $CourseName -DataDir $DataDir

    $isArchive = $false
    $tempExtractDir = $null
    $scanFolder = $SourcePath

    try {
        # Check if source is a .zip archive
        $sourceItem = Get-Item -LiteralPath $SourcePath
        if (-not $sourceItem.PSIsContainer -and $sourceItem.Extension.ToLower() -eq ".zip") {
            $isArchive = $true
            $tempExtractDir = Join-Path ([System.IO.Path]::GetTempPath()) ("NPTEL_Receipts_" + [Guid]::NewGuid().ToString("N"))
            $null = New-Item -ItemType Directory -Path $tempExtractDir -Force
            try {
                [System.IO.Compression.ZipFile]::ExtractToDirectory($SourcePath, $tempExtractDir)
            } catch {
                Expand-Archive -LiteralPath $SourcePath -DestinationPath $tempExtractDir -Force
            }
            $scanFolder = $tempExtractDir
        }

        # Filter registered students
        $regStudents = @($Students | Where-Object {
            if ($_.PSObject.Properties['IsRegistered']) { $_.IsRegistered -ne $false } else { $true }
        })

        # Scan candidate receipt files recursively
        $candidateFiles = @(Get-ChildItem -LiteralPath $scanFolder -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension.ToLower() -in @('.png', '.jpg', '.jpeg', '.pdf', '.webp')
        })

        # Precompute first name occurrences among registered students (for Tier 4 unique matching)
        $firstNameCounts = @{}
        foreach ($st in $regStudents) {
            if ($st.Name) {
                $fTok = (($st.Name.Trim() -split '\s+')[0] -replace '[^a-zA-Z0-9]', '').ToLower()
                if ($fTok.Length -ge 3) {
                    $firstNameCounts[$fTok] = ($firstNameCounts[$fTok] + 1)
                }
            }
        }

        $assignedFilePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $matchedList = [System.Collections.ArrayList]@()
        $existingList = [System.Collections.ArrayList]@()
        $missingList = [System.Collections.ArrayList]@()

        $stIdx = 0
        $totalRegCount = $regStudents.Count
        foreach ($st in $regStudents) {
            $stIdx++
            $rollNo = if ($st.RollNo) { [string]$st.RollNo } else { "" }
            $name = if ($st.Name) { [string]$st.Name } else { "" }
            $cleanRoll = ($rollNo -replace '[\\/:*?"<>|]', '_').Trim()

            # Check if receipt already exists on disk
            $existing = Get-ChildItem -LiteralPath $receiptsDir -Filter "${cleanRoll}_receipt.*" -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 } | Select-Object -First 1
            if (-not $Force -and $existing) {
                $null = $existingList.Add([PSCustomObject]@{
                    RollNo = $rollNo
                    Name   = $name
                    File   = $existing.FullName
                })
                if ($ProgressCallback) {
                    & $ProgressCallback $stIdx $totalRegCount $st "Already on disk"
                }
                continue
            }

            # Run 4-Tier Matching against unassigned candidates
            $matchedFile = $null
            $matchTier = 0

            # Tier 1: Clean Roll Number match
            if ($rollNo) {
                $cleanRollAlpha = ($rollNo -replace '[^a-zA-Z0-9]', '').ToLower()
                if ($cleanRollAlpha.Length -ge 3) {
                    foreach ($f in $candidateFiles) {
                        if ($assignedFilePaths.Contains($f.FullName)) { continue }
                        $fClean = ($f.BaseName -replace '[^a-zA-Z0-9]', '').ToLower()
                        if ($fClean -match [regex]::Escape($cleanRollAlpha) -or $cleanRollAlpha -match [regex]::Escape($fClean)) {
                            $matchedFile = $f
                            $matchTier = 1
                            break
                        }
                    }
                }
            }

            # Tier 2: Clean Full Name match
            if (-not $matchedFile -and $name) {
                $cleanName = ($name -replace '[^a-zA-Z0-9]', '').ToLower()
                if ($cleanName.Length -ge 3) {
                    foreach ($f in $candidateFiles) {
                        if ($assignedFilePaths.Contains($f.FullName)) { continue }
                        $fClean = ($f.BaseName -replace '[^a-zA-Z0-9]', '').ToLower()
                        if ($fClean -match [regex]::Escape($cleanName)) {
                            $matchedFile = $f
                            $matchTier = 2
                            break
                        }
                    }
                }
            }

            # Tier 3: First + Last token match
            if (-not $matchedFile -and $name) {
                $tokens = @($name.Trim() -split '\s+' | Where-Object { $_.Length -ge 2 })
                if ($tokens.Count -ge 2) {
                    $firstTok = ($tokens[0] -replace '[^a-zA-Z0-9]', '').ToLower()
                    $lastTok = ($tokens[-1] -replace '[^a-zA-Z0-9]', '').ToLower()
                    foreach ($f in $candidateFiles) {
                        if ($assignedFilePaths.Contains($f.FullName)) { continue }
                        $fClean = ($f.BaseName -replace '[^a-zA-Z0-9]', '').ToLower()
                        if ($fClean -match [regex]::Escape($firstTok) -and $fClean -match [regex]::Escape($lastTok)) {
                            $matchedFile = $f
                            $matchTier = 3
                            break
                        }
                    }
                }
            }

            # Tier 4: Unique First Name match
            if (-not $matchedFile -and $name) {
                $tokens = @($name.Trim() -split '\s+' | Where-Object { $_.Length -ge 2 })
                if ($tokens.Count -ge 1) {
                    $firstTok = ($tokens[0] -replace '[^a-zA-Z0-9]', '').ToLower()
                    if ($firstTok.Length -ge 3 -and $firstNameCounts[$firstTok] -eq 1) {
                        foreach ($f in $candidateFiles) {
                            if ($assignedFilePaths.Contains($f.FullName)) { continue }
                            $fClean = ($f.BaseName -replace '[^a-zA-Z0-9]', '').ToLower()
                            if ($fClean -match [regex]::Escape($firstTok)) {
                                $matchedFile = $f
                                $matchTier = 4
                                break
                            }
                        }
                    }
                }
            }

            if ($matchedFile) {
                $null = $assignedFilePaths.Add($matchedFile.FullName)
                $ext = [System.IO.Path]::GetExtension($matchedFile.FullName).ToLower()
                $destFile = Join-Path $receiptsDir "${cleanRoll}_receipt${ext}"
                Copy-Item -LiteralPath $matchedFile.FullName -Destination $destFile -Force
                $null = $matchedList.Add([PSCustomObject]@{
                    RollNo     = $rollNo
                    Name       = $name
                    SourceFile = $matchedFile.Name
                    DestFile   = $destFile
                    Tier       = $matchTier
                })
                if ($ProgressCallback) {
                    & $ProgressCallback $stIdx $totalRegCount $st "Matched: $($matchedFile.Name)"
                }
            } else {
                $null = $missingList.Add([PSCustomObject]@{
                    RollNo = $rollNo
                    Name   = $name
                })
                if ($ProgressCallback) {
                    & $ProgressCallback $stIdx $totalRegCount $st "No match found"
                }
            }
        }

        # Calculate unassigned candidate files
        $unassignedFiles = [System.Collections.ArrayList]@()
        foreach ($f in $candidateFiles) {
            if (-not $assignedFilePaths.Contains($f.FullName)) {
                $null = $unassignedFiles.Add($f.Name)
            }
        }

        return [PSCustomObject]@{
            Success          = $true
            SourcePath       = $SourcePath
            IsArchive        = $isArchive
            TotalRegistered  = $regStudents.Count
            IngestedCount    = $matchedList.Count
            ExistingCount    = $existingList.Count
            MissingCount     = $missingList.Count
            UnassignedCount  = $unassignedFiles.Count
            MatchedStudents  = @($matchedList)
            ExistingStudents = @($existingList)
            MissingStudents  = @($missingList)
            UnassignedFiles  = @($unassignedFiles)
        }
    }
    finally {
        if ($isArchive -and $tempExtractDir -and (Test-Path -LiteralPath $tempExtractDir)) {
            Remove-Item -LiteralPath $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

