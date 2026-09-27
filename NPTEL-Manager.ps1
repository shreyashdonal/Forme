<#
.SYNOPSIS
NPTEL Management System - Real-State Controller
Course-Centric Workspace Router with Zero Dummy Data & 2-Stage Semester Lifecycle
#>

Set-StrictMode -Off

# 0. Process-Scope Execution Bypass & STA Assurance
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $scriptFile = if ($PSScriptRoot) { Join-Path $PSScriptRoot "NPTEL-Manager.ps1" } elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { ".\NPTEL-Manager.ps1" }
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "$scriptFile"
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms

# 1. Resolve Application Root Directory (Safe null checks)
function Resolve-AppRoot {
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "UI\MainWindow.xaml"))) {
        return $PSScriptRoot
    }
    if ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
        $cmdDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        if ($cmdDir -and (Test-Path (Join-Path $cmdDir "UI\MainWindow.xaml"))) {
            return $cmdDir
        }
    }
    $curr = (Get-Location).Path
    if (Test-Path (Join-Path $curr "UI\MainWindow.xaml")) {
        return $curr
    }
    return $curr
}

$appRoot = Resolve-AppRoot
$script:appRoot = $appRoot

# 1.1 Load Helper Modules
$importModule = Join-Path $appRoot "modules\Import-StudentSheet.ps1"
if (Test-Path $importModule) {
    . $importModule
}

$downloadModule = Join-Path $appRoot "modules\Download-Receipts.ps1"
if (Test-Path $downloadModule) {
    . $downloadModule
}

$ocrModule = Join-Path $appRoot "modules\OcrEngine.ps1"
if (Test-Path $ocrModule) {
    . $ocrModule
}

$verModule = Join-Path $appRoot "modules\VerificationEngine.ps1"
if (Test-Path $verModule) {
    . $verModule
}

# 2. State Storage (data/courses.json)
$dataDir = Join-Path $appRoot "data"
$script:dataDir = $dataDir
if (-not (Test-Path $dataDir)) {
    $null = New-Item -ItemType Directory -Path $dataDir
}

$coursesFile = Join-Path $dataDir "courses.json"
$script:courses = [System.Collections.ArrayList]@()

if (Test-Path $coursesFile) {
    try {
        $json = Get-Content $coursesFile -Raw -Encoding UTF8
        if ($json -and $json.Trim()) {
            $parsed = ConvertFrom-Json $json
            if ($parsed -is [System.Array]) {
                foreach ($item in $parsed) {
                    if (-not $item.PSObject.Properties['VerificationSheet']) {
                        $item | Add-Member -NotePropertyName 'VerificationSheet' -NotePropertyValue "" -Force
                    }
                    $null = $script:courses.Add($item)
                }
            } elseif ($parsed) {
                if (-not $parsed.PSObject.Properties['VerificationSheet']) {
                    $parsed | Add-Member -NotePropertyName 'VerificationSheet' -NotePropertyValue "" -Force
                }
                $null = $script:courses.Add($parsed)
            }
        }
    } catch {
        $script:courses = [System.Collections.ArrayList]@()
    }
}

$script:activeCourse = $null

function Save-Courses {
    $json = ConvertTo-Json @($script:courses) -Depth 4
    Set-Content -Path $coursesFile -Value $json -Encoding UTF8
}

function Get-CourseStudentsFilePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CourseId,
        [string]$CourseName = $null
    )
    if (-not $CourseName -and $script:courses) {
        foreach ($c in $script:courses) {
            if ([string]$c.Id -eq $CourseId) {
                $CourseName = $c.Name
                break
            }
        }
    }
    $cleanCourseName = if ($CourseName) { ($CourseName -replace '[\\/:*?"<>|]', '_').Trim() } else { $null }
    if (-not $cleanCourseName) { $cleanCourseName = $CourseId }

    $coursesParent = Join-Path $dataDir "Courses"
    $courseDir = Join-Path $coursesParent $cleanCourseName
    if (-not (Test-Path -LiteralPath $courseDir)) {
        $null = New-Item -ItemType Directory -Path $courseDir -Force
    }

    $modernPath = Join-Path $courseDir "students.json"

    # Backward compatibility: automatically migrate legacy data/students_<CourseId>.json if found
    $legacyPath = Join-Path $dataDir "students_$CourseId.json"
    if ((Test-Path -LiteralPath $legacyPath) -and (-not (Test-Path -LiteralPath $modernPath))) {
        Move-Item -LiteralPath $legacyPath -Destination $modernPath -Force
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
        [string]$CourseName = $null
    )
    $filePath = Get-CourseStudentsFilePath -CourseId $CourseId -CourseName $CourseName
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
        [switch]$Force
    )
    $filePath = Get-CourseStudentsFilePath -CourseId $CourseId -CourseName $CourseName
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
            Save-CourseStudents -CourseId $CourseId -Students $sheetResult.Students -ColumnMap $sheetResult.ColumnMap -CourseName $CourseName
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
        [string]$RegistrationSheet = $null
    )
    $store = Get-CourseStudentStore -CourseId $CourseId -RegistrationSheet $RegistrationSheet
    if ($store -and $store.Students) {
        return @($store.Students)
    }
    return @()
}

function New-CourseVerificationSheet {
    param(
        [Parameter(Mandatory = $true)]
        $Course
    )
    $regSheet = [string]$Course.RegistrationSheet
    if (-not $regSheet -or -not (Test-Path -LiteralPath $regSheet)) {
        throw "Registration sheet not found on disk: $regSheet"
    }

    # Determine target path: saved alongside the registration sheet
    $regDir = [System.IO.Path]::GetDirectoryName($regSheet)
    $cName = if ($Course.Name) { [string]$Course.Name } else { "Course" }
    $cleanName = ($cName -replace '[\\/:*?"<>|]', '_').Trim()
    $targetPath = Join-Path $regDir "${cleanName}_Verification_Sheet.xlsx"

    # Read rows from registration sheet via Import-StudentSheet
    $parsed = Import-StudentSheet -Path $regSheet
    if (-not $parsed.Success -or $parsed.Rows.Count -eq 0) {
        throw "Could not parse registration sheet: $($parsed.Error)"
    }

    # Detect registration column from ColumnMap
    $isRegHeader = if ($parsed.ColumnMap) { $parsed.ColumnMap.IsRegistered } else { $null }

    # Build verification rows (existing columns + 'Verification Status' + 'Verification Remarks')
    $verificationRows = [System.Collections.ArrayList]@()
    foreach ($row in $parsed.Rows) {
        $rowDict = [ordered]@{}
        foreach ($prop in $row.PSObject.Properties) {
            $rowDict[$prop.Name] = $prop.Value
        }
        $isRegVal = if ($isRegHeader -and $rowDict.Contains($isRegHeader)) { ConvertTo-BooleanValue $rowDict[$isRegHeader] } else { $null }
        if ($isRegVal -eq $false) {
            $rowDict['Verification Status'] = 'Did Not Register'
            $rowDict['Verification Remarks'] = 'Student opted out of exam'
        } else {
            $rowDict['Verification Status'] = 'Pending'
            $rowDict['Verification Remarks'] = 'Awaiting Verification'
        }
        $null = $verificationRows.Add([PSCustomObject]$rowDict)
    }

    # Export to Excel using Export-Excel (from ImportExcel module) or fallback to CSV
    $hasImportExcel = (Get-Module -Name ImportExcel -ListAvailable)
    if ($hasImportExcel) {
        Import-Module ImportExcel -ErrorAction SilentlyContinue
        $verificationRows | Export-Excel -Path $targetPath -WorksheetName "Verification" -AutoSize -BoldTopRow -FreezeTopRow -ClearSheet
    } else {
        $targetPath = [System.IO.Path]::ChangeExtension($targetPath, ".csv")
        $verificationRows | Export-Csv -Path $targetPath -NoTypeInformation -Encoding UTF8
    }

    # Update course record safely in PowerShell 5.1 / 7
    if ($Course.PSObject.Properties['VerificationSheet']) {
        $Course.VerificationSheet = $targetPath
    } else {
        $Course | Add-Member -NotePropertyName 'VerificationSheet' -NotePropertyValue $targetPath -Force
    }
    Save-Courses

    # Update students store with initial verification status
    $store = Get-CourseStudentStore -CourseId $Course.Id -RegistrationSheet $regSheet
    if ($store -and $store.Students) {
        foreach ($st in $store.Students) {
            if ($st.IsRegistered -eq $false) {
                if ($st.PSObject.Properties['VerificationStatus']) { $st.VerificationStatus = 'Did Not Register' } else { $st | Add-Member -NotePropertyName 'VerificationStatus' -NotePropertyValue 'Did Not Register' -Force }
                if ($st.PSObject.Properties['VerificationRemarks']) { $st.VerificationRemarks = 'Student opted out of exam' } else { $st | Add-Member -NotePropertyName 'VerificationRemarks' -NotePropertyValue 'Student opted out of exam' -Force }
            } else {
                if ($st.PSObject.Properties['VerificationStatus']) { $st.VerificationStatus = 'Pending' } else { $st | Add-Member -NotePropertyName 'VerificationStatus' -NotePropertyValue 'Pending' -Force }
                if ($st.PSObject.Properties['VerificationRemarks']) { $st.VerificationRemarks = 'Awaiting Verification' } else { $st | Add-Member -NotePropertyName 'VerificationRemarks' -NotePropertyValue 'Awaiting Verification' -Force }
            }
        }
        Save-CourseStudents -CourseId $Course.Id -Students $store.Students -ColumnMap $store.ColumnMap
    }

    return $targetPath
}

# 3. XAML Loader Helper
function Import-Xaml {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Error "XAML file not found at: $Path"
        return $null
    }
    $raw = Get-Content $Path -Raw -Encoding UTF8
    $raw = $raw -replace 'x:Class="[^"]*"', ''
    $raw = $raw -replace 'mc:Ignorable="[^"]*"', ''
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($raw))
    return [System.Windows.Markup.XamlReader]::Load($reader)
}

# 4. File Browse Helper (Native Windows OpenFileDialog)
function Show-ExcelBrowseDialog {
    param([string]$Title = "Select Spreadsheet")
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $Title
    $dialog.Filter = "Spreadsheets (*.xlsx;*.xls;*.csv)|*.xlsx;*.xls;*.csv|All Files (*.*)|*.*"
    $dialog.InitialDirectory = [System.Environment]::GetFolderPath("MyDocuments")
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

# 5. Initialize WPF Application and Load Theme Tokens
if (-not [System.Windows.Application]::Current) {
    $null = New-Object System.Windows.Application
}

$themePath = Join-Path $appRoot "UI\Styles\Theme.xaml"
$themeDict = Import-Xaml $themePath
if ($themeDict) {
    [System.Windows.Application]::Current.Resources.MergedDictionaries.Add($themeDict)
}

# 6. Load Main Window Shell
$mainWindowPath = Join-Path $appRoot "UI\MainWindow.xaml"
$window = Import-Xaml $mainWindowPath

if (-not $window) {
    Write-Error "Failed to load MainWindow.xaml"
    exit
}

# 7. Extract Shell Navigation Elements
$ViewContainer = $window.FindName("ViewContainer")
$NavBtnHome = $window.FindName("NavBtnHome")
$NavBtnCourses = $window.FindName("NavBtnCourses")
$NavBtnSettings = $window.FindName("NavBtnSettings")
$BtnHeaderSync = $window.FindName("BtnHeaderSync")
$TxtStatusBadge = $window.FindName("TxtStatusBadge")
$StatusDot = $window.FindName("StatusDot")

# 8. View Caching & Navigation Router
$script:views = @{}
$script:currentView = ""

function Get-OrCreateView {
    param([string]$ViewName)
    if ($script:views.ContainsKey($ViewName)) {
        return $script:views[$ViewName]
    }
    $path = Join-Path $appRoot "UI\Views\$ViewName.xaml"
    $view = Import-Xaml $path
    $script:views[$ViewName] = $view
    Wire-ViewEvents $ViewName $view
    return $view
}

function Remove-Course {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CourseId
    )

    $target = $null
    foreach ($c in $script:courses) {
        if ([string]$c.Id -eq $CourseId) {
            $target = $c
            break
        }
    }

    if (-not $target) { return }

    $cName = if ($target.Name) { [string]$target.Name } else { "this course" }

    $confirm = [System.Windows.MessageBox]::Show(
        "Are you sure you want to delete '$cName'?`n`nThis will remove the course and its cached student records from the app. Your original Excel spreadsheet on disk will not be deleted.",
        "Confirm Delete Course",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) {
        return
    }

    # 1. Remove from active courses collection & persist to JSON
    $script:courses = @($script:courses | Where-Object { [string]$_.Id -ne $CourseId })
    Save-Courses

    # 2. If deleted course was currently active, reset activeCourse and header
    if ($script:activeCourse -and [string]$script:activeCourse.Id -eq $CourseId) {
        $script:activeCourse = $null
        if ($TxtStatusBadge) {
            $TxtStatusBadge.Text = "No Course Active"
            $TxtStatusBadge.Foreground = [System.Windows.Application]::Current.FindResource("MutedBrush")
        }
        if ($StatusDot) {
            $StatusDot.Fill = [System.Windows.Application]::Current.FindResource("MutedBrush")
        }
    }

    # 3. Clean up cached data directory for this course
    try {
        $cleanName = ($cName -replace '[\\/:*?"<>|]', '_').Trim()
        $courseDir = Join-Path $appRoot "data\Courses\$cleanName"
        if (Test-Path -LiteralPath $courseDir) {
            Remove-Item -LiteralPath $courseDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        $legacyJson = Join-Path $appRoot "data\students_$CourseId.json"
        if (Test-Path -LiteralPath $legacyJson) {
            Remove-Item -LiteralPath $legacyJson -Force -ErrorAction SilentlyContinue
        }
    } catch {
        # Ignore file locks
    }

    # 4. Refresh course cards list
    Refresh-CourseLists

    # 5. If currently viewing workspace or child view of deleted course, navigate to CoursesView
    if ($script:currentView -in @("WorkspaceView", "Stage1View", "Stage2View", "ReviewView")) {
        Navigate-To "CoursesView"
    }

    [System.Windows.MessageBox]::Show(
        "Course '$cName' has been deleted successfully.",
        "Course Deleted",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    )
}

# 9. Dynamic UI Card Builder for Courses
function Build-CourseCard {
    param($Course, [switch]$Detailed)

    $cardBorder = New-Object System.Windows.Controls.Border
    $cardBorder.Background = [System.Windows.Application]::Current.FindResource("Panel2Brush")
    $cardBorder.BorderBrush = [System.Windows.Application]::Current.FindResource("BorderBrush")
    $cardBorder.BorderThickness = New-Object System.Windows.Thickness(1)
    $cardBorder.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $cardBorder.Padding = New-Object System.Windows.Thickness(16)
    $cardBorder.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)

    $stack = New-Object System.Windows.Controls.StackPanel

    # Title Row
    $titleGrid = New-Object System.Windows.Controls.Grid
    $titleGrid.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)

    $txtTitle = New-Object System.Windows.Controls.TextBlock
    $txtTitle.Text = $Course.Name
    $txtTitle.FontSize = 15
    $txtTitle.FontWeight = [System.Windows.FontWeights]::SemiBold
    $txtTitle.Foreground = [System.Windows.Application]::Current.FindResource("TextBrush")

    $badgeBorder = New-Object System.Windows.Controls.Border
    $badgeBorder.Background = [System.Windows.Application]::Current.FindResource("PanelBrush")
    $badgeBorder.BorderBrush = [System.Windows.Application]::Current.FindResource("BorderBrush")
    $badgeBorder.BorderThickness = New-Object System.Windows.Thickness(1)
    $badgeBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
    $badgeBorder.Padding = New-Object System.Windows.Thickness(6, 2, 6, 2)
    $badgeBorder.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right

    $badgeText = New-Object System.Windows.Controls.TextBlock
    $badgeText.Text = if ($Course.Code) { $Course.Code } else { "NPTEL" }
    $badgeText.FontFamily = New-Object System.Windows.Media.FontFamily("IBM Plex Mono, Consolas")
    $badgeText.FontSize = 10
    $badgeText.Foreground = [System.Windows.Application]::Current.FindResource("AccentBrush")
    $badgeBorder.Child = $badgeText

    $null = $titleGrid.Children.Add($txtTitle)
    $null = $titleGrid.Children.Add($badgeBorder)
    $null = $stack.Children.Add($titleGrid)

    # Subtitle / Department & Semester
    $metaText = New-Object System.Windows.Controls.TextBlock
    $dept = if ($Course.Department) { $Course.Department } else { "Department" }
    $sem = if ($Course.Semester) { $Course.Semester } else { "Active Term" }
    $metaText.Text = "$dept - $sem"
    $metaText.FontSize = 11
    $metaText.Foreground = [System.Windows.Application]::Current.FindResource("MutedBrush")
    $metaText.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
    $null = $stack.Children.Add($metaText)

    # Action Row
    $actionGrid = New-Object System.Windows.Controls.Grid

    # Delete Course Button (Left)
    $btnDelete = New-Object System.Windows.Controls.Button
    $btnDelete.Content = "Delete Course"
    $btnDelete.Style = [System.Windows.Application]::Current.FindResource("BtnSecondary")
    $btnDelete.Foreground = [System.Windows.Application]::Current.FindResource("DangerBrush")
    $btnDelete.Padding = New-Object System.Windows.Thickness(12, 6, 12, 6)
    $btnDelete.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    $btnDelete.Tag = [string]$Course.Id

    $btnDelete.Add_Click({
        $id = [string]$this.Tag
        Remove-Course -CourseId $id
    })

    # Open Workspace Button (Right)
    $btnOpen = New-Object System.Windows.Controls.Button
    $btnOpen.Content = "Open Workspace ->"
    $btnOpen.Style = [System.Windows.Application]::Current.FindResource("BtnSecondary")
    $btnOpen.Padding = New-Object System.Windows.Thickness(12, 6, 12, 6)
    $btnOpen.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $btnOpen.Tag = [string]$Course.Id

    $btnOpen.Add_Click({
        $id = [string]$this.Tag
        $found = $null
        foreach ($c in $script:courses) {
            if ([string]$c.Id -eq $id) {
                $found = $c
                break
            }
        }
        if ($found) {
            Select-Course $found
        }
    })

    $null = $actionGrid.Children.Add($btnDelete)
    $null = $actionGrid.Children.Add($btnOpen)
    $null = $stack.Children.Add($actionGrid)

    $cardBorder.Child = $stack
    return $cardBorder
}

function Refresh-CourseLists {
    $coursesView = $script:views["CoursesView"]

    if ($coursesView) {
        $gridHost = $coursesView.FindName("CoursesGridHost")
        $emptyState = $coursesView.FindName("CoursesEmptyState")

        if ($gridHost) {
            $gridHost.Children.Clear()
            if ($script:courses.Count -gt 0) {
                if ($emptyState) { $emptyState.Visibility = [System.Windows.Visibility]::Collapsed }
                foreach ($c in $script:courses) {
                    $card = Build-CourseCard -Course $c -Detailed
                    $null = $gridHost.Children.Add($card)
                }
            } else {
                if ($emptyState) { $emptyState.Visibility = [System.Windows.Visibility]::Visible }
            }
        }
    }
}

function Select-Course {
    param(
        $Course,
        [string]$TargetView = $null
    )
    if (-not $Course) { return }
    $script:activeCourse = $Course

    $cName = if ($Course.Name) { [string]$Course.Name } else { "Untitled Course" }
    $cCode = if ($Course.Code) { [string]$Course.Code } else { "" }
    $cDept = if ($Course.Department) { [string]$Course.Department } else { "" }
    $cSem = if ($Course.Semester) { [string]$Course.Semester } else { "" }

    # Update shell header status
    if ($TxtStatusBadge) {
        $codeBadge = if ($cCode) { " ($cCode)" } else { "" }
        $TxtStatusBadge.Text = "$cName$codeBadge"
        $TxtStatusBadge.Foreground = [System.Windows.Application]::Current.FindResource("TextBrush")
    }
    if ($StatusDot) {
        $StatusDot.Fill = [System.Windows.Application]::Current.FindResource("SageBrush")
    }

    # 1. Retrieve Course Student Store & Metrics
    $store = Get-CourseStudentStore -CourseId $Course.Id -RegistrationSheet $Course.RegistrationSheet
    $students = @($store.Students)
    $colMap = $store.ColumnMap

    $totalCount = $students.Count
    $regCount = @($students | Where-Object { $_.IsRegistered -eq $true }).Count
    $actionCount = @($students | Where-Object { $_.IsRegistered -eq $false }).Count

    # Compute verification status metrics
    $verifiedCount = 0
    $reviewCount = 0
    $unregCount = 0

    foreach ($st in $students) {
        $vStatus = if ($st.PSObject.Properties['VerificationStatus']) { [string]$st.VerificationStatus } else { "" }
        $isReg = if ($st.PSObject.Properties['IsRegistered']) { $st.IsRegistered } else { $null }

        if ($vStatus -eq "Verified") {
            $verifiedCount++
        } elseif ($vStatus -eq "Under Review") {
            $reviewCount++
        } elseif ($vStatus -eq "Did Not Register" -or $isReg -eq $false) {
            $unregCount++
        }
    }

    $vSheetPath = if ($Course.PSObject.Properties['VerificationSheet']) { [string]$Course.VerificationSheet } else { $null }
    $vSheetExists = $vSheetPath -and (Test-Path -LiteralPath $vSheetPath)

    $sageBrush = [System.Windows.Application]::Current.FindResource("SageBrush")
    $accentBrush = [System.Windows.Application]::Current.FindResource("AccentBrush")
    $mutedBrush = [System.Windows.Application]::Current.FindResource("MutedBrush")
    $textBrush = [System.Windows.Application]::Current.FindResource("TextBrush")
    $borderBrush = [System.Windows.Application]::Current.FindResource("BorderBrush")

    # ── Update Workspace View (Overview) ──
    $wsView = Get-OrCreateView "WorkspaceView"
    if ($wsView) {
        $breadcrumb = $wsView.FindName("TxtBreadcrumbCourse")
        $title = $wsView.FindName("TxtCourseDashboardTitle")
        $subtitle = $wsView.FindName("TxtCourseDashboardSubtitle")
        $statResults = $wsView.FindName("TxtStatExamResults")

        if ($breadcrumb) {
            $codeStr = if ($cCode) { " ($cCode)" } else { "" }
            $upperName = $cName.ToUpper()
            $breadcrumb.Text = "COURSES > $upperName$codeStr"
        }
        if ($title) {
            $title.Text = "$cName " + [char]0x2014 + " Workspace"
        }
        if ($subtitle) {
            $deptStr = if ($cDept) { "$cDept - " } else { "" }
            $semStr = if ($cSem) { "$cSem" } else { "" }
            $subtitle.Text = "$deptStr$semStr"
        }
        if ($statResults) {
            if ($Course.ExamResultsSheet) {
                $statResults.Text = "Uploaded"
                $statResults.Foreground = $sageBrush
            } else {
                $statResults.Text = "Pending"
                $statResults.Foreground = $mutedBrush
            }
        }

        # Bind Top Metric Cards
        $statEnrolled = $wsView.FindName("TxtStatEnrolled")
        if ($statEnrolled) { $statEnrolled.Text = [string]$totalCount }

        $statExamReg = $wsView.FindName("TxtStatExamRegistered")
        if ($statExamReg) { $statExamReg.Text = [string]$regCount }

        $statAction = $wsView.FindName("TxtStatActionNeeded")
        if ($statAction) { $statAction.Text = [string]$actionCount }

        # Stage 1 Status Badge
        $txtStage1Status = $wsView.FindName("TxtStage1Status")
        $badgeStage1 = $wsView.FindName("BadgeStage1Status")
        if ($txtStage1Status) {
            if ($regCount -gt 0 -and $verifiedCount -eq $regCount) {
                $txtStage1Status.Text = "Complete " + [char]0x2713
                $txtStage1Status.Foreground = $sageBrush
                if ($badgeStage1) { $badgeStage1.BorderBrush = $sageBrush }
            } else {
                $txtStage1Status.Text = "In Progress"
                $txtStage1Status.Foreground = $accentBrush
                if ($badgeStage1) { $badgeStage1.BorderBrush = $accentBrush }
            }
        }

        # Stage 2 Status Badge
        $txtStage2Status = $wsView.FindName("TxtStage2Status")
        $badgeStage2 = $wsView.FindName("BadgeStage2Status")
        if ($txtStage2Status) {
            if ($Course.ExamResultsSheet) {
                $txtStage2Status.Text = "Complete " + [char]0x2713
                $txtStage2Status.Foreground = $sageBrush
                if ($badgeStage2) { $badgeStage2.BorderBrush = $sageBrush }
            } else {
                $txtStage2Status.Text = "Pending"
                $txtStage2Status.Foreground = $mutedBrush
                if ($badgeStage2) { $badgeStage2.BorderBrush = $borderBrush }
            }
        }
    }

    # ── Update Stage 1 View (Registration & Verification) ──
    $s1View = Get-OrCreateView "Stage1View"
    if ($s1View) {
        # Breadcrumb
        $s1Breadcrumb = $s1View.FindName("TxtStage1Breadcrumb")
        if ($s1Breadcrumb) {
            $codeStr = if ($cCode) { " ($cCode)" } else { "" }
            $upperName = $cName.ToUpper()
            $s1Breadcrumb.Text = "COURSES > $upperName$codeStr > STAGE 1"
        }

        # Registration Sheet Path
        $sheetPathLabel = $s1View.FindName("TxtDashboardSheetPath")
        if ($sheetPathLabel) {
            $sheetPathLabel.Text = if ($Course.RegistrationSheet) { [string]$Course.RegistrationSheet } else { "No registration sheet linked." }
        }

        # Bind Registration Sheet Health Basic Metrics Strip
        $hTotal = $s1View.FindName("TxtHealthTotalStudents")
        $hExamReg = $s1View.FindName("TxtHealthExamRegistered")
        $hOther = $s1View.FindName("TxtHealthOtherStudents")
        if ($hTotal) { $hTotal.Text = [string]$totalCount }
        if ($hExamReg) { $hExamReg.Text = [string]$regCount }
        if ($hOther) { $hOther.Text = [string]$actionCount }

        # Update Registration Sheet Health Column Badges
        $colKeys = @(
            @{ Key = 'RollNo';       Label = 'Roll No';           Card = 'CardColRollNo';       Icon = 'IconColRollNo';       Txt = 'TxtColRollNo' },
            @{ Key = 'Name';         Label = 'Name';              Card = 'CardColName';         Icon = 'IconColName';         Txt = 'TxtColName' },
            @{ Key = 'Email';        Label = 'Email';             Card = 'CardColEmail';        Icon = 'IconColEmail';        Txt = 'TxtColEmail' },
            @{ Key = 'Subject';      Label = 'Subject';           Card = 'CardColSubject';      Icon = 'IconColSubject';      Txt = 'TxtColSubject' },
            @{ Key = 'IsEnrolled';   Label = 'Enrolled';          Card = 'CardColIsEnrolled';   Icon = 'IconColIsEnrolled';   Txt = 'TxtColIsEnrolled' },
            @{ Key = 'IsRegistered'; Label = 'Exam Registered';   Card = 'CardColIsRegistered'; Icon = 'IconColIsRegistered'; Txt = 'TxtColIsRegistered' },
            @{ Key = 'ProofUrl';     Label = 'Proof Receipt';     Card = 'CardColProofUrl';     Icon = 'IconColProofUrl';     Txt = 'TxtColProofUrl' }
        )

        $missingCols = @()
        foreach ($item in $colKeys) {
            $mappedHeader = $null
            if ($colMap) {
                if ($colMap -is [System.Collections.IDictionary] -and $colMap.Contains($item.Key)) {
                    $mappedHeader = $colMap[$item.Key]
                } elseif ($colMap.PSObject -and $colMap.PSObject.Properties[$item.Key]) {
                    $mappedHeader = $colMap.PSObject.Properties[$item.Key].Value
                }
            }

            $cCard = $s1View.FindName($item.Card)
            $cIcon = $s1View.FindName($item.Icon)
            $cTxt = $s1View.FindName($item.Txt)

            if ($mappedHeader) {
                if ($cIcon) { $cIcon.Text = [string][char]0x2713; $cIcon.Foreground = $sageBrush }
                if ($cTxt) { $cTxt.Text = [string]$mappedHeader; $cTxt.Foreground = $textBrush }
                if ($cCard) { $cCard.BorderBrush = $borderBrush }
            } else {
                if ($cIcon) { $cIcon.Text = [string][char]0x26A0; $cIcon.Foreground = $accentBrush }
                if ($cTxt) { $cTxt.Text = "MISSING"; $cTxt.Foreground = $accentBrush }
                if ($cCard) { $cCard.BorderBrush = $accentBrush }
                $missingCols += $item.Label
            }
        }

        # Overall Health & Missing Column Warning Banner
        $panelWarn = $s1View.FindName("PanelColumnWarning")
        $txtWarnMsg = $s1View.FindName("TxtColumnWarningMessage")
        $badgeHealth = $s1View.FindName("BadgeOverallHealth")
        $txtHealth = $s1View.FindName("TxtOverallHealth")

        if ($missingCols.Count -gt 0) {
            if ($panelWarn) { $panelWarn.Visibility = [System.Windows.Visibility]::Visible }
            if ($txtWarnMsg) {
                if ('Exam Registered' -in $missingCols) {
                    $txtWarnMsg.Text = "The 'Exam Registration' column was not found in this spreadsheet."
                } else {
                    $txtWarnMsg.Text = "The following expected column(s) were not found in this spreadsheet: $($missingCols -join ', ')."
                }
            }
            if ($txtHealth) { $txtHealth.Text = "$($missingCols.Count) Column(s) Missing " + [char]0x26A0; $txtHealth.Foreground = $accentBrush }
            if ($badgeHealth) { $badgeHealth.BorderBrush = $accentBrush }
        } else {
            if ($panelWarn) { $panelWarn.Visibility = [System.Windows.Visibility]::Collapsed }
            if ($txtHealth) { $txtHealth.Text = "7/7 Columns Detected " + [char]0x2713; $txtHealth.Foreground = $sageBrush }
            if ($badgeHealth) { $badgeHealth.BorderBrush = $sageBrush }
        }

        # Summary Text
        $txtSummary = $s1View.FindName("TxtSheetAuditSummary")
        if ($txtSummary) {
            $detectedCount = 7 - $missingCols.Count
            $txtSummary.Text = "$totalCount Total Students | $detectedCount/7 Standard Columns Detected"
        }
        $txtSyncTime = $s1View.FindName("TxtSheetAuditTimestamp")
        if ($txtSyncTime) {
            $syncDate = if ($store.LastSync) { [string]$store.LastSync } else { (Get-Date).ToString("yyyy-MM-dd HH:mm") }
            $txtSyncTime.Text = "Synced: $syncDate"
        }

        # Verification Sheet Panel State & Mini Dashboard Metrics
        $panelPrompt = $s1View.FindName("PanelVerificationSheetPrompt")
        $panelActive = $s1View.FindName("PanelVerificationSheetActive")
        $badgeVerSheet = $s1View.FindName("BadgeVerificationSheetStatus")
        $txtVerPath = $s1View.FindName("TxtVerificationSheetPath")
        $txtVerSummary = $s1View.FindName("TxtVerificationSheetSummary")
        $txtVerTime = $s1View.FindName("TxtVerificationSheetTimestamp")

        $txtVerStatVerified = $s1View.FindName("TxtVerStatVerified")
        $txtVerStatReview   = $s1View.FindName("TxtVerStatReview")
        $txtVerStatUnreg    = $s1View.FindName("TxtVerStatUnreg")

        if ($txtVerStatVerified) { $txtVerStatVerified.Text = $verifiedCount.ToString() }
        if ($txtVerStatReview)   { $txtVerStatReview.Text = $reviewCount.ToString() }
        if ($txtVerStatUnreg)    { $txtVerStatUnreg.Text = $unregCount.ToString() }

        if ($vSheetExists) {
            if ($panelPrompt) { $panelPrompt.Visibility = [System.Windows.Visibility]::Collapsed }
            if ($panelActive) { $panelActive.Visibility = [System.Windows.Visibility]::Visible }
            if ($badgeVerSheet) { $badgeVerSheet.Visibility = [System.Windows.Visibility]::Visible }
            if ($txtVerPath) { $txtVerPath.Text = $vSheetPath }
            if ($txtVerSummary) {
                $txtVerSummary.Text = "$totalCount Students | $verifiedCount Verified, $reviewCount Under Review, $unregCount Did Not Register"
            }
            if ($txtVerTime) {
                $fileItem = Get-Item -LiteralPath $vSheetPath -ErrorAction SilentlyContinue
                $modTime = if ($fileItem) { $fileItem.LastWriteTime.ToString("yyyy-MM-dd HH:mm") } else { "" }
                $txtVerTime.Text = "Updated: $modTime"
            }
        } else {
            if ($panelPrompt) { $panelPrompt.Visibility = [System.Windows.Visibility]::Visible }
            if ($panelActive) { $panelActive.Visibility = [System.Windows.Visibility]::Collapsed }
            if ($badgeVerSheet) { $badgeVerSheet.Visibility = [System.Windows.Visibility]::Collapsed }
        }
    }

    # ── Update Stage 2 View (Exam Results) ──
    $s2View = Get-OrCreateView "Stage2View"
    if ($s2View) {
        $s2Breadcrumb = $s2View.FindName("TxtStage2Breadcrumb")
        if ($s2Breadcrumb) {
            $codeStr = if ($cCode) { " ($cCode)" } else { "" }
            $upperName = $cName.ToUpper()
            $s2Breadcrumb.Text = "COURSES > $upperName$codeStr > STAGE 2"
        }

        $panelResultsActive = $s2View.FindName("PanelExamResultsActive")
        $txtResultsPath = $s2View.FindName("TxtExamResultsPath")
        if ($Course.ExamResultsSheet -and (Test-Path -LiteralPath $Course.ExamResultsSheet -ErrorAction SilentlyContinue)) {
            if ($panelResultsActive) { $panelResultsActive.Visibility = [System.Windows.Visibility]::Visible }
            if ($txtResultsPath) { $txtResultsPath.Text = [string]$Course.ExamResultsSheet }
        } else {
            if ($panelResultsActive) { $panelResultsActive.Visibility = [System.Windows.Visibility]::Collapsed }
        }
    }

    # ── Update Review View (if initialized) ──
    if ($script:views.ContainsKey("ReviewView")) {
        Update-ReviewView -Course $Course -Students $students
    }

    if ($TargetView) {
        Navigate-To $TargetView
    } elseif ($script:currentView -eq "Stage1View" -or $script:currentView -eq "Stage2View" -or $script:currentView -eq "ReviewView") {
        # Already inside the Stage detail view or Review queue; keep user on the active view
    } else {
        Navigate-To "WorkspaceView"
    }
}

function Update-ReviewView {
    param(
        $Course,
        $Students = $null
    )
    if (-not $Course) { return }
    $rv = Get-OrCreateView "ReviewView"
    if (-not $rv) { return }

    if (-not $Students) {
        $store = Get-CourseStudentStore -CourseId $Course.Id -RegistrationSheet $Course.RegistrationSheet
        $Students = @($store.Students)
    }

    $cName = if ($Course.Name) { [string]$Course.Name } else { "Untitled Course" }
    $cCode = if ($Course.Code) { [string]$Course.Code } else { "" }

    # 1. Breadcrumb
    $txtBreadcrumb = $rv.FindName("TxtReviewBreadcrumb")
    if ($txtBreadcrumb) {
        $codeStr = if ($cCode) { " ($cCode)" } else { "" }
        $upperName = $cName.ToUpper()
        $dash = [char]0x2014
        $txtBreadcrumb.Text = "COURSES > $upperName$codeStr > STAGE 1 $dash REVIEW QUEUE"
    }

    # 2. Filter students under review
    $reviewStudents = @($Students | Where-Object { $_.VerificationStatus -eq "Under Review" })
    $revCount = $reviewStudents.Count

    # 3. Count badge
    $txtBadge = $rv.FindName("TxtReviewCountBadge")
    if ($txtBadge) {
        $plural = if ($revCount -eq 1) { "Student Needs Review" } else { "Students Need Review" }
        $txtBadge.Text = "$revCount $plural"
        if ($revCount -gt 0) {
            $txtBadge.Foreground = [System.Windows.Application]::Current.FindResource("AccentBrush")
        } else {
            $txtBadge.Foreground = [System.Windows.Application]::Current.FindResource("MutedBrush")
        }
    }

    # 4. Review items list host
    $hostPanel = $rv.FindName("ReviewItemsListHost")
    $emptyNotice = $rv.FindName("ReviewEmptyStateNotice")

    if ($hostPanel) {
        $hostPanel.Children.Clear()

        if ($revCount -gt 0) {
            if ($emptyNotice) { $emptyNotice.Visibility = [System.Windows.Visibility]::Collapsed }

            foreach ($st in $reviewStudents) {
                $cardBorder = New-Object System.Windows.Controls.Border
                $cardBorder.Background = [System.Windows.Application]::Current.FindResource("Panel2Brush")
                $cardBorder.BorderBrush = [System.Windows.Application]::Current.FindResource("BorderBrush")
                $cardBorder.BorderThickness = New-Object System.Windows.Thickness(1)
                $cardBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
                $cardBorder.Padding = New-Object System.Windows.Thickness(12, 10, 12, 10)
                $cardBorder.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
                $cardBorder.Cursor = [System.Windows.Input.Cursors]::Hand
                $cardBorder.Tag = $st

                $stack = New-Object System.Windows.Controls.StackPanel

                # Top row: Roll Number and Review badge
                $topGrid = New-Object System.Windows.Controls.Grid
                $col1 = New-Object System.Windows.Controls.ColumnDefinition
                $col1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                $col2 = New-Object System.Windows.Controls.ColumnDefinition
                $col2.Width = [System.Windows.GridLength]::Auto
                $null = $topGrid.ColumnDefinitions.Add($col1)
                $null = $topGrid.ColumnDefinitions.Add($col2)

                $txtRoll = New-Object System.Windows.Controls.TextBlock
                $txtRoll.Text = if ($st.RollNo) { [string]$st.RollNo } else { "No Roll No" }
                $txtRoll.FontFamily = New-Object System.Windows.Media.FontFamily("IBM Plex Mono, Consolas")
                $txtRoll.FontSize = 12
                $txtRoll.FontWeight = [System.Windows.FontWeights]::SemiBold
                $txtRoll.Foreground = [System.Windows.Application]::Current.FindResource("TextBrush")
                [System.Windows.Controls.Grid]::SetColumn($txtRoll, 0)
                $null = $topGrid.Children.Add($txtRoll)

                $badge = New-Object System.Windows.Controls.Border
                $badge.Background = [System.Windows.Application]::Current.FindResource("AccentTintBrush")
                $badge.BorderBrush = [System.Windows.Application]::Current.FindResource("AccentBrush")
                $badge.BorderThickness = New-Object System.Windows.Thickness(1)
                $badge.CornerRadius = New-Object System.Windows.CornerRadius(4)
                $badge.Padding = New-Object System.Windows.Thickness(6, 2, 6, 2)

                $badgeTxt = New-Object System.Windows.Controls.TextBlock
                $badgeTxt.Text = "Review"
                $badgeTxt.FontFamily = New-Object System.Windows.Media.FontFamily("IBM Plex Mono, Consolas")
                $badgeTxt.FontSize = 9
                $badgeTxt.FontWeight = [System.Windows.FontWeights]::Bold
                $badgeTxt.Foreground = [System.Windows.Application]::Current.FindResource("AccentBrush")
                $badge.Child = $badgeTxt
                [System.Windows.Controls.Grid]::SetColumn($badge, 1)
                $null = $topGrid.Children.Add($badge)

                $null = $stack.Children.Add($topGrid)

                # Student Name
                $txtName = New-Object System.Windows.Controls.TextBlock
                $txtName.Text = if ($st.Name) { [string]$st.Name } else { "Unnamed Student" }
                $txtName.FontSize = 12
                $txtName.Foreground = [System.Windows.Application]::Current.FindResource("TextBrush")
                $txtName.Margin = New-Object System.Windows.Thickness(0, 4, 0, 2)
                $null = $stack.Children.Add($txtName)

                # Remarks preview
                if ($st.VerificationRemarks) {
                    $txtRemarks = New-Object System.Windows.Controls.TextBlock
                    $remStr = [string]$st.VerificationRemarks
                    if ($remStr.Length -gt 46) { $remStr = $remStr.Substring(0, 43) + "..." }
                    $txtRemarks.Text = $remStr
                    $txtRemarks.FontSize = 10
                    $txtRemarks.Foreground = [System.Windows.Application]::Current.FindResource("MutedBrush")
                    $txtRemarks.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
                    $null = $stack.Children.Add($txtRemarks)
                }

                $cardBorder.Child = $stack

                # Wire card click to Show-StudentReviewDetails
                $cardBorder.Add_MouseLeftButtonUp({
                    Show-StudentReviewDetails -Student $this.Tag -CardElement $this
                })

                $null = $hostPanel.Children.Add($cardBorder)
            }

            # Automatically select the first student in the queue
            if ($hostPanel.Children.Count -gt 0) {
                $firstCard = $hostPanel.Children[0]
                Show-StudentReviewDetails -Student $firstCard.Tag -CardElement $firstCard
            }
        } else {
            if ($emptyNotice) { $emptyNotice.Visibility = [System.Windows.Visibility]::Visible }
            $placeholder = $rv.FindName("ReviewDetailsPlaceholder")
            $workspace = $rv.FindName("ReviewWorkspaceGrid")
            if ($placeholder) { $placeholder.Visibility = [System.Windows.Visibility]::Visible }
            if ($workspace) { $workspace.Visibility = [System.Windows.Visibility]::Collapsed }
        }
    }
}

function Show-StudentReviewDetails {
    param(
        $Student,
        $CardElement = $null
    )
    if (-not $Student) { return }
    $rv = Get-OrCreateView "ReviewView"
    if (-not $rv) { return }

    # 1. Highlight selected card in queue
    if ($CardElement) {
        $parent = $CardElement.Parent
        if ($parent) {
            foreach ($sibling in $parent.Children) {
                $sibling.BorderBrush = [System.Windows.Application]::Current.FindResource("BorderBrush")
                $sibling.Background = [System.Windows.Application]::Current.FindResource("Panel2Brush")
            }
        }
        $CardElement.BorderBrush = [System.Windows.Application]::Current.FindResource("AccentBrush")
        $CardElement.Background = [System.Windows.Application]::Current.FindResource("PanelModBrush")
    }

    # 2. Toggle View State
    $placeholder = $rv.FindName("ReviewDetailsPlaceholder")
    $workspace = $rv.FindName("ReviewWorkspaceGrid")
    if ($placeholder) { $placeholder.Visibility = [System.Windows.Visibility]::Collapsed }
    if ($workspace) { $workspace.Visibility = [System.Windows.Visibility]::Visible }

    # 3. Populate Header & Identity
    $txtName = $rv.FindName("TxtReviewStudentName")
    $txtRoll = $rv.FindName("TxtReviewStudentRoll")
    $txtStatus = $rv.FindName("TxtReviewStatus")

    if ($txtName) { $txtName.Text = if ($Student.Name) { [string]$Student.Name } else { "Unnamed Student" } }
    if ($txtRoll) { $txtRoll.Text = if ($Student.RollNo) { "Roll No: $($Student.RollNo)" } else { "Roll No: Not Assigned" } }
    if ($txtStatus) {
        $stVal = if ($Student.VerificationStatus) { [string]$Student.VerificationStatus } else { "UNDER REVIEW" }
        $txtStatus.Text = $stVal.ToUpper()
    }

    # 4. Populate Diagnostics
    $txtRemarks = $rv.FindName("TxtReviewRemarks")
    if ($txtRemarks) {
        $rem = if ($Student.VerificationRemarks) { [string]$Student.VerificationRemarks } else { "Submission flagged during verification rules check. Please inspect the attached receipt against the student details." }
        $txtRemarks.Text = $rem
    }

    # 5. Populate Registration Record
    $txtEmail = $rv.FindName("TxtReviewEmail")
    $txtSubj = $rv.FindName("TxtReviewSubject")
    $txtIsReg = $rv.FindName("TxtReviewIsRegistered")
    $txtTime = $rv.FindName("TxtReviewTimestamp")
    $txtProof = $rv.FindName("TxtReviewProofUrl")
    $btnDrive = $rv.FindName("BtnOpenDriveLink")

    $dash = [char]0x2014
    if ($txtEmail) { $txtEmail.Text = if ($Student.Email) { [string]$Student.Email } else { "$dash" } }
    if ($txtSubj)  { $txtSubj.Text = if ($Student.Subject) { [string]$Student.Subject } else { "$dash" } }
    if ($txtIsReg) { $txtIsReg.Text = if ($Student.IsRegistered) { "Yes" } else { "No" } }
    if ($txtTime)  { $txtTime.Text = if ($Student.Timestamp) { [string]$Student.Timestamp } else { "$dash" } }
    if ($txtProof) { $txtProof.Text = if ($Student.ProofUrl) { [string]$Student.ProofUrl } else { "No link provided" } }
    if ($btnDrive) {
        $btnDrive.Tag = if ($Student.ProofUrl) { [string]$Student.ProofUrl } else { "" }
        $btnDrive.IsEnabled = [bool]$Student.ProofUrl
    }

    # Store currently selected student on the workspace
    $workspace.Tag = $Student

    # 6. Load & Display Receipt Image
    $imgReceipt = $rv.FindName("ReceiptImage")
    $scrollViewer = $rv.FindName("ReceiptScrollViewer")
    $missingPanel = $rv.FindName("ReceiptMissingPlaceholder")
    $txtBadge = $rv.FindName("TxtReceiptStatusBadge")
    $btnOpenFile = $rv.FindName("BtnOpenReceiptFile")
    $btnDownload = $rv.FindName("BtnDownloadMissingReceipt")
    $zoomScale = $rv.FindName("ReceiptZoomScale")
    $txtZoom = $rv.FindName("TxtZoomLevel")

    if ($btnDownload) { $btnDownload.Tag = $Student }

    # Reset Zoom
    if ($zoomScale) {
        $zoomScale.ScaleX = 1.0
        $zoomScale.ScaleY = 1.0
    }
    if ($txtZoom) { $txtZoom.Text = "100%" }

    # Find receipt on disk
    $receiptFound = $false
    $receiptPath = $null
    $displayImgPath = $null

    if ($script:activeCourse -and $Student.RollNo) {
        $cName = if ($script:activeCourse.Name) { [string]$script:activeCourse.Name } else { "Default" }
        $cleanCName = ($cName -replace '[\\/:*?"<>|]', '_').Trim()
        $receiptsDir = Join-Path $appRoot "data\Courses\$cleanCName\receipts"

        $cleanRoll = (($Student.RollNo) -replace '[\\/:*?"<>|]', '_').Trim()
        if (Test-Path -LiteralPath $receiptsDir) {
            $matchedFile = Get-ChildItem -LiteralPath $receiptsDir -Filter "${cleanRoll}_receipt.*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($matchedFile) {
                $receiptFound = $true
                $receiptPath = $matchedFile.FullName

                $ext = $matchedFile.Extension.ToLower()
                if ($ext -eq ".pdf") {
                    try {
                        $displayImgPath = ConvertTo-ReceiptImage -FilePath $receiptPath
                    } catch {
                        $displayImgPath = $null
                    }
                } elseif ($ext -in @('.png', '.jpg', '.jpeg', '.bmp', '.webp')) {
                    $displayImgPath = $receiptPath
                }
            }
        }
    }

    if ($receiptFound -and $displayImgPath -and (Test-Path -LiteralPath $displayImgPath)) {
        try {
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit()
            $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.UriSource = New-Object System.Uri($displayImgPath, [System.UriKind]::Absolute)
            $bmp.EndInit()
            $bmp.Freeze()

            if ($imgReceipt) { $imgReceipt.Source = $bmp }
            if ($scrollViewer) { $scrollViewer.Visibility = [System.Windows.Visibility]::Visible }
            if ($missingPanel) { $missingPanel.Visibility = [System.Windows.Visibility]::Collapsed }

            if ($txtBadge) {
                $extName = [System.IO.Path]::GetExtension($receiptPath).TrimStart('.').ToUpper()
                $txtBadge.Text = "Cached ($extName)"
                $txtBadge.Foreground = [System.Windows.Application]::Current.FindResource("SageBrush")
            }

            if ($btnOpenFile) {
                $btnOpenFile.Tag = $receiptPath
                $btnOpenFile.IsEnabled = $true
            }
        } catch {
            $receiptFound = $false
        }
    }

    if (-not $receiptFound -or -not $displayImgPath) {
        if ($imgReceipt) { $imgReceipt.Source = $null }
        if ($scrollViewer) { $scrollViewer.Visibility = [System.Windows.Visibility]::Collapsed }
        if ($missingPanel) { $missingPanel.Visibility = [System.Windows.Visibility]::Visible }

        if ($txtBadge) {
            $txtBadge.Text = "Not Cached"
            $txtBadge.Foreground = [System.Windows.Application]::Current.FindResource("MutedBrush")
        }

        if ($btnOpenFile) {
            $btnOpenFile.Tag = $null
            $btnOpenFile.IsEnabled = $false
        }
    }
}

function Open-ReviewView {
    if (-not $script:activeCourse) { return }
    $rv = Get-OrCreateView "ReviewView"
    Update-ReviewView -Course $script:activeCourse
    Navigate-To "ReviewView"
}

# 10. Wire Events per View (Using dynamic lookups to prevent scope closure loss)
function Wire-ViewEvents {
    param([string]$ViewName, $viewObj)
    if (-not $viewObj) { return }

    switch ($ViewName) {
        "HomeView" {
            # Start Registration Button
            $btnStart = $viewObj.FindName("BtnStartRegistration")
            if ($btnStart) {
                $btnStart.Add_Click({
                    $v = $script:views["HomeView"]
                    if ($v) {
                        $pw = $v.FindName("PanelHomeWelcome")
                        $pf = $v.FindName("PanelRegisterForm")
                        if ($pw) { $pw.Visibility = [System.Windows.Visibility]::Collapsed }
                        if ($pf) { $pf.Visibility = [System.Windows.Visibility]::Visible }
                    }
                })
            }

            # Back button
            $btnBack = $viewObj.FindName("BtnBackFromRegister")
            if ($btnBack) {
                $btnBack.Add_Click({
                    $v = $script:views["HomeView"]
                    if ($v) {
                        $pw = $v.FindName("PanelHomeWelcome")
                        $pf = $v.FindName("PanelRegisterForm")
                        if ($pf) { $pf.Visibility = [System.Windows.Visibility]::Collapsed }
                        if ($pw) { $pw.Visibility = [System.Windows.Visibility]::Visible }
                    }
                })
            }

            # Cancel button
            $btnCancel = $viewObj.FindName("BtnCancelRegister")
            if ($btnCancel) {
                $btnCancel.Add_Click({
                    $v = $script:views["HomeView"]
                    if ($v) {
                        $pw = $v.FindName("PanelHomeWelcome")
                        $pf = $v.FindName("PanelRegisterForm")
                        if ($pf) { $pf.Visibility = [System.Windows.Visibility]::Collapsed }
                        if ($pw) { $pw.Visibility = [System.Windows.Visibility]::Visible }
                    }
                })
            }

            # File Picker: Student Registration Sheet
            $btnBrowseReg = $viewObj.FindName("BtnBrowseRegistrationSheet")
            if ($btnBrowseReg) {
                $btnBrowseReg.Add_Click({
                    $selected = Show-ExcelBrowseDialog "Select Student Registration & Enrollment Spreadsheet"
                    if ($selected) {
                        $v = $script:views["HomeView"]
                        $txt = if ($v) { $v.FindName("TxtRegistrationSheetPath") } else { $null }
                        if ($txt) { $txt.Text = $selected }
                    }
                })
            }

            # Create Course CTA
            $btnCreate = $viewObj.FindName("BtnCreateCourse")
            if ($btnCreate) {
                $btnCreate.Add_Click({
                    $v = $script:views["HomeView"]
                    if (-not $v) { return }

                    $txtCourseName = $v.FindName("TxtCourseName")
                    $txtCourseCode = $v.FindName("TxtCourseCode")
                    $txtDepartment = $v.FindName("TxtDepartment")
                    $txtSemester = $v.FindName("TxtSemester")
                    $txtSheet = $v.FindName("TxtRegistrationSheetPath")

                    $name = if ($txtCourseName -and $txtCourseName.Text) { $txtCourseName.Text.Trim() } else { "" }
                    $sheet = if ($txtSheet -and $txtSheet.Text) { $txtSheet.Text.Trim() } else { "" }

                    if (-not $name) {
                        [System.Windows.MessageBox]::Show("Please enter a Course Title to create a workspace.", "Course Title Required", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                        return
                    }

                    if (-not $sheet) {
                        [System.Windows.MessageBox]::Show("Please select or attach a Student Enrollment & Registration spreadsheet (.xlsx, .xls, or .csv) before creating the course.", "Spreadsheet Required", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                        return
                    }

                    if (-not (Test-Path $sheet)) {
                        [System.Windows.MessageBox]::Show("The selected spreadsheet file could not be found:`n$sheet`nPlease browse and pick a valid file.", "File Not Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                        return
                    }

                    $newCourse = [PSCustomObject]@{
                        Id = [Guid]::NewGuid().ToString()
                        Name = $name
                        Code = if ($txtCourseCode -and $txtCourseCode.Text) { $txtCourseCode.Text.Trim() } else { "" }
                        Department = if ($txtDepartment -and $txtDepartment.Text) { $txtDepartment.Text.Trim() } else { "" }
                        Semester = if ($txtSemester -and $txtSemester.Text) { $txtSemester.Text.Trim() } else { "" }
                        RegistrationSheet = if ($txtSheet -and $txtSheet.Text) { $txtSheet.Text.Trim() } else { "" }
                        VerificationSheet = ""
                        ExamResultsSheet = ""
                        Stage = "Registration"
                        Created = (Get-Date).ToString("yyyy-MM-dd HH:mm")
                    }

                    $null = $script:courses.Add($newCourse)
                    Save-Courses

                    # Ingest and persist student enrollment records
                    if ($newCourse.RegistrationSheet -and (Test-Path -LiteralPath $newCourse.RegistrationSheet)) {
                        $parsedSheet = Import-StudentSheet -Path $newCourse.RegistrationSheet
                        if ($parsedSheet.Success -and $parsedSheet.Students.Count -gt 0) {
                            Save-CourseStudents -CourseId $newCourse.Id -Students $parsedSheet.Students
                        }
                    }

                    # Clear input values
                    if ($txtCourseName) { $txtCourseName.Text = "" }
                    if ($txtCourseCode) { $txtCourseCode.Text = "" }
                    if ($txtDepartment) { $txtDepartment.Text = "" }
                    if ($txtSemester) { $txtSemester.Text = "" }
                    if ($txtSheet) { $txtSheet.Text = "" }

                    # Reset to Welcome launcher
                    $pw = $v.FindName("PanelHomeWelcome")
                    $pf = $v.FindName("PanelRegisterForm")
                    if ($pf) { $pf.Visibility = [System.Windows.Visibility]::Collapsed }
                    if ($pw) { $pw.Visibility = [System.Windows.Visibility]::Visible }

                    Refresh-CourseLists
                    Select-Course $newCourse
                })
            }

            # View Courses Navigation from Home
            $btnBrowseFromHome = $viewObj.FindName("BtnBrowseCoursesFromHome")
            if ($btnBrowseFromHome) {
                $btnBrowseFromHome.Add_Click({ Navigate-To "CoursesView" })
            }

            Refresh-CourseLists
        }

        "CoursesView" {
            $btnNew = $viewObj.FindName("BtnHeaderAddNewCourse")
            if ($btnNew) {
                $btnNew.Add_Click({
                    Navigate-To "HomeView"
                    $hv = $script:views["HomeView"]
                    if ($hv) {
                        $pw = $hv.FindName("PanelHomeWelcome")
                        $pf = $hv.FindName("PanelRegisterForm")
                        if ($pw) { $pw.Visibility = [System.Windows.Visibility]::Collapsed }
                        if ($pf) { $pf.Visibility = [System.Windows.Visibility]::Visible }
                    }
                })
            }
            $btnEmptyNew = $viewObj.FindName("BtnEmptyStateAddCourse")
            if ($btnEmptyNew) {
                $btnEmptyNew.Add_Click({
                    Navigate-To "HomeView"
                    $hv = $script:views["HomeView"]
                    if ($hv) {
                        $pw = $hv.FindName("PanelHomeWelcome")
                        $pf = $hv.FindName("PanelRegisterForm")
                        if ($pw) { $pw.Visibility = [System.Windows.Visibility]::Collapsed }
                        if ($pf) { $pf.Visibility = [System.Windows.Visibility]::Visible }
                    }
                })
            }

            Refresh-CourseLists
        }

        "WorkspaceView" {
            # Stage 1 Card Click -> Navigate to Stage1View
            $cardStage1 = $viewObj.FindName("CardStage1")
            if ($cardStage1) {
                $cardStage1.Add_MouseLeftButtonUp({
                    Navigate-To "Stage1View"
                })
            }

            # Stage 2 Card Click -> Navigate to Stage2View
            $cardStage2 = $viewObj.FindName("CardStage2")
            if ($cardStage2) {
                $cardStage2.Add_MouseLeftButtonUp({
                    Navigate-To "Stage2View"
                })
            }

            # Delete Course from Workspace Header
            $btnDelete = $viewObj.FindName("BtnDeleteCourseFromWorkspace")
            if ($btnDelete) {
                $btnDelete.Add_Click({
                    if ($script:activeCourse) {
                        Remove-Course -CourseId $script:activeCourse.Id
                    }
                })
            }
        }

        "Stage1View" {
            # Back to Workspace
            $btnBack = $viewObj.FindName("BtnBackToWorkspace")
            if ($btnBack) {
                $btnBack.Add_Click({
                    Navigate-To "WorkspaceView"
                })
            }

            # Open Sheet in Windows default application (Excel/LibreOffice/etc.)
            $btnOpenSheet = $viewObj.FindName("BtnOpenRegistrationSheet")
            if ($btnOpenSheet) {
                $btnOpenSheet.Add_Click({
                    if (-not $script:activeCourse -or -not $script:activeCourse.RegistrationSheet) {
                        [System.Windows.MessageBox]::Show("No registration spreadsheet is attached to this course.", "No Sheet Attached", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                        return
                    }
                    $path = [string]$script:activeCourse.RegistrationSheet
                    if (Test-Path -LiteralPath $path) {
                        [System.Diagnostics.Process]::Start($path)
                    } else {
                        [System.Windows.MessageBox]::Show("The attached spreadsheet file could not be found at:`n$path", "File Not Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                    }
                })
            }

            # In-App Sheet Preview Handler
            $btnPreviewSheet = $viewObj.FindName("BtnPreviewRegistrationSheet")
            if ($btnPreviewSheet) {
                $btnPreviewSheet.Add_Click({
                    if (-not $script:activeCourse -or -not $script:activeCourse.RegistrationSheet) {
                        [System.Windows.MessageBox]::Show("No registration spreadsheet is attached to this course.", "No Sheet Attached", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                        return
                    }
                    $path = [string]$script:activeCourse.RegistrationSheet
                    if (-not (Test-Path -LiteralPath $path)) {
                        [System.Windows.MessageBox]::Show("The attached spreadsheet file could not be found at:`n$path", "File Not Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                        return
                    }

                    $dv = $script:views["Stage1View"]
                    if (-not $dv) { return }

                    $modal = $dv.FindName("SheetPreviewModal")
                    $grid = $dv.FindName("DataGridSheetPreview")
                    $title = $dv.FindName("TxtPreviewSheetTitle")
                    $subtitle = $dv.FindName("TxtPreviewSheetSubtitle")
                    $footerNote = $dv.FindName("TxtPreviewFooterNote")

                    $fileName = [System.IO.Path]::GetFileName($path)
                    if ($title) { $title.Text = "Preview: $fileName" }
                    if ($subtitle) { $subtitle.Text = "Parsing spreadsheet rows..." }
                    if ($modal) { $modal.Visibility = [System.Windows.Visibility]::Visible }

                    # Parse spreadsheet via Import-StudentSheet
                    $parsed = Import-StudentSheet -Path $path
                    if ($parsed.Success) {
                        if ($grid) {
                            $grid.ItemsSource = $null
                            $grid.ItemsSource = $parsed.Rows
                        }
                        if ($subtitle) {
                            $subtitle.Text = "$($parsed.RowCount) student records found in sheet."
                        }
                        if ($footerNote) {
                            $footerNote.Text = "Headers detected: $($parsed.Headers.Count) columns | Total records: $($parsed.RowCount)"
                        }
                    } else {
                        if ($subtitle) {
                            $subtitle.Text = "Error reading sheet: $($parsed.Error)"
                        }
                        [System.Windows.MessageBox]::Show("Could not read sheet:`n$($parsed.Error)", "Preview Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                    }
                })
            }

            # Close In-App Sheet Preview Handlers
            $btnCloseX = $viewObj.FindName("BtnClosePreviewX")
            if ($btnCloseX) {
                $btnCloseX.Add_Click({
                    $dv = $script:views["Stage1View"]
                    if ($dv) {
                        $modal = $dv.FindName("SheetPreviewModal")
                        if ($modal) { $modal.Visibility = [System.Windows.Visibility]::Collapsed }
                    }
                })
            }

            $btnClose = $viewObj.FindName("BtnClosePreview")
            if ($btnClose) {
                $btnClose.Add_Click({
                    $dv = $script:views["Stage1View"]
                    if ($dv) {
                        $modal = $dv.FindName("SheetPreviewModal")
                        if ($modal) { $modal.Visibility = [System.Windows.Visibility]::Collapsed }
                    }
                })
            }

            $btnModalOpenSystem = $viewObj.FindName("BtnPreviewOpenSystem")
            if ($btnModalOpenSystem) {
                $btnModalOpenSystem.Add_Click({
                    if ($script:activeCourse -and $script:activeCourse.RegistrationSheet) {
                        $path = [string]$script:activeCourse.RegistrationSheet
                        if (Test-Path -LiteralPath $path) {
                            [System.Diagnostics.Process]::Start($path)
                        }
                    }
                })
            }

            # Recheck Registration Sheet Health Handler
            $btnRecheckHealth = $viewObj.FindName("BtnRecheckSheetHealth")
            if ($btnRecheckHealth) {
                $btnRecheckHealth.Add_Click({
                    if (-not $script:activeCourse) { return }
                    $sheetPath = [string]$script:activeCourse.RegistrationSheet
                    if (-not $sheetPath -or -not (Test-Path -LiteralPath $sheetPath)) {
                        [System.Windows.MessageBox]::Show("The attached spreadsheet file could not be found:`n$sheetPath`nPlease check the file location or use 'Replace Sheet...'.", "File Not Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                        return
                    }

                    # Force re-ingestion from disk and update store
                    $null = Get-CourseStudentStore -CourseId $script:activeCourse.Id -RegistrationSheet $sheetPath -Force

                    # Refresh views with updated store and health badges
                    Select-Course $script:activeCourse

                    [System.Windows.MessageBox]::Show("Registration sheet health rechecked and updated successfully.", "Health Rechecked", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                })
            }

            # Replace Registration Sheet Handler
            $btnChangeSheet = $viewObj.FindName("BtnChangeRegistrationSheet")
            if ($btnChangeSheet) {
                $btnChangeSheet.Add_Click({
                    if (-not $script:activeCourse) { return }
                    $selected = Show-ExcelBrowseDialog "Select Replacement Student Registration Spreadsheet"
                    if ($selected) {
                        $script:activeCourse.RegistrationSheet = $selected
                        Save-Courses

                        # Force re-ingestion and rebuild store for the newly attached spreadsheet
                        $null = Get-CourseStudentStore -CourseId $script:activeCourse.Id -RegistrationSheet $selected -Force

                        # Refresh views with updated store and health badges
                        Select-Course $script:activeCourse

                        [System.Windows.MessageBox]::Show("Registration sheet updated and health verified for '$($script:activeCourse.Name)'.", "Sheet Updated", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                    }
                })
            }

            # Generate Verification Sheet Handler
            $btnGenVerSheet = $viewObj.FindName("BtnGenerateVerificationSheet")
            if ($btnGenVerSheet) {
                $btnGenVerSheet.Add_Click({
                    if (-not $script:activeCourse) { return }
                    try {
                        $targetPath = New-CourseVerificationSheet -Course $script:activeCourse
                        Select-Course $script:activeCourse
                        [System.Windows.MessageBox]::Show(
                            "Verification sheet generated successfully at:`n$targetPath`n`nNew columns 'Verification Status' and 'Verification Remarks' were appended.",
                            "Verification Sheet Ready",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Information
                        )
                    } catch {
                        [System.Windows.MessageBox]::Show(
                            "Failed to generate verification sheet:`n$($_.Exception.Message)",
                            "Generation Error",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Error
                        )
                    }
                })
            }

            # Open Verification Sheet in Windows Default App
            $btnOpenVerSheet = $viewObj.FindName("BtnOpenVerificationSheet")
            if ($btnOpenVerSheet) {
                $btnOpenVerSheet.Add_Click({
                    if (-not $script:activeCourse -or -not $script:activeCourse.VerificationSheet) { return }
                    $path = [string]$script:activeCourse.VerificationSheet
                    if (Test-Path -LiteralPath $path) {
                        [System.Diagnostics.Process]::Start($path)
                    } else {
                        [System.Windows.MessageBox]::Show("Verification sheet file not found at:`n$path", "File Not Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                    }
                })
            }

            # Preview Verification Sheet in Modal DataGrid
            $btnPrevVerSheet = $viewObj.FindName("BtnPreviewVerificationSheet")
            if ($btnPrevVerSheet) {
                $btnPrevVerSheet.Add_Click({
                    if (-not $script:activeCourse -or -not $script:activeCourse.VerificationSheet) { return }
                    $path = [string]$script:activeCourse.VerificationSheet
                    if (-not (Test-Path -LiteralPath $path)) {
                        [System.Windows.MessageBox]::Show("Verification sheet file not found at:`n$path", "File Not Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                        return
                    }

                    $dv = $script:views["Stage1View"]
                    if (-not $dv) { return }

                    $modal = $dv.FindName("SheetPreviewModal")
                    $grid = $dv.FindName("DataGridSheetPreview")
                    $title = $dv.FindName("TxtPreviewSheetTitle")
                    $subtitle = $dv.FindName("TxtPreviewSheetSubtitle")
                    $footerNote = $dv.FindName("TxtPreviewFooterNote")

                    $fileName = [System.IO.Path]::GetFileName($path)
                    if ($title) { $title.Text = "Preview: $fileName" }
                    if ($subtitle) { $subtitle.Text = "Parsing verification sheet rows..." }
                    if ($modal) { $modal.Visibility = [System.Windows.Visibility]::Visible }

                    $parsed = Import-StudentSheet -Path $path
                    if ($parsed.Success) {
                        if ($grid) {
                            $grid.ItemsSource = $null
                            $grid.ItemsSource = $parsed.Rows
                        }
                        if ($subtitle) {
                            $subtitle.Text = "$($parsed.RowCount) student records with Verification Status columns."
                        }
                        if ($footerNote) {
                            $footerNote.Text = "Headers: $($parsed.Headers.Count) columns | Total records: $($parsed.RowCount)"
                        }
                    } else {
                        if ($subtitle) { $subtitle.Text = "Error reading sheet: $($parsed.Error)" }
                    }
                })
            }

            # Re-generate / Recreate Verification Sheet Handler
            $btnRecreateVerSheet = $viewObj.FindName("BtnRecreateVerificationSheet")
            if ($btnRecreateVerSheet) {
                $btnRecreateVerSheet.Add_Click({
                    if (-not $script:activeCourse) { return }
                    $res = [System.Windows.MessageBox]::Show(
                        "Do you want to re-generate the Verification Sheet from the current registration responses?`n`nNote: This will refresh all rows and reset statuses to 'Pending'.",
                        "Re-generate Verification Sheet",
                        [System.Windows.MessageBoxButton]::YesNo,
                        [System.Windows.MessageBoxImage]::Question
                    )
                    if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
                        try {
                            $targetPath = New-CourseVerificationSheet -Course $script:activeCourse
                            Select-Course $script:activeCourse
                            [System.Windows.MessageBox]::Show("Verification sheet re-generated successfully.", "Sheet Updated", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                        } catch {
                            [System.Windows.MessageBox]::Show("Error re-generating verification sheet:`n$($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                        }
                    }
                })
            }

            # Automated Batch Verification (OCR) Handler
            $btnVerifyAll = $viewObj.FindName("BtnVerifyAll")
            if ($btnVerifyAll) {
                $btnVerifyAll.Add_Click({
                    try {
                        if (-not $script:activeCourse) {
                            [System.Windows.MessageBox]::Show(
                                "Please select a course first before verifying.",
                                "No Active Course",
                                [System.Windows.MessageBoxButton]::OK,
                                [System.Windows.MessageBoxImage]::Warning
                            )
                            return
                        }

                        # 1. Ensure Verification Sheet exists or prompt to auto-generate
                        $vSheetPath = if ($script:activeCourse.PSObject.Properties['VerificationSheet']) { [string]$script:activeCourse.VerificationSheet } else { $null }
                        if (-not $vSheetPath -or -not (Test-Path -LiteralPath $vSheetPath)) {
                            $askGen = [System.Windows.MessageBox]::Show(
                                "A Verification Sheet has not been generated for '$($script:activeCourse.Name)' yet.`n`nWould you like to generate it now and proceed with verification?",
                                "Generate Verification Sheet?",
                                [System.Windows.MessageBoxButton]::YesNo,
                                [System.Windows.MessageBoxImage]::Question
                            )
                            if ($askGen -eq [System.Windows.MessageBoxResult]::Yes) {
                                $vSheetPath = New-CourseVerificationSheet -Course $script:activeCourse
                                Select-Course $script:activeCourse
                            } else {
                                return
                            }
                        }

                        # 2. Inspect student roster
                        $store = Get-CourseStudentStore -CourseId $script:activeCourse.Id -RegistrationSheet $script:activeCourse.RegistrationSheet -CourseName $script:activeCourse.Name
                        $students = @($store.Students)
                        $regStudents = @($students | Where-Object { $_.IsRegistered -eq $true })

                        if ($regStudents.Count -eq 0) {
                            [System.Windows.MessageBox]::Show(
                                "No registered students found to verify in course '$($script:activeCourse.Name)'.",
                                "No Students Queued",
                                [System.Windows.MessageBoxButton]::OK,
                                [System.Windows.MessageBoxImage]::Information
                            )
                            return
                        }

                        # 3. Confirmation Dialog
                        $confirm = [System.Windows.MessageBox]::Show(
                            "Start automated batch receipt verification for '$($script:activeCourse.Name)'?`n`n" +
                            "Students queued: $($regStudents.Count) registered student(s)`n`n" +
                            "The pipeline will execute:`n" +
                            "1. Download / retrieve receipts from local cache or links`n" +
                            "2. Perform native WinRT OCR text extraction (PDF / Images)`n" +
                            "3. Evaluate the 5 verification rules (Status, Rs. 1000/1100 Fee, Course Title, Authenticity, Identity)`n" +
                            "4. Delta-sync and auto-update students.json and the Excel Verification Sheet.",
                            "Confirm Automated Verification",
                            [System.Windows.MessageBoxButton]::YesNo,
                            [System.Windows.MessageBoxImage]::Question
                        )
                        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

                        # 4. Run Pipeline with Wait Cursor & Visual Feedback
                        $origCursor = [System.Windows.Input.Mouse]::OverrideCursor
                        $dv = $script:views["Stage1View"]
                        $btn = if ($dv) { $dv.FindName("BtnVerifyAll") } else { $null }
                        $origContent = if ($btn) { $btn.Content } else { "▶ Verify All (OCR)" }
                        try {
                            [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
                            if ($btn) {
                                $btn.IsEnabled = $false
                                $btn.Content = "Verifying Receipts (OCR)..."
                            }

                            $dDir = if ($script:dataDir) { $script:dataDir } else { (Join-Path $script:appRoot "data") }
                            $summary = Invoke-CourseVerificationPipeline -Course $script:activeCourse -DataDir $dDir

                            # Refresh views and mini cards
                            Select-Course $script:activeCourse

                            $vFileName = if ($script:activeCourse.VerificationSheet) { [System.IO.Path]::GetFileName($script:activeCourse.VerificationSheet) } else { "Verification Sheet" }
                            [System.Windows.MessageBox]::Show(
                                "Automated Verification Completed for '$($script:activeCourse.Name)'!`n`n" +
                                "[Verified]: $($summary.VerifiedCount)`n" +
                                "[Under Review]: $($summary.ReviewCount)`n" +
                                "[Did Not Register]: $($summary.UnregCount)`n" +
                                "Total Processed: $($summary.ProcessedCount) of $($summary.TotalStudents)`n`n" +
                                "Database: data/Courses/$($script:activeCourse.Name)/students.json`n" +
                                "Excel Sheet: $vFileName",
                                "Verification Complete",
                                [System.Windows.MessageBoxButton]::OK,
                                [System.Windows.MessageBoxImage]::Information
                            )
                        } finally {
                            [System.Windows.Input.Mouse]::OverrideCursor = $origCursor
                            if ($btn) {
                                $btn.Content = $origContent
                                $btn.IsEnabled = $true
                            }
                        }
                    } catch {
                        [System.Windows.MessageBox]::Show(
                            "Verification pipeline failed:`n$($_.Exception.Message)",
                            "Verification Error",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Error
                        )
                    }
                })
            }

            # Mini Dashboard Cards Click Handlers
            $cardVerified = $viewObj.FindName("CardVerStatVerified")
            if ($cardVerified) {
                $cardVerified.Add_MouseLeftButtonUp({
                    $dv = $script:views["Stage1View"]
                    $txt = if ($dv) { $dv.FindName("TxtVerStatVerified") } else { $null }
                    $count = if ($txt) { $txt.Text } else { "0" }
                    [System.Windows.MessageBox]::Show(
                        "Verified Students: $count`n`nIn Phase F, clicking this card will open the filtered student roster showing all verified students with export options.",
                        "Verified Students",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    )
                })
            }

            $cardReview = $viewObj.FindName("CardVerStatReview")
            if ($cardReview) {
                $cardReview.Add_MouseLeftButtonUp({
                    if (-not $script:activeCourse) {
                        [System.Windows.MessageBox]::Show(
                            "Please select or register a course first.",
                            "Notice",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Information
                        )
                        return
                    }
                    Open-ReviewView
                })
            }

            $cardUnreg = $viewObj.FindName("CardVerStatUnreg")
            if ($cardUnreg) {
                $cardUnreg.Add_MouseLeftButtonUp({
                    $dv = $script:views["Stage1View"]
                    $txt = if ($dv) { $dv.FindName("TxtVerStatUnreg") } else { $null }
                    $count = if ($txt) { $txt.Text } else { "0" }
                    [System.Windows.MessageBox]::Show(
                        "Did Not Register: $count`n`nIn Phase F, clicking this card will open the roster filtered to students who opted out of the examination.",
                        "Did Not Register",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    )
                })
            }
        }

        "Stage2View" {
            # Back to Workspace
            $btnBack = $viewObj.FindName("BtnBackToWorkspace")
            if ($btnBack) {
                $btnBack.Add_Click({
                    Navigate-To "WorkspaceView"
                })
            }

            # Stage 2 Exam Results Upload Handler
            $btnUploadResults = $viewObj.FindName("BtnUploadExamResults")
            if ($btnUploadResults) {
                $btnUploadResults.Add_Click({
                    if (-not $script:activeCourse) {
                        [System.Windows.MessageBox]::Show("Please select or register a course first.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                        return
                    }

                    $selected = Show-ExcelBrowseDialog "Select Official NPTEL Exam Results Spreadsheet"
                    if ($selected) {
                        $script:activeCourse.ExamResultsSheet = $selected
                        $script:activeCourse.Stage = "ResultsUploaded"
                        Save-Courses

                        # Refresh all views with updated state
                        Select-Course $script:activeCourse

                        [System.Windows.MessageBox]::Show("Exam results spreadsheet attached for '$($script:activeCourse.Name)'.`nReady for grade & credit reconciliation!", "Results Uploaded", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                    }
                })
            }
        }

        "ReviewView" {
            # Back to Stage 1
            $btnBack = $viewObj.FindName("BtnBackToStage1")
            if ($btnBack) {
                $btnBack.Add_Click({
                    if ($script:activeCourse) {
                        Select-Course $script:activeCourse -TargetView "Stage1View"
                    } else {
                        Navigate-To "CoursesView"
                    }
                })
            }

            # Open Drive Link in Default Browser
            $btnDrive = $viewObj.FindName("BtnOpenDriveLink")
            if ($btnDrive) {
                $btnDrive.Add_Click({
                    $url = [string]$this.Tag
                    if ($url -and ($url.StartsWith("http://") -or $url.StartsWith("https://"))) {
                        try {
                            [System.Diagnostics.Process]::Start([System.Diagnostics.ProcessStartInfo]@{
                                FileName = $url
                                UseShellExecute = $true
                            }) | Out-Null
                        } catch {
                            [System.Windows.MessageBox]::Show("Unable to open URL in browser: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                        }
                    }
                })
            }

            # Open Cached Receipt in External Viewer
            $btnOpenFile = $viewObj.FindName("BtnOpenReceiptFile")
            if ($btnOpenFile) {
                $btnOpenFile.Add_Click({
                    $filePath = [string]$this.Tag
                    if ($filePath -and (Test-Path -LiteralPath $filePath)) {
                        try {
                            [System.Diagnostics.Process]::Start([System.Diagnostics.ProcessStartInfo]@{
                                FileName = $filePath
                                UseShellExecute = $true
                            }) | Out-Null
                        } catch {
                            [System.Windows.MessageBox]::Show("Unable to open receipt file: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                        }
                    }
                })
            }

            # Zoom In Control
            $btnZoomIn = $viewObj.FindName("BtnZoomIn")
            if ($btnZoomIn) {
                $btnZoomIn.Add_Click({
                    $rv = $script:views["ReviewView"]
                    $scale = if ($rv) { $rv.FindName("ReceiptZoomScale") } else { $null }
                    $lbl = if ($rv) { $rv.FindName("TxtZoomLevel") } else { $null }
                    if ($scale) {
                        $newVal = [Math]::Min(4.0, [Math]::Round($scale.ScaleX * 1.25, 2))
                        $scale.ScaleX = $newVal
                        $scale.ScaleY = $newVal
                        if ($lbl) { $lbl.Text = "$([int]($newVal * 100))%" }
                    }
                })
            }

            # Zoom Out Control
            $btnZoomOut = $viewObj.FindName("BtnZoomOut")
            if ($btnZoomOut) {
                $btnZoomOut.Add_Click({
                    $rv = $script:views["ReviewView"]
                    $scale = if ($rv) { $rv.FindName("ReceiptZoomScale") } else { $null }
                    $lbl = if ($rv) { $rv.FindName("TxtZoomLevel") } else { $null }
                    if ($scale) {
                        $newVal = [Math]::Max(0.25, [Math]::Round($scale.ScaleX / 1.25, 2))
                        $scale.ScaleX = $newVal
                        $scale.ScaleY = $newVal
                        if ($lbl) { $lbl.Text = "$([int]($newVal * 100))%" }
                    }
                })
            }

            # Reset Zoom Fit Control
            $btnZoomFit = $viewObj.FindName("BtnZoomFit")
            if ($btnZoomFit) {
                $btnZoomFit.Add_Click({
                    $rv = $script:views["ReviewView"]
                    $scale = if ($rv) { $rv.FindName("ReceiptZoomScale") } else { $null }
                    $lbl = if ($rv) { $rv.FindName("TxtZoomLevel") } else { $null }
                    if ($scale) {
                        $scale.ScaleX = 1.0
                        $scale.ScaleY = 1.0
                        if ($lbl) { $lbl.Text = "100%" }
                    }
                })
            }

            # Download Missing Receipt Handler
            $btnDl = $viewObj.FindName("BtnDownloadMissingReceipt")
            if ($btnDl) {
                $btnDl.Add_Click({
                    $st = $this.Tag
                    if (-not $st -or -not $script:activeCourse) { return }
                    if (-not $st.ProofUrl) {
                        [System.Windows.MessageBox]::Show("This student has not provided a proof URL.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                        return
                    }

                    $cName = if ($script:activeCourse.Name) { [string]$script:activeCourse.Name } else { "Default" }
                    try {
                        $origCursor = [System.Windows.Input.Mouse]::OverrideCursor
                        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait

                        $dlResults = Download-CourseReceipts -CourseId $script:activeCourse.Id -CourseName $cName -Students @($st) -Force
                        Show-StudentReviewDetails -Student $st
                    } catch {
                        [System.Windows.MessageBox]::Show("Failed to download receipt: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                    } finally {
                        [System.Windows.Input.Mouse]::OverrideCursor = $origCursor
                    }
                })
            }
        }
    }
}

# 11. Navigation Router
function Navigate-To {
    param([string]$ViewName)

    $viewControl = Get-OrCreateView $ViewName
    if (-not $viewControl) { return }

    $script:currentView = $ViewName

    # Swap active view in the ContentControl outlet
    $ViewContainer.Content = $viewControl

    # Update Tab Active Styles
    $activeStyle = [System.Windows.Application]::Current.FindResource("BtnNavActive")
    $defaultStyle = [System.Windows.Application]::Current.FindResource("BtnNav")

    if ($NavBtnHome) { $NavBtnHome.Style = if ($ViewName -eq "HomeView") { $activeStyle } else { $defaultStyle } }
    if ($NavBtnCourses) { $NavBtnCourses.Style = if ($ViewName -eq "CoursesView" -or $ViewName -eq "WorkspaceView" -or $ViewName -eq "Stage1View" -or $ViewName -eq "Stage2View" -or $ViewName -eq "ReviewView") { $activeStyle } else { $defaultStyle } }
    if ($NavBtnSettings) { $NavBtnSettings.Style = if ($ViewName -eq "SettingsView") { $activeStyle } else { $defaultStyle } }

    Refresh-CourseLists
}

# 12. Attach Navigation Bar Events
if ($NavBtnHome) { $NavBtnHome.Add_Click({ Navigate-To "HomeView" }) }
if ($NavBtnCourses) { $NavBtnCourses.Add_Click({ Navigate-To "CoursesView" }) }
if ($NavBtnSettings) { $NavBtnSettings.Add_Click({ Navigate-To "SettingsView" }) }

if ($BtnHeaderSync) {
    $BtnHeaderSync.Add_Click({
        if ($script:activeCourse) {
            [System.Windows.MessageBox]::Show("Synchronizing student sheets for '$($script:activeCourse.Name)'...", "Sync Status", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        } else {
            [System.Windows.MessageBox]::Show("No active course selected to sync. Please select or add a course first.", "Sync Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        }
    })
}

# 13. Initial Route: Home View (Course Setup & Launcher)
Navigate-To "HomeView"

# 14. Run Main Window
$window.ShowDialog() | Out-Null
