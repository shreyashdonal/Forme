# ==============================================================================
# NPTEL Operations Studio -- Stage 2 Examination & Certificate Verification Engine
# File: modules/ExamVerificationEngine.ps1
# Purpose: Specialized data extractor and verification rule engine for NPTEL
#          course completion certificates and examination results.
# ==============================================================================

function Normalize-ExamOcrText {
    param([string]$Text)
    if (-not $Text) { return "" }
    # Normalize common OCR artifacts and line endings
    $norm = $Text -replace '\r\n', "`n"
    $norm = $norm -replace '\r', "`n"
    # Replace non-breaking spaces with standard space
    $norm = $norm -replace '[\u00A0\u2000-\u200B]', ' '
    return $norm
}

function Extract-CertificateData {
    [CmdletBinding()]
    param(
        $OcrResult
    )

    $result = [PSCustomObject]@{
        Success           = $false
        CandidateName     = $null
        CourseName        = $null
        AssignmentMarks   = $null
        ExamMarks         = $null
        TotalMarks        = $null
        CertificateRollNo = $null
        Credits           = $null
        RawText           = ""
        Confidence        = "Low"
        Issues            = @()
    }

    if (-not $OcrResult) {
        $result.Issues = @("No OCR result provided")
        return $result
    }

    # Extract raw text and line array
    $rawText = ""
    $lines = @()
    if ($OcrResult -is [string]) {
        $rawText = $OcrResult
        $lines = @($rawText -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    } elseif ($OcrResult.PSObject.Properties['RawText']) {
        $rawText = [string]$OcrResult.RawText
        if ($OcrResult.PSObject.Properties['Lines'] -and $OcrResult.Lines) {
            $lines = @($OcrResult.Lines | ForEach-Object { [string]$_ } | Where-Object { $_.Trim().Length -gt 0 })
        } else {
            $lines = @($rawText -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
        }
    } elseif ($OcrResult.PSObject.Properties['Text']) {
        $rawText = [string]$OcrResult.Text
        $lines = @($rawText -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    }

    $cleanText = Normalize-ExamOcrText $rawText
    $result.RawText = $cleanText

    if ([string]::IsNullOrWhiteSpace($cleanText)) {
        $result.Issues = @("Empty OCR text")
        return $result
    }

    $issues = [System.Collections.ArrayList]@()

    # --------------------------------------------------------------------------
    # 1. Candidate Name Extraction
    # --------------------------------------------------------------------------
    $candidateName = $null

    # Pattern A: Regex single-block match
    if ($cleanText -match '(?i)(?:This\s+is\s+to\s+certify\s+that|This\s+certificate\s+is\s+awarded\s+to)\s+([A-Za-z\s\.\,''\-]+?)\s+(?:for\s+(?:success\w*|completing)|has\s+success\w*|with\s+a\s+consolidated)') {
        $candidateName = ($matches[1] -replace '\s+', ' ').Trim()
    }

    # Pattern B: Line-by-line fallback
    if (-not $candidateName -or $candidateName.Length -lt 2) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '(?i)(?:This\s+is\s+to\s+certify\s+that|This\s+certificate\s+is\s+awarded\s+to)') {
                for ($j = $i + 1; $j -lt [Math]::Min($lines.Count, $i + 4); $j++) {
                    $cand = $lines[$j].Trim()
                    if ($cand.Length -ge 3 -and $cand -notmatch '(?i)(for\s+successfully|has\s+successfully|course|nptel|consolidated)') {
                        $candidateName = $cand
                        break
                    }
                }
                break
            }
        }
    }

    # Clean candidate name
    if ($candidateName) {
        $candidateName = ($candidateName -replace '^(mr\.|ms\.|shri|smt\.)\s*', '').Trim()
        $result.CandidateName = $candidateName
    } else {
        $null = $issues.Add("Candidate name could not be identified from certificate text")
    }

    # --------------------------------------------------------------------------
    # 2. Course Title Extraction
    # --------------------------------------------------------------------------
    $courseName = $null

    # Pattern A: Regex
    if ($cleanText -match '(?i)comple(?:ting|ted)\s+the\s+course\s+([^\r\n]+?)\s+(?:with\s+a\s+consolidated|Online\s+Assignments|Roll\s*No)') {
        $courseName = ($matches[1] -replace '\s+', ' ').Trim()
    }

    # Pattern B: Line-by-line fallback
    if (-not $courseName -or $courseName.Length -lt 3) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '(?i)complet(?:ing|ed)\s+the\s+course\s*(.*)') {
                $inline = $matches[1].Trim()
                if ($inline.Length -ge 4 -and $inline -notmatch '(?i)(with\s+a|score)') {
                    $courseName = $inline
                    break
                } else {
                    for ($j = $i + 1; $j -lt [Math]::Min($lines.Count, $i + 4); $j++) {
                        $cand = $lines[$j].Trim()
                        if ($cand.Length -ge 4 -and $cand -notmatch '(?i)(with\s+a\s+consolidated|score|online|exam|roll\s*no)') {
                            $courseName = $cand
                            break
                        }
                    }
                    break
                }
            }
        }
    }

    if ($courseName) {
        $result.CourseName = $courseName
    } else {
        $null = $issues.Add("Course name could not be identified from certificate text")
    }

    # --------------------------------------------------------------------------
    # 3. Assignment Marks Extraction (/25)
    # --------------------------------------------------------------------------
    $assignmentMarks = $null

    if ($cleanText -match '(?i)(?:online\s*assignments?|assignment\s*marks?)[^0-9\n\r]{0,20}([0-9]{1,2}(?:\.[0-9]{1,2})?)\s*[/\\|!I1l]\s*25') {
        $assignmentMarks = $matches[1]
    } elseif ($cleanText -match '(?i)(?:online\s*assignments?|assignment\s*marks?)[^0-9\n\r]{0,20}([0-9]{1,2}\.[0-9]{1,2})[1lI/\\|]25') {
        $assignmentMarks = $matches[1]
    } elseif ($cleanText -match '(?i)([0-9]{1,2}(?:\.[0-9]{1,2})?)\s*[/\\|!I1l]\s*25') {
        $assignmentMarks = $matches[1]
    }

    if ($assignmentMarks) {
        $result.AssignmentMarks = $assignmentMarks
    } else {
        $null = $issues.Add("Assignment marks (/25) not detected")
    }

    # --------------------------------------------------------------------------
    # 4. Proctored Exam Marks Extraction (/75)
    # --------------------------------------------------------------------------
    $examMarks = $null

    if ($cleanText -match '(?i)(?:proctored\s*exam|exam\s*marks?)[^0-9\n\r]{0,20}([0-9]{1,2}(?:\.[0-9]{1,2})?)\s*[/\\|!I1l]\s*75') {
        $examMarks = $matches[1]
    } elseif ($cleanText -match '(?i)(?:proctored\s*exam|exam\s*marks?)[^0-9\n\r]{0,20}([0-9]{1,2}\.[0-9]{1,2})[1lI/\\|]75') {
        $examMarks = $matches[1]
    } elseif ($cleanText -match '(?i)([0-9]{1,2}(?:\.[0-9]{1,2})?)\s*[/\\|!I1l]\s*75') {
        $examMarks = $matches[1]
    }

    if ($examMarks) {
        $result.ExamMarks = $examMarks
    } else {
        $null = $issues.Add("Proctored exam marks (/75) not detected")
    }

    # --------------------------------------------------------------------------
    # 5. Total Marks / Consolidated Score Extraction (/100)
    # --------------------------------------------------------------------------
    $totalMarks = $null

    if ($cleanText -match '(?i)consolidated\s*score\s*of[^0-9\n\r]{0,10}([0-9]{1,2}(?:\.[0-9]{1,2})?)') {
        $totalMarks = $matches[1]
    } elseif ($cleanText -match '(?i)total\s*(?:score|marks)?[^0-9\n\r]{0,10}([0-9]{1,2}(?:\.[0-9]{1,2})?)\s*[/\\|!I1l]\s*100') {
        $totalMarks = $matches[1]
    } elseif ($cleanText -match '(?i)score\s*of[^0-9\n\r]{0,10}([0-9]{1,2}(?:\.[0-9]{1,2})?)') {
        $totalMarks = $matches[1]
    }

    if ($totalMarks) {
        $result.TotalMarks = $totalMarks
    } else {
        $null = $issues.Add("Consolidated total marks (/100) not detected")
    }

    # --------------------------------------------------------------------------
    # 6. NPTEL Roll Number / Certificate ID
    # --------------------------------------------------------------------------
    $certRoll = $null

    if ($cleanText -match '(?i)roll\s*no[\.:\s]+([A-Za-z0-9_-]{8,})') {
        $certRoll = $matches[1].Trim()
    } elseif ($cleanText -match '(?i)\b(NPTEL[0-9]{2}[A-Za-z0-9_-]{6,})\b') {
        $certRoll = $matches[1].Trim()
    }

    if ($certRoll) {
        $result.CertificateRollNo = $certRoll
    } else {
        $null = $issues.Add("NPTEL Roll No / Certificate ID not detected")
    }

    # --------------------------------------------------------------------------
    # 7. Recommended Credits Extraction
    # --------------------------------------------------------------------------
    $credits = $null

    if ($cleanText -match '(?i)(?:credits?\s*recommended|no\.\s*of\s*credits)[^0-9\n\r]{0,15}([1-4])\b') {
        $credits = [int]$matches[1]
    } elseif ($cleanText -match '(?i)\b([1-4])\s*credits?\b') {
        $credits = [int]$matches[1]
    } elseif ($cleanText -match '(?i)12\s*weeks?\s*(?:course)?') {
        $credits = 3
    } elseif ($cleanText -match '(?i)8\s*weeks?\s*(?:course)?') {
        $credits = 2
    } elseif ($cleanText -match '(?i)4\s*weeks?\s*(?:course)?') {
        $credits = 1
    }

    if ($credits) {
        $result.Credits = $credits
    }

    # --------------------------------------------------------------------------
    # Confidence Score & Final Success Assessment
    # --------------------------------------------------------------------------
    $matchedFieldsCount = 0
    if ($result.CandidateName)   { $matchedFieldsCount++ }
    if ($result.CourseName)      { $matchedFieldsCount++ }
    if ($result.AssignmentMarks) { $matchedFieldsCount++ }
    if ($result.ExamMarks)       { $matchedFieldsCount++ }
    if ($result.TotalMarks)      { $matchedFieldsCount++ }
    if ($result.CertificateRollNo) { $matchedFieldsCount++ }

    if ($matchedFieldsCount -ge 5) {
        $result.Confidence = "High"
        $result.Success    = $true
    } elseif ($matchedFieldsCount -ge 3) {
        $result.Confidence = "Medium"
        $result.Success    = $true
    } else {
        $result.Confidence = "Low"
        $result.Success    = ($result.TotalMarks -ne $null -or $result.AssignmentMarks -ne $null)
    }

    $result.Issues = @($issues)
    return $result
}

# ==============================================================================
# 5-Rule Examination Verification Engine & Under Review Policy
# ==============================================================================

function Compare-ExamTextFuzzy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Expected = "",

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Actual = "",

        [string[]]$StopWords = @('introduction', 'to', 'the', 'an', 'a', 'of', 'in', 'and', 'nptel', 'course', 'mr', 'ms', 'shri', 'smt', 'dr', 'mrs')
    )

    if ([string]::IsNullOrWhiteSpace($Expected) -or [string]::IsNullOrWhiteSpace($Actual)) {
        return $false
    }

    $cleanExp = ($Expected.ToLower() -replace '[^\w\s]', ' ' -replace '\s+', ' ').Trim()
    $cleanAct = ($Actual.ToLower()   -replace '[^\w\s]', ' ' -replace '\s+', ' ').Trim()

    # Exact or substring match
    if ($cleanExp -eq $cleanAct -or $cleanExp.Contains($cleanAct) -or $cleanAct.Contains($cleanExp)) {
        return $true
    }

    # Significant token matching
    $tokensExp = @($cleanExp -split ' ' | Where-Object { $_.Length -ge 2 -and $_ -notin $StopWords })
    $tokensAct = @($cleanAct -split ' ' | Where-Object { $_.Length -ge 2 -and $_ -notin $StopWords })

    if ($tokensExp.Count -eq 0 -or $tokensAct.Count -eq 0) {
        return ($cleanExp -eq $cleanAct)
    }

    $commonTokens = @($tokensExp | Where-Object { $tokensAct -contains $_ })
    $minCount = [Math]::Min($tokensExp.Count, $tokensAct.Count)
    if ($minCount -eq 0) { return $false }

    $ratio = $commonTokens.Count / $minCount
    return ($ratio -ge 0.5)
}

function Test-ExamVerificationRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Student,

        [Parameter(Mandatory = $false)]
        $CertificateData,

        [Parameter(Mandatory = $false)]
        $Course = $null,

        [switch]$AllowRounding
    )

    $verResult = [PSCustomObject]@{
        Status                  = "Under Review"
        Remarks                 = ""
        RuleCourseMatch         = $false
        RuleIdentityMatch       = $false
        RuleAssignmentMatch     = $false
        RuleExamMatch           = $false
        RuleTotalMatch          = $false
        Discrepancies           = @()
        VerifiedAssignmentMarks = $null
        VerifiedExamMarks       = $null
        VerifiedTotalMarks      = $null
        CertificateRollNo       = $null
        Credits                 = $null
    }

    # 0. Check if Certificate Data exists and was read
    if (-not $CertificateData -or -not $CertificateData.Success) {
        $reasons = if ($CertificateData -and $CertificateData.Issues -and $CertificateData.Issues.Count -gt 0) {
            $CertificateData.Issues -join "; "
        } else {
            "Certificate not found or unreadable via OCR"
        }
        $verResult.Status        = "Under Review"
        $verResult.Remarks       = "Under Review: $reasons"
        $verResult.Discrepancies = @($reasons)
        return $verResult
    }

    # Populate verified/extracted data fields from certificate
    $verResult.VerifiedAssignmentMarks = [string]$CertificateData.AssignmentMarks
    $verResult.VerifiedExamMarks       = [string]$CertificateData.ExamMarks
    $verResult.VerifiedTotalMarks      = [string]$CertificateData.TotalMarks
    $verResult.CertificateRollNo       = [string]$CertificateData.CertificateRollNo
    $verResult.Credits                 = if ($CertificateData.Credits) { [int]$CertificateData.Credits } else { $null }

    $discrepancies = [System.Collections.ArrayList]@()
    $hasRoundingUsed = $false

    # --------------------------------------------------------------------------
    # Rule 1: Course Match
    # --------------------------------------------------------------------------
    $expectedCourse = if ($Course -and $Course.Name) { [string]$Course.Name } elseif ($Student.Subject) { [string]$Student.Subject } else { "" }
    $certCourse     = [string]$CertificateData.CourseName

    if (Compare-ExamTextFuzzy -Expected $expectedCourse -Actual $certCourse) {
        $verResult.RuleCourseMatch = $true
    } else {
        $null = $discrepancies.Add("Course mismatch (Expected: '$expectedCourse' vs Certificate: '$certCourse')")
    }

    # --------------------------------------------------------------------------
    # Rule 2: Identity Match (Candidate Name)
    # --------------------------------------------------------------------------
    $studentName = [string]$Student.Name
    $certName    = [string]$CertificateData.CandidateName

    if (Compare-ExamTextFuzzy -Expected $studentName -Actual $certName) {
        $verResult.RuleIdentityMatch = $true
    } else {
        $null = $discrepancies.Add("Identity mismatch (Student: '$studentName' vs Certificate: '$certName')")
    }

    # --------------------------------------------------------------------------
    # Rule 3: Assignment Marks Match (/25)
    # --------------------------------------------------------------------------
    $declAssignStr = ([string]$Student.DeclaredAssignmentMarks -replace '/\s*25', '').Trim()
    $certAssignStr = ([string]$CertificateData.AssignmentMarks -replace '/\s*25', '').Trim()
    $dAssign = 0.0
    $cAssign = 0.0
    $dAssignOk = [double]::TryParse($declAssignStr, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$dAssign)
    $cAssignOk = [double]::TryParse($certAssignStr, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$cAssign)

    if ($dAssignOk -and $cAssignOk) {
        if ([Math]::Abs($dAssign - $cAssign) -lt 0.001) {
            $verResult.RuleAssignmentMatch = $true
        } elseif ($AllowRounding -and ([Math]::Round($dAssign, 0, [System.MidpointRounding]::AwayFromZero) -eq [Math]::Round($cAssign, 0, [System.MidpointRounding]::AwayFromZero))) {
            $verResult.RuleAssignmentMatch = $true
            $hasRoundingUsed = $true
        } else {
            $remSuffix = if ($AllowRounding) { "after rounding " } else { "" }
            $null = $discrepancies.Add("Assignment marks mismatch ${remSuffix}(Declared: $declAssignStr vs Certificate: $certAssignStr)")
        }
    } else {
        $null = $discrepancies.Add("Assignment marks missing or non-numeric (Declared: '$declAssignStr' vs Certificate: '$certAssignStr')")
    }

    # --------------------------------------------------------------------------
    # Rule 4: Proctored Exam Marks Match (/75)
    # --------------------------------------------------------------------------
    $declExamStr = ([string]$Student.DeclaredExamMarks -replace '/\s*75', '').Trim()
    $certExamStr = ([string]$CertificateData.ExamMarks -replace '/\s*75', '').Trim()
    $dExam = 0.0
    $cExam = 0.0
    $dExamOk = [double]::TryParse($declExamStr, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$dExam)
    $cExamOk = [double]::TryParse($certExamStr, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$cExam)

    if ($dExamOk -and $cExamOk) {
        if ([Math]::Abs($dExam - $cExam) -lt 0.001) {
            $verResult.RuleExamMatch = $true
        } elseif ($AllowRounding -and ([Math]::Round($dExam, 0, [System.MidpointRounding]::AwayFromZero) -eq [Math]::Round($cExam, 0, [System.MidpointRounding]::AwayFromZero))) {
            $verResult.RuleExamMatch = $true
            $hasRoundingUsed = $true
        } else {
            $remSuffix = if ($AllowRounding) { "after rounding " } else { "" }
            $null = $discrepancies.Add("Exam marks mismatch ${remSuffix}(Declared: $declExamStr vs Certificate: $certExamStr)")
        }
    } else {
        $null = $discrepancies.Add("Exam marks missing or non-numeric (Declared: '$declExamStr' vs Certificate: '$certExamStr')")
    }

    # --------------------------------------------------------------------------
    # Rule 5: Consolidated Total Marks Match (/100)
    # --------------------------------------------------------------------------
    $declTotalStr = ([string]$Student.DeclaredTotalMarks -replace '/\s*100', '' -replace '%', '').Trim()
    $certTotalStr = ([string]$CertificateData.TotalMarks -replace '/\s*100', '' -replace '%', '').Trim()
    $dTotal = 0.0
    $cTotal = 0.0
    $dTotalOk = [double]::TryParse($declTotalStr, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$dTotal)
    $cTotalOk = [double]::TryParse($certTotalStr, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$cTotal)

    if ($dTotalOk -and $cTotalOk) {
        if ([Math]::Abs($dTotal - $cTotal) -lt 0.001) {
            $verResult.RuleTotalMatch = $true
        } elseif ($AllowRounding -and ([Math]::Round($dTotal, 0, [System.MidpointRounding]::AwayFromZero) -eq [Math]::Round($cTotal, 0, [System.MidpointRounding]::AwayFromZero))) {
            $verResult.RuleTotalMatch = $true
            $hasRoundingUsed = $true
        } else {
            $remSuffix = if ($AllowRounding) { "after rounding " } else { "" }
            $null = $discrepancies.Add("Total marks mismatch ${remSuffix}(Declared: $declTotalStr vs Certificate: $certTotalStr)")
        }
    } else {
        $null = $discrepancies.Add("Total marks missing or non-numeric (Declared: '$declTotalStr' vs Certificate: '$certTotalStr')")
    }

    # --------------------------------------------------------------------------
    # Overall Verification Verdict
    # --------------------------------------------------------------------------
    $verResult.Discrepancies = @($discrepancies)

    if ($discrepancies.Count -eq 0) {
        $verResult.Status  = "Verified"
        if ($hasRoundingUsed) {
            $verResult.Remarks = "Verified (Rounded Match)"
        } else {
            $verResult.Remarks = "All 5 Rules Verified (Course, Identity, Assignment, Exam, Total Marks matched)"
        }
    } else {
        $verResult.Status  = "Under Review"
        $verResult.Remarks = "Under Review: " + ($discrepancies -join "; ")
    }

    return $verResult
}

# ==============================================================================
# Automated Batch Examination Verification Pipeline
# ==============================================================================

function Invoke-CourseExamVerificationPipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Course,
        [string]$DataDir = $null,
        [scriptblock]$ProgressCallback = $null,
        [switch]$Force,
        [switch]$AllowRounding
    )

    $appRoot = Split-Path -Parent $PSScriptRoot
    if (-not $DataDir) {
        $DataDir = Join-Path $appRoot "data"
    }

    # Ensure helper modules are loaded
    $ocrModule = Join-Path $PSScriptRoot "OcrEngine.ps1"
    if (Test-Path -LiteralPath $ocrModule) { . $ocrModule }

    $sheetModule = Join-Path $PSScriptRoot "Import-StudentSheet.ps1"
    if (Test-Path -LiteralPath $sheetModule) { . $sheetModule }

    $cName = if ($Course.Name) { [string]$Course.Name } else { "Course" }
    $cleanCourseName = ($cName -replace '[\\/:*?"<>|]', '_').Trim()

    # Load exam results store
    $store = Get-CourseExamResultsStore -CourseId $Course.Id -CourseName $Course.Name -ExamResultsSheet $Course.ExamResultsSheet -DataDir $DataDir
    if (-not $store -or -not $store.Students -or $store.Students.Count -eq 0) {
        throw "No student exam responses found for course '$cName'. Please attach an examination results sheet first."
    }

    $students = @($store.Students)
    $totalCount = $students.Count

    # Resolve certificates directory: data/Courses/<CourseName>/certificates
    $certsDir = Join-Path $DataDir "Courses\$cleanCourseName\certificates"

    $verifiedCount  = 0
    $reviewCount    = 0
    $missingCount   = 0
    $skippedCount   = 0
    $processedCount = 0
    $index          = 0

    foreach ($student in $students) {
        $index++
        $rollNo = if ($student.RollNo) { [string]$student.RollNo } else { "Student_$index" }
        $cleanRoll = ($rollNo -replace '[\\/:*?"<>|]', '_').Trim()
        $currentStatus = if ($student.PSObject.Properties['ExamVerificationStatus']) { [string]$student.ExamVerificationStatus } else { "Pending" }

        # 1. Delta Sync: Preserve already verified students unless -Force is specified
        $isPreservedVerified = (-not $Force -and $currentStatus -eq "Verified")
        # If AllowRounding is FALSE, do not preserve students who were only verified via rounding!
        if ($isPreservedVerified -and -not $AllowRounding -and ($student.ExamVerificationRemarks -like "*round*")) {
            $isPreservedVerified = $false
        }
        if ($isPreservedVerified) {
            $verifiedCount++
            $skippedCount++
            if ($ProgressCallback) {
                & $ProgressCallback $index $totalCount $student "Preserved (Already Verified)"
            }
            continue
        }

        $processedCount++

        # 2. Locate Certificate on Disk
        $certPath = $null
        if ($student.PSObject.Properties['LocalCertificatePath'] -and $student.LocalCertificatePath -and (Test-Path -LiteralPath $student.LocalCertificatePath)) {
            $certPath = [string]$student.LocalCertificatePath
        } else {
            $cachedCert = Get-ChildItem -LiteralPath $certsDir -Filter "${cleanRoll}_certificate.*" -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 } | Select-Object -First 1
            if ($cachedCert) {
                $certPath = $cachedCert.FullName
                if ($student.PSObject.Properties['LocalCertificatePath']) {
                    $student.LocalCertificatePath = $cachedCert.FullName
                } else {
                    $student | Add-Member -NotePropertyName 'LocalCertificatePath' -NotePropertyValue $cachedCert.FullName -Force
                }
            }
        }

        # If certificate is missing on disk
        if (-not $certPath -or -not (Test-Path -LiteralPath $certPath)) {
            $missingCount++
            $reviewCount++
            $stStatus = "Under Review"
            $stRemark = "Under Review: Certificate file missing on disk (Import or Download certificates first)"

            if ($student.PSObject.Properties['ExamVerificationStatus']) { $student.ExamVerificationStatus = $stStatus } else { $student | Add-Member -NotePropertyName 'ExamVerificationStatus' -NotePropertyValue $stStatus -Force }
            if ($student.PSObject.Properties['ExamVerificationRemarks']) { $student.ExamVerificationRemarks = $stRemark } else { $student | Add-Member -NotePropertyName 'ExamVerificationRemarks' -NotePropertyValue $stRemark -Force }

            if ($ProgressCallback) {
                & $ProgressCallback $index $totalCount $student "Missing Certificate"
            }
            continue
        }

        # Check if structured certificate data was previously extracted and cached
        $certExtracted = $null
        if (-not $Force -and $student.CertificateCandidateName -and $student.CertificateCourseName -and ($student.VerifiedTotalMarks -or $student.VerifiedAssignmentMarks)) {
            $certExtracted = [PSCustomObject]@{
                Success           = $true
                CandidateName     = [string]$student.CertificateCandidateName
                CourseName        = [string]$student.CertificateCourseName
                AssignmentMarks   = [string]$student.VerifiedAssignmentMarks
                ExamMarks         = [string]$student.VerifiedExamMarks
                TotalMarks        = [string]$student.VerifiedTotalMarks
                CertificateRollNo = [string]$student.CertificateRollNo
                Credits           = if ($student.Credits) { [int]$student.Credits } else { $null }
                Issues            = @()
            }
        }

        if (-not $certExtracted) {
            # 3. Render PDF (if needed) & Run Native WinRT OCR
            if ($ProgressCallback) {
                & $ProgressCallback $index $totalCount $student "Running OCR on certificate..."
            }

            $ocrData = Get-CertificateOcrText -CertificateFilePath $certPath
            if (-not $ocrData.Success -or -not $ocrData.RawText -or -not $ocrData.RawText.Trim()) {
                $reviewCount++
                $errMsg = if ($ocrData.Error) { $ocrData.Error } else { "Unreadable or blurry certificate image/PDF" }
                $stStatus = "Under Review"
                $stRemark = "Under Review: OCR failed ($errMsg)"

                if ($student.PSObject.Properties['ExamVerificationStatus']) { $student.ExamVerificationStatus = $stStatus } else { $student | Add-Member -NotePropertyName 'ExamVerificationStatus' -NotePropertyValue $stStatus -Force }
                if ($student.PSObject.Properties['ExamVerificationRemarks']) { $student.ExamVerificationRemarks = $stRemark } else { $student | Add-Member -NotePropertyName 'ExamVerificationRemarks' -NotePropertyValue $stRemark -Force }

                if ($ProgressCallback) {
                    & $ProgressCallback $index $totalCount $student "OCR Unreadable"
                }
                continue
            }

            # 4. Extract structured certificate data
            $certExtracted = Extract-CertificateData -OcrResult $ocrData
        }

        # 5. Evaluate the 5 Verification Rules
        $ruleOutcome = Test-ExamVerificationRules -Student $student -CertificateData $certExtracted -Course $Course -AllowRounding:$AllowRounding

        # Update student record properties
        if ($student.PSObject.Properties['ExamVerificationStatus']) {
            $student.ExamVerificationStatus = $ruleOutcome.Status
        } else {
            $student | Add-Member -NotePropertyName 'ExamVerificationStatus' -NotePropertyValue $ruleOutcome.Status -Force
        }

        if ($student.PSObject.Properties['ExamVerificationRemarks']) {
            $student.ExamVerificationRemarks = $ruleOutcome.Remarks
        } else {
            $student | Add-Member -NotePropertyName 'ExamVerificationRemarks' -NotePropertyValue $ruleOutcome.Remarks -Force
        }

        # Save extracted certificate fields
        if ($certExtracted.CourseName) {
            if ($student.PSObject.Properties['CertificateCourseName']) { $student.CertificateCourseName = [string]$certExtracted.CourseName } else { $student | Add-Member -NotePropertyName 'CertificateCourseName' -NotePropertyValue ([string]$certExtracted.CourseName) -Force }
        }
        if ($certExtracted.CandidateName) {
            if ($student.PSObject.Properties['CertificateCandidateName']) { $student.CertificateCandidateName = [string]$certExtracted.CandidateName } else { $student | Add-Member -NotePropertyName 'CertificateCandidateName' -NotePropertyValue ([string]$certExtracted.CandidateName) -Force }
        }
        if ($certExtracted.AssignmentMarks) {
            if ($student.PSObject.Properties['VerifiedAssignmentMarks']) { $student.VerifiedAssignmentMarks = [string]$certExtracted.AssignmentMarks } else { $student | Add-Member -NotePropertyName 'VerifiedAssignmentMarks' -NotePropertyValue ([string]$certExtracted.AssignmentMarks) -Force }
        }
        if ($certExtracted.ExamMarks) {
            if ($student.PSObject.Properties['VerifiedExamMarks']) { $student.VerifiedExamMarks = [string]$certExtracted.ExamMarks } else { $student | Add-Member -NotePropertyName 'VerifiedExamMarks' -NotePropertyValue ([string]$certExtracted.ExamMarks) -Force }
        }
        if ($certExtracted.TotalMarks) {
            if ($student.PSObject.Properties['VerifiedTotalMarks']) { $student.VerifiedTotalMarks = [string]$certExtracted.TotalMarks } else { $student | Add-Member -NotePropertyName 'VerifiedTotalMarks' -NotePropertyValue ([string]$certExtracted.TotalMarks) -Force }
        }
        if ($certExtracted.CertificateRollNo) {
            if ($student.PSObject.Properties['CertificateRollNo']) { $student.CertificateRollNo = [string]$certExtracted.CertificateRollNo } else { $student | Add-Member -NotePropertyName 'CertificateRollNo' -NotePropertyValue ([string]$certExtracted.CertificateRollNo) -Force }
        }
        if ($certExtracted.Credits) {
            if ($student.PSObject.Properties['Credits']) { $student.Credits = [int]$certExtracted.Credits } else { $student | Add-Member -NotePropertyName 'Credits' -NotePropertyValue ([int]$certExtracted.Credits) -Force }
        }

        if ($ruleOutcome.Status -eq "Verified") {
            $verifiedCount++
        } else {
            $reviewCount++
        }

        if ($ProgressCallback) {
            & $ProgressCallback $index $totalCount $student "$($ruleOutcome.Status)"
        }
    }

    # 6. Save updated store to data/Courses/<CourseName>/exam_results.json
    $store.Students = $students
    $store.LastSync = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Save-CourseExamResultsStore -Store $store -CourseId $Course.Id -CourseName $Course.Name -DataDir $DataDir

    # 7. Update the Result Verification Sheet Excel file if it exists
    $sheetSync = Export-CourseExamVerificationSheetData -Course $Course -Students $students

    return [PSCustomObject]@{
        CourseId              = $Course.Id
        CourseName            = $Course.Name
        TotalCount            = $totalCount
        ProcessedCount        = $processedCount
        VerifiedCount         = $verifiedCount
        ReviewCount           = $reviewCount
        MissingCount          = $missingCount
        SkippedCount          = $skippedCount
        VerificationSheetSync = $sheetSync
    }
}
 
function Export-CourseExamVerificationSheetData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Course,
        [Parameter(Mandatory = $true)]
        $Students
    )

    $vSheetPath = if ($Course.PSObject.Properties['ExamVerificationSheet']) { [string]$Course.ExamVerificationSheet } else { $null }
    if (-not $vSheetPath -and $Course.ExamResultsSheet) {
        $examDir = [System.IO.Path]::GetDirectoryName([string]$Course.ExamResultsSheet)
        $cName = if ($Course.Name) { [string]$Course.Name } else { "Course" }
        $cleanName = ($cName -replace '[\\/:*?"<>|]', '_').Trim()
        $candidateXlsx = Join-Path $examDir "${cleanName}_Result_Verification_Sheet.xlsx"
        if (Test-Path -LiteralPath $candidateXlsx) { $vSheetPath = $candidateXlsx }
    }

    if (-not $vSheetPath -or -not (Test-Path -LiteralPath $vSheetPath)) {
        return [PSCustomObject]@{ Success = $true; Skipped = $true; Path = $vSheetPath }
    }

    if (Test-FileLocked -Path $vSheetPath) {
        $fName = [System.IO.Path]::GetFileName($vSheetPath)
        return [PSCustomObject]@{
            Success  = $false
            Error    = "FILE_LOCKED"
            Path     = $vSheetPath
            FileName = $fName
        }
    }

    try {
        $parsedVer = Import-StudentSheet -Path $vSheetPath
        if ($parsedVer.Success -and $parsedVer.Rows.Count -gt 0) {
            $statusMap = @{}
            $remarkMap = @{}
            foreach ($st in $Students) {
                $k = if ($st.RollNo) { $st.RollNo.Trim().ToLower() } elseif ($st.Email) { $st.Email.Trim().ToLower() } else { "" }
                if ($k) {
                    $statusMap[$k] = [string]$st.ExamVerificationStatus
                    $remarkMap[$k] = [string]$st.ExamVerificationRemarks
                }
            }

            $rollHeader = if ($parsedVer.ColumnMap -and $parsedVer.ColumnMap.RollNo) { $parsedVer.ColumnMap.RollNo } else { $null }
            $emailHeader = if ($parsedVer.ColumnMap -and $parsedVer.ColumnMap.Email) { $parsedVer.ColumnMap.Email } else { $null }
            $updatedRows = [System.Collections.Generic.List[object]]::new()

            foreach ($row in $parsedVer.Rows) {
                $rDict = [ordered]@{}
                foreach ($p in $row.PSObject.Properties) {
                    $rDict[$p.Name] = $p.Value
                }
                $rowRoll = if ($rollHeader -and $rDict.Contains($rollHeader)) { [string]$rDict[$rollHeader] } else { "" }
                $rowEmail = if ($emailHeader -and $rDict.Contains($emailHeader)) { [string]$rDict[$emailHeader] } else { "" }
                $k = if ($rowRoll) { $rowRoll.Trim().ToLower() } elseif ($rowEmail) { $rowEmail.Trim().ToLower() } else { "" }

                if ($k -and $statusMap.ContainsKey($k)) {
                    $rDict['Verification Status'] = $statusMap[$k]
                    $rDict['Verification Remarks'] = $remarkMap[$k]
                }
                $updatedRows.Add([PSCustomObject]$rDict)
            }

            # Export back to Excel / CSV
            $hasImportExcel = (Get-Module -Name ImportExcel -ListAvailable)
            if ($hasImportExcel -and $vSheetPath.EndsWith(".xlsx")) {
                Import-Module ImportExcel -ErrorAction SilentlyContinue
                try {
                    $updatedRows | Export-Excel -Path $vSheetPath -WorksheetName "Result Verification" -AutoSize -BoldTopRow -FreezeTopRow -ClearSheet
                } catch {
                    if ((Test-FileLocked -Path $vSheetPath) -or $_.Exception.Message -match "being used by another process|Error saving file|Save") {
                        return [PSCustomObject]@{
                            Success  = $false
                            Error    = "FILE_LOCKED"
                            Path     = $vSheetPath
                            FileName = [System.IO.Path]::GetFileName($vSheetPath)
                        }
                    }
                    throw
                }
            } else {
                $updatedRows | Export-Csv -Path $vSheetPath -NoTypeInformation -Encoding UTF8
            }
        }
        return [PSCustomObject]@{ Success = $true; Error = $null; Path = $vSheetPath }
    } catch {
        # Non-fatal if Excel export fails; exam_results.json is preserved
        $fName = [System.IO.Path]::GetFileName($vSheetPath)
        if ((Test-FileLocked -Path $vSheetPath) -or $_.Exception.Message -match "being used by another process|Error saving file|Save") {
            return [PSCustomObject]@{
                Success  = $false
                Error    = "FILE_LOCKED"
                Path     = $vSheetPath
                FileName = $fName
            }
        }
        return [PSCustomObject]@{
            Success  = $false
            Error    = $_.Exception.Message
            Path     = $vSheetPath
            FileName = $fName
        }
    }
}

