# ==============================================================================
# NPTEL Operations Studio — 5-Rule Verification Matcher & Automated Pipeline
# File: modules/VerificationEngine.ps1
# Purpose: Evaluates Payment Status, Fee Amount, Course Title, Authenticity,
#          and Student Identity against OCR tokens. Writes results to students.json
#          and the Course Verification Sheet Excel file.
# ==============================================================================

# Helper to normalize strings for comparison (removes punctuation and extra spaces)
function Normalize-TextForMatching {
    param([string]$Text)
    if (-not $Text) { return "" }
    $clean = $Text.ToLower() -replace '[^a-z0-9\s]', ' '
    return ($clean -split '\s+' | Where-Object { $_ }) -join ' '
}

# 1. 5-Rule Verification Matcher
function Test-ReceiptVerificationRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Student,
        [Parameter(Mandatory = $true)]
        [string]$OcrText,
        [array]$OcrLines = @(),
        [string]$CourseName = ""
    )

    $normOcr = Normalize-TextForMatching $OcrText
    $failedRemarks = [System.Collections.ArrayList]@()

    # --------------------------------------------------------------------------
    # RULE 1: Payment Status Check
    # Must confirm "successful" and guard against "failed"
    # --------------------------------------------------------------------------
    $rule1Pass = $false
    $hasSuccessWord = ($normOcr -match '\b(?:successful|payment\s+is\s+successful|payment\s+successful|paid)\b')
    $hasFailedWord  = ($normOcr -match '\b(?:failed|payment\s+failed|transaction\s+failed|declined)\b')

    if ($hasSuccessWord -and -not $hasFailedWord) {
        $rule1Pass = $true
    } elseif ($hasFailedWord) {
        $null = $failedRemarks.Add("Payment failed or declined")
    } else {
        $null = $failedRemarks.Add("Payment success confirmation not found")
    }

    # --------------------------------------------------------------------------
    # RULE 2: Fee Amount Check
    # Must detect official NPTEL exam fee (₹1,000 standard or ₹1,100 late fee)
    # --------------------------------------------------------------------------
    $rule2Pass = $false
    # Match 1000 or 1100 (alone or with currency symbols)
    if ($normOcr -match '\b(?:1000|1100)\b') {
        $rule2Pass = $true
    } else {
        $null = $failedRemarks.Add("Fee amount not Rs. 1,000 or Rs. 1,100")
    }

    # --------------------------------------------------------------------------
    # RULE 3: Course Title Matching
    # Fuzzy keyword matching against active course name or student subject
    # --------------------------------------------------------------------------
    $rule3Pass = $false
    $targetCourse = if ($CourseName) { $CourseName } else { [string]$Student.Subject }
    $cleanTarget = Normalize-TextForMatching $targetCourse
    $compressedOcr = ($normOcr -replace '\s+', '')
    $compressedTarget = ($cleanTarget -replace '\s+', '')

    # Check 1: Space-insensitive substring match (e.g. 'softcomputing' in 'introductiontosoftcomputing')
    if ($compressedTarget.Length -ge 4 -and $compressedOcr.Contains($compressedTarget)) {
        $rule3Pass = $true
    }

    # Check 2: If student has a Subject attribute, test compressed match against it
    if (-not $rule3Pass -and $Student.Subject) {
        $cleanSubj = Normalize-TextForMatching ([string]$Student.Subject)
        $compressedSubj = ($cleanSubj -replace '\s+', '')
        if ($compressedSubj.Length -ge 4 -and $compressedOcr.Contains($compressedSubj)) {
            $rule3Pass = $true
        }
    }

    # Check 3: Tokenized keyword matching (accounting for stop words)
    if (-not $rule3Pass) {
        $candidateSources = @($cleanTarget)
        if ($Student.Subject) {
            $candidateSources += Normalize-TextForMatching ([string]$Student.Subject)
        }

        $stopWords = @('introduction', 'to', 'and', 'the', 'of', 'in', 'for', 'nptel', 'course', 'elective', 'online')

        foreach ($src in $candidateSources) {
            $keywords = @(($src -split '\s+') | Where-Object { $_.Length -gt 2 -and $_ -notin $stopWords })
            if ($keywords.Count -eq 0) {
                $keywords = @(($src -split '\s+') | Where-Object { $_.Length -gt 2 })
            }

            if ($keywords.Count -gt 0) {
                $matchedKeywords = 0
                foreach ($kw in $keywords) {
                    if ($normOcr -match [regex]::Escape($kw) -or $compressedOcr.Contains($kw)) {
                        $matchedKeywords++
                    }
                }
                if ($matchedKeywords -ge [Math]::Ceiling($keywords.Count * 0.5)) {
                    $rule3Pass = $true
                    break
                }
            }
        }
    }

    if (-not $rule3Pass) {
        $null = $failedRemarks.Add("Course title mismatch (Expected: '$targetCourse')")
    }

    # --------------------------------------------------------------------------
    # RULE 4: NPTEL / Razorpay Authenticity Check
    # Checks for official markers: support@nptel.iitm.ac.in, order_, pay_, nptel
    # --------------------------------------------------------------------------
    $rule4Pass = $false
    $hasNptelEmail = ($OcrText -match '(?i)support@nptel\.iitm\.ac\.in' -or $normOcr -match '\bnptel\b' -or $normOcr -match '\biitm\b')
    $hasOrderId    = ($OcrText -match '(?i)\border_[a-zA-Z0-9]{8,}\b')
    $hasPayId      = ($OcrText -match '(?i)\bpay_[a-zA-Z0-9]{8,}\b')

    if ($hasNptelEmail -or $hasOrderId -or $hasPayId) {
        $rule4Pass = $true
    } else {
        $null = $failedRemarks.Add("Missing NPTEL / Razorpay authenticity markers")
    }

    # --------------------------------------------------------------------------
    # RULE 5: Student Identity Cross-Check
    # Matches receipt greeting ("Hello <Name>,") against the roster name
    # --------------------------------------------------------------------------
    $rule5Pass = $false
    $studentName = if ($Student.Name) { [string]$Student.Name } else { "" }
    $normStudentName = Normalize-TextForMatching $studentName

    if ($normStudentName) {
        $nameParts = @($normStudentName -split '\s+' | Where-Object { $_.Length -ge 3 })
        $firstName = if ($nameParts.Count -gt 0) { $nameParts[0] } else { "" }

        # Check if greeting pattern "hello <name>" exists, or full/first name appears in receipt
        $hasGreeting = ($normOcr -match "(?i)hello\s+([a-z\s]{3,30})")
        $greetingMatched = $false

        if ($hasGreeting) {
            $greetingName = $matches[1]
            if ($firstName -and $greetingName -match [regex]::Escape($firstName)) {
                $greetingMatched = $true
            }
        }

        # Check first name or full name presence
        if ($greetingMatched -or ($firstName -and $normOcr -match "\b$([regex]::Escape($firstName))\b")) {
            $rule5Pass = $true
        } else {
            $null = $failedRemarks.Add("Student name does not match receipt greeting ('$studentName')")
        }
    } else {
        # If student has no name in roster, rule cannot be checked
        $rule5Pass = $true
    }

    # --------------------------------------------------------------------------
    # Classification Outcome
    # --------------------------------------------------------------------------
    $allPass = $rule1Pass -and $rule2Pass -and $rule3Pass -and $rule4Pass -and $rule5Pass

    if ($allPass) {
        $feeLabel = if ($normOcr -match '\b1100\b') { "Fee: Rs. 1,100 (Late Fee)" } else { "Fee: Rs. 1,000" }
        return [PSCustomObject]@{
            Status      = "Verified"
            Remarks     = "Clean match ($feeLabel confirmed, Course & Identity matched)"
            Rule1Pass   = $rule1Pass
            Rule2Pass   = $rule2Pass
            Rule3Pass   = $rule3Pass
            Rule4Pass   = $rule4Pass
            Rule5Pass   = $rule5Pass
            FailedRules = @()
        }
    } else {
        return [PSCustomObject]@{
            Status      = "Under Review"
            Remarks     = ($failedRemarks -join " | ")
            Rule1Pass   = $rule1Pass
            Rule2Pass   = $rule2Pass
            Rule3Pass   = $rule3Pass
            Rule4Pass   = $rule4Pass
            Rule5Pass   = $rule5Pass
            FailedRules = @($failedRemarks)
        }
    }
}

# 2. Automated Course Verification Pipeline
function Invoke-CourseVerificationPipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Course,
        [string]$DataDir = $null,
        [string]$LocalReceiptsFolder = $null,
        [scriptblock]$ProgressCallback = $null,
        [switch]$Force
    )

    $appRoot = Split-Path -Parent $PSScriptRoot
    if (-not $DataDir) {
        $DataDir = Join-Path $appRoot "data"
    }

    # Load helper modules if needed
    $dlModule = Join-Path $PSScriptRoot "Download-Receipts.ps1"
    if (Test-Path $dlModule) { . $dlModule }

    $ocrModule = Join-Path $PSScriptRoot "OcrEngine.ps1"
    if (Test-Path $ocrModule) { . $ocrModule }

    $cName = if ($Course.Name) { [string]$Course.Name } else { "Course" }
    $cleanCourseName = ($cName -replace '[\\/:*?"<>|]', '_').Trim()

    # Load student store
    $store = Get-CourseStudentStore -CourseId $Course.Id -RegistrationSheet $Course.RegistrationSheet -CourseName $Course.Name
    if (-not $store -or -not $store.Students -or $store.Students.Count -eq 0) {
        throw "No student records found for course '$cName'."
    }

    $students = @($store.Students)
    $totalCount = $students.Count

    # Resolve course receipts folder: data/Courses/<CourseName>/receipts/
    $receiptsDir = Get-CourseReceiptsDirectory -CourseId $Course.Id -CourseName $Course.Name -DataDir $DataDir

    # Check for local receipts folder (default check on Desktop if not specified)
    if (-not $LocalReceiptsFolder -or -not (Test-Path -LiteralPath $LocalReceiptsFolder)) {
        $desktopTestData = Join-Path ([Environment]::GetFolderPath("Desktop")) "Test Data for Formee"
        if (Test-Path -LiteralPath $desktopTestData) {
            $LocalReceiptsFolder = $desktopTestData
        }
    }

    $verifiedCount = 0
    $reviewCount = 0
    $unregCount = 0
    $processedCount = 0
    $index = 0

    foreach ($student in $students) {
        $index++
        $rollNo = if ($student.RollNo) { [string]$student.RollNo } else { "Student_$index" }
        $name = if ($student.Name) { [string]$student.Name } else { "" }
        $isReg = if ($student.PSObject.Properties['IsRegistered']) { $student.IsRegistered } else { $true }
        $currentStatus = if ($student.PSObject.Properties['VerificationStatus']) { [string]$student.VerificationStatus } else { "Pending" }

        # 1. Non-Registered Students (Fast-Path Skip)
        if ($isReg -eq $false) {
            $unregCount++
            if ($student.PSObject.Properties['VerificationStatus']) { $student.VerificationStatus = "Did Not Register" } else { $student | Add-Member -NotePropertyName 'VerificationStatus' -NotePropertyValue "Did Not Register" -Force }
            if ($student.PSObject.Properties['VerificationRemarks']) { $student.VerificationRemarks = "Student opted out of exam" } else { $student | Add-Member -NotePropertyName 'VerificationRemarks' -NotePropertyValue "Student opted out of exam" -Force }
            if ($ProgressCallback) {
                & $ProgressCallback $index $totalCount $student "Skipped (Did Not Register)"
            }
            continue
        }

        # 2. Delta Sync: Preserve already verified students unless -Force is specified
        if (-not $Force -and $currentStatus -eq "Verified") {
            $verifiedCount++
            if ($ProgressCallback) {
                & $ProgressCallback $index $totalCount $student "Preserved (Already Verified)"
            }
            continue
        }

        $processedCount++

        # 3. Retrieve or Ingest Receipt File
        $cleanRoll = ($rollNo -replace '[\\/:*?"<>|]', '_').Trim()
        $cachedReceipt = Get-ChildItem -LiteralPath $receiptsDir -Filter "${cleanRoll}_receipt.*" -ErrorAction SilentlyContinue | Select-Object -First 1

        $receiptPath = $null
        if ($cachedReceipt -and $cachedReceipt.Length -gt 0) {
            $receiptPath = $cachedReceipt.FullName
        } else {
            # Try single download/match
            $dlBatch = Invoke-ReceiptBatchDownload -CourseId $Course.Id -CourseName $Course.Name -Students @($student) -DataDir $DataDir -LocalReceiptsFolder $LocalReceiptsFolder
            if ($dlBatch.Results -and $dlBatch.Results[0].Success) {
                $receiptPath = $dlBatch.Results[0].LocalPath
            }
        }

        # If receipt could not be found or downloaded
        if (-not $receiptPath -or -not (Test-Path -LiteralPath $receiptPath)) {
            $errNote = if ($dlBatch -and $dlBatch.Results[0].Error) { $dlBatch.Results[0].Error } else { "Receipt file not found or inaccessible" }
            $reviewCount++
            if ($student.PSObject.Properties['VerificationStatus']) { $student.VerificationStatus = "Under Review" } else { $student | Add-Member -NotePropertyName 'VerificationStatus' -NotePropertyValue "Under Review" -Force }
            if ($student.PSObject.Properties['VerificationRemarks']) { $student.VerificationRemarks = "Flagged: $errNote" } else { $student | Add-Member -NotePropertyName 'VerificationRemarks' -NotePropertyValue "Flagged: $errNote" -Force }

            if ($ProgressCallback) {
                & $ProgressCallback $index $totalCount $student "Under Review (Missing Receipt)"
            }
            continue
        }

        # 4. Render PDF (if needed) & Run Native WinRT OCR
        if ($ProgressCallback) {
            & $ProgressCallback $index $totalCount $student "Running OCR on receipt..."
        }

        $ocrData = Get-ReceiptExtractedData -ReceiptFilePath $receiptPath
        if (-not $ocrData.Success -or -not $ocrData.RawText.Trim()) {
            $reviewCount++
            $errMsg = if ($ocrData.Error) { $ocrData.Error } else { "Unreadable or blurry receipt image" }
            if ($student.PSObject.Properties['VerificationStatus']) { $student.VerificationStatus = "Under Review" } else { $student | Add-Member -NotePropertyName 'VerificationStatus' -NotePropertyValue "Under Review" -Force }
            if ($student.PSObject.Properties['VerificationRemarks']) { $student.VerificationRemarks = "Flagged: $errMsg" } else { $student | Add-Member -NotePropertyName 'VerificationRemarks' -NotePropertyValue "Flagged: $errMsg" -Force }

            if ($ProgressCallback) {
                & $ProgressCallback $index $totalCount $student "Under Review (OCR Error)"
            }
            continue
        }

        # 5. Evaluate the 5 Verification Rules
        $ruleOutcome = Test-ReceiptVerificationRules -Student $student -OcrText $ocrData.RawText -OcrLines $ocrData.Lines -CourseName $Course.Name

        if ($student.PSObject.Properties['VerificationStatus']) {
            $student.VerificationStatus = $ruleOutcome.Status
        } else {
            $student | Add-Member -NotePropertyName 'VerificationStatus' -NotePropertyValue $ruleOutcome.Status -Force
        }

        if ($student.PSObject.Properties['VerificationRemarks']) {
            $student.VerificationRemarks = $ruleOutcome.Remarks
        } else {
            $student | Add-Member -NotePropertyName 'VerificationRemarks' -NotePropertyValue $ruleOutcome.Remarks -Force
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

    # 6. Save updated records to data/Courses/<CourseName>/students.json
    Save-CourseStudents -CourseId $Course.Id -Students $students -ColumnMap $store.ColumnMap -CourseName $Course.Name

    # 7. Update the Verification Sheet Excel file if it exists
    $vSheetPath = if ($Course.PSObject.Properties['VerificationSheet']) { [string]$Course.VerificationSheet } else { $null }
    if ($vSheetPath -and (Test-Path -LiteralPath $vSheetPath)) {
        try {
            $parsedVer = Import-StudentSheet -Path $vSheetPath
            if ($parsedVer.Success -and $parsedVer.Rows.Count -gt 0) {
                $statusMap = @{}
                $remarkMap = @{}
                foreach ($st in $students) {
                    $key = if ($st.RollNo) { $st.RollNo.Trim().ToLower() } else { "" }
                    if ($key) {
                        $statusMap[$key] = [string]$st.VerificationStatus
                        $remarkMap[$key] = [string]$st.VerificationRemarks
                    }
                }

                $rollHeader = if ($parsedVer.ColumnMap) { $parsedVer.ColumnMap.RollNo } else { $null }
                $updatedRows = [System.Collections.ArrayList]@()

                foreach ($row in $parsedVer.Rows) {
                    $rDict = [ordered]@{}
                    foreach ($p in $row.PSObject.Properties) {
                        $rDict[$p.Name] = $p.Value
                    }
                    $rowRoll = if ($rollHeader -and $rDict.Contains($rollHeader)) { [string]$rDict[$rollHeader] } else { "" }
                    $cleanRollKey = $rowRoll.Trim().ToLower()

                    if ($cleanRollKey -and $statusMap.ContainsKey($cleanRollKey)) {
                        $rDict['Verification Status'] = $statusMap[$cleanRollKey]
                        $rDict['Verification Remarks'] = $remarkMap[$cleanRollKey]
                    }
                    $null = $updatedRows.Add([PSCustomObject]$rDict)
                }

                # Export back to Excel / CSV
                $hasImportExcel = (Get-Module -Name ImportExcel -ListAvailable)
                if ($hasImportExcel -and $vSheetPath.EndsWith(".xlsx")) {
                    Import-Module ImportExcel -ErrorAction SilentlyContinue
                    $updatedRows | Export-Excel -Path $vSheetPath -WorksheetName "Verification" -AutoSize -BoldTopRow -FreezeTopRow -ClearSheet
                } else {
                    $updatedRows | Export-Csv -Path $vSheetPath -NoTypeInformation -Encoding UTF8
                }
            }
        } catch {
            # Non-fatal if Excel export fails; students.json is preserved
        }
    }

    return [PSCustomObject]@{
        CourseId        = $Course.Id
        CourseName      = $Course.Name
        TotalStudents   = $totalCount
        ProcessedCount  = $processedCount
        VerifiedCount   = $verifiedCount
        ReviewCount     = $reviewCount
        UnregCount      = $unregCount
    }
}

# ------------------------------------------------------------------------------
# 3. Smart Delta Response Synchronization (Google Form Delta Updates)
# ------------------------------------------------------------------------------
function Sync-CourseResponses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Course,
        [string]$NewSheetPath = $null,
        [string]$DataDir = $null
    )

    $appRoot = Split-Path -Parent $PSScriptRoot
    if (-not $DataDir) {
        $DataDir = Join-Path $appRoot "data"
    }

    # Load helper modules
    $importModule = Join-Path $PSScriptRoot "Import-StudentSheet.ps1"
    if (Test-Path $importModule) { . $importModule }

    $cName = if ($Course.Name) { [string]$Course.Name } else { "Course" }
    $cleanCourseName = ($cName -replace '[\\/:*?"<>|]', '_').Trim()

    $targetSheet = if ($NewSheetPath) { $NewSheetPath } else { [string]$Course.RegistrationSheet }
    if (-not $targetSheet -or -not (Test-Path -LiteralPath $targetSheet)) {
        throw "Registration spreadsheet not found on disk: $targetSheet"
    }

    # 1. Parse the new/updated registration sheet
    $sheetResult = Import-StudentSheet -Path $targetSheet
    if (-not $sheetResult.Success) {
        throw "Could not parse registration sheet: $($sheetResult.Error)"
    }

    # 2. Load existing course student store
    $store = Get-CourseStudentStore -CourseId $Course.Id -RegistrationSheet $Course.RegistrationSheet -CourseName $Course.Name -DataDir $DataDir
    $existingStudents = @($store.Students)

    # Build lookup map of existing students: Key = normalized RollNo, Fallback = Email
    $existingMap = @{}
    foreach ($st in $existingStudents) {
        $rollKey = if ($st.RollNo) { $st.RollNo.Trim().ToLower() } else { "" }
        if ($rollKey) {
            $existingMap[$rollKey] = $st
        } elseif ($st.Email) {
            $existingMap[$st.Email.Trim().ToLower()] = $st
        }
    }

    $dlModule = Join-Path $PSScriptRoot "Download-Receipts.ps1"
    if (Test-Path $dlModule) { . $dlModule }
    $receiptsDir = Get-CourseReceiptsDirectory -CourseId $Course.Id -CourseName $Course.Name -DataDir $DataDir

    $mergedStudents = [System.Collections.ArrayList]@()
    $newCount = 0
    $reverifiedCount = 0
    $updatedReviewCount = 0
    $preservedCount = 0
    $preservedVerifiedCount = 0

    foreach ($incoming in $sheetResult.Students) {
        $rollKey = if ($incoming.RollNo) { $incoming.RollNo.Trim().ToLower() } else { "" }
        $emailKey = if ($incoming.Email) { $incoming.Email.Trim().ToLower() } else { "" }

        $match = $null
        if ($rollKey -and $existingMap.ContainsKey($rollKey)) {
            $match = $existingMap[$rollKey]
        } elseif ($emailKey -and $existingMap.ContainsKey($emailKey)) {
            $match = $existingMap[$emailKey]
        }

        if (-not $match) {
            # -------------------------------------------------------------
            # CASE A: Brand New Student (New row from Google Form)
            # -------------------------------------------------------------
            $newCount++
            $isReg = if ($incoming.PSObject.Properties['IsRegistered']) { $incoming.IsRegistered } else { $true }
            $status = if ($isReg -eq $false) { "Did Not Register" } else { "Pending" }
            $remarks = if ($isReg -eq $false) { "Student opted out of exam" } else { "Awaiting Verification" }

            if ($incoming.PSObject.Properties['VerificationStatus']) { $incoming.VerificationStatus = $status } else { $incoming | Add-Member -NotePropertyName 'VerificationStatus' -NotePropertyValue $status -Force }
            if ($incoming.PSObject.Properties['VerificationRemarks']) { $incoming.VerificationRemarks = $remarks } else { $incoming | Add-Member -NotePropertyName 'VerificationRemarks' -NotePropertyValue $remarks -Force }

            $null = $mergedStudents.Add($incoming)
        } else {
            # -------------------------------------------------------------
            # Existing Student Found: Check for updated Receipt Link
            # -------------------------------------------------------------
            $oldUrl = if ($match.ProofUrl) { $match.ProofUrl.Trim() } else { "" }
            $newUrl = if ($incoming.ProofUrl) { $incoming.ProofUrl.Trim() } else { "" }
            $oldStatus = if ($match.VerificationStatus) { [string]$match.VerificationStatus } else { "Pending" }
            $oldRemarks = if ($match.VerificationRemarks) { [string]$match.VerificationRemarks } else { "Awaiting Verification" }

            $urlChanged = ($oldUrl -and $newUrl -and ($oldUrl -ne $newUrl))

            # Copy updated fields from incoming sheet (name, email, subject, isReg, etc.)
            foreach ($prop in $incoming.PSObject.Properties) {
                if ($prop.Name -notin @('VerificationStatus', 'VerificationRemarks')) {
                    if ($match.PSObject.Properties[$prop.Name]) {
                        $match.($prop.Name) = $prop.Value
                    } else {
                        $match | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                    }
                }
            }

            if ($urlChanged) {
                # Purge old cached receipt so the new receipt is forced to download & OCR
                $cleanRoll = ($incoming.RollNo -replace '[\\/:*?"<>|]', '_').Trim()
                if ($receiptsDir -and (Test-Path -LiteralPath $receiptsDir)) {
                    Get-ChildItem -LiteralPath $receiptsDir -Filter "${cleanRoll}_receipt*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                }

                if ($oldStatus -eq "Verified") {
                    # CASE B: Previously verified student changed receipt link
                    $reverifiedCount++
                    $match.VerificationStatus = "Pending"
                    $match.VerificationRemarks = "Receipt link updated after verification; queued for re-verification"
                } else {
                    # CASE C: Under review / pending student submitted a new link
                    $updatedReviewCount++
                    $match.VerificationStatus = "Pending"
                    $match.VerificationRemarks = "Receipt link updated; queued for re-verification"
                }
            } else {
                # CASE D: Unchanged student
                $preservedCount++
                if ($oldStatus -eq "Verified") {
                    $preservedVerifiedCount++
                }
                $match.VerificationStatus = $oldStatus
                $match.VerificationRemarks = $oldRemarks
            }

            $null = $mergedStudents.Add($match)
        }
    }

    # 3. Save merged list back to data/Courses/<CourseName>/students.json
    $colMap = if ($sheetResult.ColumnMap) { $sheetResult.ColumnMap } else { $store.ColumnMap }
    Save-CourseStudents -CourseId $Course.Id -Students $mergedStudents -ColumnMap $colMap -CourseName $Course.Name -DataDir $DataDir

    # 4. Update the Course Verification Sheet (.xlsx / .csv)
    $vSheetPath = if ($Course.PSObject.Properties['VerificationSheet']) { [string]$Course.VerificationSheet } else { $null }
    if ($vSheetPath -and (Test-Path -LiteralPath $vSheetPath)) {
        try {
            $parsedVer = Import-StudentSheet -Path $vSheetPath
            if ($parsedVer.Success) {
                $statusMap = @{}
                $remarkMap = @{}
                foreach ($st in $mergedStudents) {
                    $k = if ($st.RollNo) { $st.RollNo.Trim().ToLower() } else { "" }
                    if ($k) {
                        $statusMap[$k] = [string]$st.VerificationStatus
                        $remarkMap[$k] = [string]$st.VerificationRemarks
                    }
                }

                $rollHeader = if ($parsedVer.ColumnMap) { $parsedVer.ColumnMap.RollNo } else { $null }
                $updatedRows = [System.Collections.ArrayList]@()
                $seenRolls = @{}

                # Update existing rows
                foreach ($row in $parsedVer.Rows) {
                    $rDict = [ordered]@{}
                    foreach ($p in $row.PSObject.Properties) {
                        $rDict[$p.Name] = $p.Value
                    }
                    $rowRoll = if ($rollHeader -and $rDict.Contains($rollHeader)) { [string]$rDict[$rollHeader] } else { "" }
                    $cleanRollKey = $rowRoll.Trim().ToLower()

                    if ($cleanRollKey) {
                        $seenRolls[$cleanRollKey] = $true
                        if ($statusMap.ContainsKey($cleanRollKey)) {
                            $rDict['Verification Status'] = $statusMap[$cleanRollKey]
                            $rDict['Verification Remarks'] = $remarkMap[$cleanRollKey]
                        }
                    }
                    $null = $updatedRows.Add([PSCustomObject]$rDict)
                }

                # Append any brand-new students that were not in the old verification sheet
                foreach ($st in $mergedStudents) {
                    $stRollKey = if ($st.RollNo) { $st.RollNo.Trim().ToLower() } else { "" }
                    if ($stRollKey -and (-not $seenRolls.ContainsKey($stRollKey))) {
                        $newDict = [ordered]@{}
                        if ($st.Raw -and $st.Raw -is [System.Collections.IDictionary]) {
                            foreach ($k in $st.Raw.Keys) { $newDict[$k] = $st.Raw[$k] }
                        } else {
                            if ($st.RollNo) { $newDict['RollNo'] = $st.RollNo }
                            if ($st.Name) { $newDict['Name'] = $st.Name }
                            if ($st.Email) { $newDict['Email'] = $st.Email }
                            if ($st.Subject) { $newDict['Subject'] = $st.Subject }
                            if ($st.ProofUrl) { $newDict['ProofUrl'] = $st.ProofUrl }
                        }
                        $newDict['Verification Status'] = [string]$st.VerificationStatus
                        $newDict['Verification Remarks'] = [string]$st.VerificationRemarks
                        $null = $updatedRows.Add([PSCustomObject]$newDict)
                    }
                }

                # Export back to Excel / CSV
                $hasImportExcel = (Get-Module -Name ImportExcel -ListAvailable)
                if ($hasImportExcel -and $vSheetPath.EndsWith(".xlsx")) {
                    Import-Module ImportExcel -ErrorAction SilentlyContinue
                    $updatedRows | Export-Excel -Path $vSheetPath -WorksheetName "Verification" -AutoSize -BoldTopRow -FreezeTopRow -ClearSheet
                } else {
                    $updatedRows | Export-Csv -Path $vSheetPath -NoTypeInformation -Encoding UTF8
                }
            }
        } catch { }
    }

    return [PSCustomObject]@{
        CourseName              = $Course.Name
        TotalRoster             = $mergedStudents.Count
        NewStudents             = $newCount
        ReverifiedStudents      = $reverifiedCount
        UpdatedReviewStudents   = $updatedReviewCount
        PreservedStudents       = $preservedCount
        PreservedVerifiedCount  = $preservedVerifiedCount
    }
}


