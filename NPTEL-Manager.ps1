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
$script:reviewSessionCourseId = ""
$script:reviewSessionSolvedRolls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$script:reviewStagedSolved = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

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
    $coursesParent = Join-Path $dataDir "Courses"

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
    $legacyPath = Join-Path $dataDir "students_$CourseId.json"
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
        [string]$RegistrationSheet = $null,
        [string]$CourseName = $null
    )
    $store = Get-CourseStudentStore -CourseId $CourseId -RegistrationSheet $RegistrationSheet -CourseName $CourseName
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
    $store = Get-CourseStudentStore -CourseId $Course.Id -RegistrationSheet $regSheet -CourseName $Course.Name
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
        Save-CourseStudents -CourseId $Course.Id -Students $store.Students -ColumnMap $store.ColumnMap -CourseName $Course.Name
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
    $script:courses = [System.Collections.ArrayList]@($script:courses | Where-Object { [string]$_.Id -ne $CourseId })
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
        $guidDir = Join-Path $appRoot "data\Courses\$CourseId"
        if (Test-Path -LiteralPath $guidDir) {
            Remove-Item -LiteralPath $guidDir -Recurse -Force -ErrorAction SilentlyContinue
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
    if ($Course.Id -ne $script:reviewSessionCourseId) {
        $script:reviewSessionCourseId = $Course.Id
        $script:reviewSessionSolvedRolls.Clear()
        $script:reviewStagedSolved.Clear()
    }
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
    $store = Get-CourseStudentStore -CourseId $Course.Id -RegistrationSheet $Course.RegistrationSheet -CourseName $Course.Name
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

    # -- Update Workspace View (Overview) --
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

    # -- Update Stage 1 View (Registration & Verification) --
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

        # Mini-Summary Text on the Collapsed Header Row
        $txtMiniHealth = $s1View.FindName("TxtMiniSheetHealthSummary")
        $detectedCount = 7 - $missingCols.Count
        if ($txtMiniHealth) {
            $txtMiniHealth.Text = "$totalCount Total Students  " + [char]0x2022 + "  $regCount Exam Registered  " + [char]0x2022 + "  $detectedCount/7 Standard Columns Detected"
        }

        # Overall Health & Missing Column Warning Banner
        $panelWarn = $s1View.FindName("PanelColumnWarning")
        $txtWarnTitle = $s1View.FindName("TxtColumnWarningTitle")
        $txtWarnMsg = $s1View.FindName("TxtColumnWarningMessage")
        $badgeHealth = $s1View.FindName("BadgeOverallHealth")
        $txtHealth = $s1View.FindName("TxtOverallHealth")

        # Categorize missing columns into Critical vs Optional
        $hasCriticalMissing = ('RollNo' -in $missingCols -or 'Name' -in $missingCols -or 'Proof Receipt' -in $missingCols)
        $warnLines = [System.Collections.ArrayList]@()

        if ('RollNo' -in $missingCols) {
            $null = $warnLines.Add([char]0x2022 + " Roll Number (RollNo) Missing:`n  Required to identify students and name receipt files on disk. Automated verification cannot continue without this column.")
        }
        if ('Name' -in $missingCols) {
            $null = $warnLines.Add([char]0x2022 + " Student Name (Name) Missing:`n  Required to verify student identity against receipt greeting (Rule 5). Automated verification cannot continue without this column.")
        }
        if ('Proof Receipt' -in $missingCols) {
            $null = $warnLines.Add([char]0x2022 + " Receipt Link (ProofUrl) Missing:`n  Required to download and verify payment receipts via OCR. Automated verification cannot continue without this column.")
        }
        if ('Email' -in $missingCols) {
            $null = $warnLines.Add([char]0x2022 + " Email Column Missing:`n  You will not be able to send automated email alerts to students. (Announcement notice copy for class WhatsApp/Telegram remains available).")
        }
        if ('Exam Registered' -in $missingCols) {
            $null = $warnLines.Add([char]0x2022 + " Registration Done Missing:`n  The system will assume all form submitters registered for the exam.")
        }
        if ('Subject' -in $missingCols) {
            $courseDisplayName = if ($script:activeCourse -and $script:activeCourse.Name) { [string]$script:activeCourse.Name } else { "Course Title" }
            $null = $warnLines.Add([char]0x2022 + " Subject Column Missing:`n  The system will use the active Course Title ('$courseDisplayName') for receipt verification matching.")
        }
        if ('Enrolled' -in $missingCols) {
            $null = $warnLines.Add([char]0x2022 + " Enrollment Completed Missing:`n  SWAYAM portal course enrollment counts will not be tracked.")
        }

        if (-not $hasCriticalMissing -and $missingCols.Count -gt 0) {
            $null = $warnLines.Add([char]0x2713 + " All 3 Critical Columns (Roll Number, Student Name, Receipt Link) are present and verified!")
        }

        if ($missingCols.Count -gt 0) {
            if ($panelWarn) { $panelWarn.Visibility = [System.Windows.Visibility]::Visible }
            if ($hasCriticalMissing) {
                if ($txtWarnTitle) {
                    $txtWarnTitle.Text = [char]0x26A0 + " CRITICAL COLUMN(S) MISSING - ACTION REQUIRED"
                    $txtWarnTitle.Foreground = $dangerBrush
                }
                if ($panelWarn) {
                    $panelWarn.BorderBrush = $dangerBrush
                    $panelWarn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#332015")
                }
                if ($txtHealth) {
                    $txtHealth.Text = "$($missingCols.Count) Column(s) Missing " + [char]0x26A0
                    $txtHealth.Foreground = $dangerBrush
                }
                if ($badgeHealth) { $badgeHealth.BorderBrush = $dangerBrush }
            } else {
                if ($txtWarnTitle) {
                    $txtWarnTitle.Text = [char]0x26A0 + " COLUMN ATTENTION & OPERATIONAL IMPACT"
                    $txtWarnTitle.Foreground = $accentBrush
                }
                if ($panelWarn) {
                    $panelWarn.BorderBrush = $accentBrush
                    $panelWarn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2A2215")
                }
                if ($txtHealth) {
                    $txtHealth.Text = "$($missingCols.Count) Column(s) Missing " + [char]0x26A0
                    $txtHealth.Foreground = $accentBrush
                }
                if ($badgeHealth) { $badgeHealth.BorderBrush = $accentBrush }
            }
            if ($txtWarnMsg) {
                $txtWarnMsg.Text = $warnLines -join "`n`n"
            }
        } else {
            if ($panelWarn) { $panelWarn.Visibility = [System.Windows.Visibility]::Collapsed }
            if ($txtHealth) {
                $txtHealth.Text = "7/7 Columns Detected " + [char]0x2713
                $txtHealth.Foreground = $sageBrush
            }
            if ($badgeHealth) { $badgeHealth.BorderBrush = $sageBrush }
        }

        # Summary Text
        $txtSummary = $s1View.FindName("TxtSheetAuditSummary")
        if ($txtSummary) {
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

            # Update on-disk receipt cache counter (Clean & Streamlined)
            $cleanCName = ($cName -replace '[\\/:*?"<>|]', '_').Trim()
            $rDir = Join-Path $dataDir "Courses\$cleanCName\receipts"
            $diskCount = 0
            if (Test-Path -LiteralPath $rDir) {
                $diskCount = @(Get-ChildItem -LiteralPath $rDir -Filter "*_receipt.*" -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 }).Count
            }
            $txtTitle = $s1View.FindName("TxtPipelineTitle")
            if ($txtTitle) { $txtTitle.Text = "Receipt Verification & OCR" }
            $txtPipe = $s1View.FindName("TxtPipelineStatus")
            if ($txtPipe) {
                $pct = if ($regCount -gt 0) { [math]::Round(($diskCount / $regCount) * 100) } else { 0 }
                $txtPipe.Text = "$diskCount of $regCount receipt(s) on disk ($pct%)"
            }
            $panelProg = $s1View.FindName("PanelPipelineProgress")
            if ($panelProg) { $panelProg.Visibility = [System.Windows.Visibility]::Collapsed }
        } else {
            if ($panelPrompt) { $panelPrompt.Visibility = [System.Windows.Visibility]::Visible }
            if ($panelActive) { $panelActive.Visibility = [System.Windows.Visibility]::Collapsed }
            if ($badgeVerSheet) { $badgeVerSheet.Visibility = [System.Windows.Visibility]::Collapsed }
        }
    }

    # -- Update Stage 2 View (Exam Results) --
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

    # -- Update Review View (if initialized) --
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
        $Course = $script:activeCourse,
        $Students = $null
    )
    if (-not $Course) { $Course = $script:activeCourse }
    if (-not $Course) { return }
    $rv = Get-OrCreateView "ReviewView"
    if (-not $rv) { return }

    if (-not $Students) {
        $store = Get-CourseStudentStore -CourseId $Course.Id -RegistrationSheet $Course.RegistrationSheet -CourseName $Course.Name
        $Students = @($store.Students)
    }

    if ($script:reviewSessionCourseId -ne $Course.Id) {
        $script:reviewSessionCourseId = $Course.Id
        $script:reviewSessionSolvedRolls.Clear()
        $script:reviewStagedSolved.Clear()
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

    # 2. Filter students
    $pendingStudents = [System.Collections.ArrayList]@()
    foreach ($st in $Students) {
        $stKey = if ($st.RollNo) { [string]$st.RollNo } else { [string]$st.Email }
        if ($script:reviewStagedSolved.ContainsKey($stKey)) {
            continue
        }
        if ($st.VerificationStatus -eq "Under Review") {
            $null = $pendingStudents.Add($st)
        }
    }

    # Queue row items: pending first, then staged solved students
    $displayStudents = [System.Collections.ArrayList]@()
    foreach ($st in $pendingStudents) { $null = $displayStudents.Add($st) }
    foreach ($entry in $script:reviewStagedSolved.Values) {
        if ($entry.Student) { $null = $displayStudents.Add($entry.Student) }
    }

    $pendingCount = $pendingStudents.Count
    $solvedSessionCount = $script:reviewSessionSolvedRolls.Count
    $totalIssuesCount = $pendingCount + $solvedSessionCount
    $stagedChangesCount = $script:reviewStagedSolved.Count

    # 3. Mini Dashboard Progress Metrics
    $txtTotal = $rv.FindName("TxtReviewTotalIssues")
    $txtSolved = $rv.FindName("TxtReviewSolvedCount")
    $txtPending = $rv.FindName("TxtReviewPendingCount")

    if ($txtTotal)   { $txtTotal.Text = $totalIssuesCount.ToString() }
    if ($txtSolved)  { $txtSolved.Text = $solvedSessionCount.ToString() }
    if ($txtPending) { $txtPending.Text = $pendingCount.ToString() }

    # 4. Header Count Badge
    $txtBadge = $rv.FindName("TxtReviewCountBadge")
    if ($txtBadge) {
        if ($pendingCount -gt 0) {
            $plural = if ($pendingCount -eq 1) { "1 Student Needs Review" } else { "$pendingCount Students Need Review" }
            $txtBadge.Text = $plural
            $txtBadge.Foreground = [System.Windows.Application]::Current.FindResource("AccentBrush")
        } else {
            $txtBadge.Text = "Queue is Clear"
            $txtBadge.Foreground = [System.Windows.Application]::Current.FindResource("SageBrush")
        }
    }

    # 5. Push Solved Changes Action Bar
    $btnPush = $rv.FindName("BtnPushSolvedChanges")
    $txtPushBadge = $rv.FindName("TxtPushChangesBadge")

    if ($btnPush) {
        $btnPush.IsEnabled = ($stagedChangesCount -gt 0)
    }
    if ($txtPushBadge) {
        if ($stagedChangesCount -gt 0) {
            $bullet = [char]0x25CF
            $plural = if ($stagedChangesCount -eq 1) { "1 change ready to push to main sheet" } else { "$stagedChangesCount changes ready to push to main sheet" }
            $txtPushBadge.Text = "$bullet $plural"
            $txtPushBadge.Foreground = [System.Windows.Application]::Current.FindResource("SageBrush")
        } else {
            if ($solvedSessionCount -gt 0) {
                $check = [char]0x2713
                $txtPushBadge.Text = "$check All session changes pushed to main sheet ($solvedSessionCount pushed)"
                $txtPushBadge.Foreground = [System.Windows.Application]::Current.FindResource("SageBrush")
            } else {
                $txtPushBadge.Text = "No pending changes in this session"
                $txtPushBadge.Foreground = [System.Windows.Application]::Current.FindResource("MutedBrush")
            }
        }
    }

    # 5b. Notify Flagged Students Action Button
    $btnNotify = $rv.FindName("BtnNotifyFlaggedStudents")
    if ($btnNotify) {
        $mailIcon = [char]0x2709
        if ($pendingCount -gt 0) {
            $plural = if ($pendingCount -eq 1) { "1 Student" } else { "$pendingCount Students" }
            $btnNotify.Content = "$mailIcon Send Email to Flagged ($plural)"
            $btnNotify.IsEnabled = $true
        } else {
            $btnNotify.Content = "$mailIcon Send Email to Flagged Students"
            $btnNotify.IsEnabled = $false
        }
    }

    # 6. Populate Review Rows Table
    $hostPanel = $rv.FindName("ReviewRowsHost")
    $emptyNotice = $rv.FindName("ReviewEmptyStateNotice")

    if ($hostPanel) {
        $hostPanel.Children.Clear()

        if ($displayStudents.Count -gt 0) {
            if ($emptyNotice) { $emptyNotice.Visibility = [System.Windows.Visibility]::Collapsed }

            foreach ($st in $displayStudents) {
                $stKey = if ($st.RollNo) { [string]$st.RollNo } else { [string]$st.Email }
                $isStaged = $script:reviewStagedSolved.ContainsKey($stKey)
                $isSolved = $script:reviewSessionSolvedRolls.Contains($stKey)

                $cardBorder = New-Object System.Windows.Controls.Border
                $cardBorder.Background = if ($isStaged) {
                    [System.Windows.Application]::Current.FindResource("PanelModBrush")
                } else {
                    [System.Windows.Application]::Current.FindResource("Panel2Brush")
                }
                $cardBorder.BorderBrush = if ($isStaged) {
                    [System.Windows.Application]::Current.FindResource("SageBrush")
                } else {
                    [System.Windows.Application]::Current.FindResource("BorderBrush")
                }
                $cardBorder.BorderThickness = New-Object System.Windows.Thickness(1)
                $cardBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
                $cardBorder.Padding = New-Object System.Windows.Thickness(14, 10, 14, 10)
                $cardBorder.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
                $cardBorder.Tag = $st

                $rowGrid = New-Object System.Windows.Controls.Grid
                $col0 = New-Object System.Windows.Controls.ColumnDefinition
                $col0.Width = New-Object System.Windows.GridLength(200)
                $col1 = New-Object System.Windows.Controls.ColumnDefinition
                $col1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                $col2 = New-Object System.Windows.Controls.ColumnDefinition
                $col2.Width = [System.Windows.GridLength]::Auto
                $null = $rowGrid.ColumnDefinitions.Add($col0)
                $null = $rowGrid.ColumnDefinitions.Add($col1)
                $null = $rowGrid.ColumnDefinitions.Add($col2)

                $remStr = if ($st.VerificationRemarks) { [string]$st.VerificationRemarks } else { "Flagged for manual verification review" }

                # Column 0: Enrollment (Roll Number)
                $txtRoll = New-Object System.Windows.Controls.TextBlock
                $txtRoll.Text = if ($st.RollNo) { [string]$st.RollNo } else { "No Roll No" }
                $txtRoll.FontFamily = New-Object System.Windows.Media.FontFamily("IBM Plex Mono, Consolas")
                $txtRoll.FontSize = 12
                $txtRoll.FontWeight = [System.Windows.FontWeights]::SemiBold
                $txtRoll.Foreground = [System.Windows.Application]::Current.FindResource("TextBrush")
                $txtRoll.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                [System.Windows.Controls.Grid]::SetColumn($txtRoll, 0)
                $null = $rowGrid.Children.Add($txtRoll)

                # Column 1: Student Name
                $txtName = New-Object System.Windows.Controls.TextBlock
                $txtName.Text = if ($st.Name) { [string]$st.Name } else { "Unnamed Student" }
                $txtName.FontSize = 12
                $txtName.FontWeight = [System.Windows.FontWeights]::Medium
                $txtName.Foreground = [System.Windows.Application]::Current.FindResource("TextBrush")
                $txtName.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $txtName.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
                $txtName.ToolTip = $remStr
                $txtName.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
                [System.Windows.Controls.Grid]::SetColumn($txtName, 1)
                $null = $rowGrid.Children.Add($txtName)

                # Column 2: Quick Actions Host (Width: Auto - Never clipped)
                $actionsPanel = New-Object System.Windows.Controls.StackPanel
                $actionsPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
                $actionsPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
                $actionsPanel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                [System.Windows.Controls.Grid]::SetColumn($actionsPanel, 2)

                if ($isStaged -or $isSolved) {
                    $pillBorder = New-Object System.Windows.Controls.Border
                    $pillBorder.Background = [System.Windows.Application]::Current.FindResource("SageTintBrush")
                    $pillBorder.BorderBrush = [System.Windows.Application]::Current.FindResource("SageBrush")
                    $pillBorder.BorderThickness = New-Object System.Windows.Thickness(1)
                    $pillBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
                    $pillBorder.Padding = New-Object System.Windows.Thickness(10, 5, 10, 5)
                    $pillBorder.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
                    $pillBorder.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

                    $pillTxt = New-Object System.Windows.Controls.TextBlock
                    $pillTxt.Text = "Solved"
                    $pillTxt.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI, IBM Plex Mono, Consolas")
                    $pillTxt.FontSize = 11
                    $pillTxt.FontWeight = [System.Windows.FontWeights]::SemiBold
                    $pillTxt.Foreground = [System.Windows.Application]::Current.FindResource("SageBrush")
                    $pillBorder.Child = $pillTxt
                    $null = $actionsPanel.Children.Add($pillBorder)
                }

                # Button 1: Issues (formerly Diagnostics)
                $btnIssues = New-Object System.Windows.Controls.Button
                $btnIssues.Content = "Issues"
                $btnIssues.Style = [System.Windows.Application]::Current.FindResource("BtnSecondary")
                $btnIssues.Padding = New-Object System.Windows.Thickness(10, 4, 10, 4)
                $btnIssues.FontSize = 11
                $btnIssues.Cursor = [System.Windows.Input.Cursors]::Hand
                $btnIssues.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
                $btnIssues.Tag = $st
                $btnIssues.ToolTip = "View flagged verification issues and discrepancy breakdown"
                $btnIssues.Add_Click({
                    $targetSt = $this.Tag
                    if (-not $targetSt) { return }
                    $stName = if ($targetSt.Name) { [string]$targetSt.Name } else { "Student" }
                    $stRoll = if ($targetSt.RollNo) { [string]$targetSt.RollNo } else { "No Roll No" }
                    $rem = if ($targetSt.VerificationRemarks) { [string]$targetSt.VerificationRemarks } else { "No specific issues logged." }

                    $issuesText = "STUDENT VERIFICATION ISSUES`n" +
                        "===========================`n`n" +
                        "Student : $stName`n" +
                        "Roll No : $stRoll`n" +
                        "Status  : $($targetSt.VerificationStatus)`n`n" +
                        "Flagged Discrepancies / Issues:`n" +
                        "$rem`n`n" +
                        "Available Actions:`n" +
                        "- [Receipt]      : View saved receipt file`n" +
                        "- [Approve]      : Quick-approve and stage for main sheet`n" +
                        "- [Open Student] : Open full split-screen inspection workspace"

                    [System.Windows.MessageBox]::Show(
                        $issuesText,
                        "Verification Issues - $stRoll",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    )
                })
                $null = $actionsPanel.Children.Add($btnIssues)

                # Button 2: Receipt
                $btnRec = New-Object System.Windows.Controls.Button
                $btnRec.Content = "Receipt"
                $btnRec.Style = [System.Windows.Application]::Current.FindResource("BtnSecondary")
                $btnRec.Padding = New-Object System.Windows.Thickness(10, 4, 10, 4)
                $btnRec.FontSize = 11
                $btnRec.Cursor = [System.Windows.Input.Cursors]::Hand
                $btnRec.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
                $btnRec.Tag = $st
                $btnRec.ToolTip = "Open saved receipt document in default viewer"
                $btnRec.Add_Click({
                    $targetSt = $this.Tag
                    if (-not $targetSt -or -not $script:activeCourse) { return }
                    $cleanRoll = if ($targetSt.RollNo) { ($targetSt.RollNo -replace '[\\/:*?"<>|]', '_').Trim() } else { "" }
                    $cName = if ($script:activeCourse.Name) { [string]$script:activeCourse.Name } else { "Default" }
                    $cleanCName = ($cName -replace '[\\/:*?"<>|]', '_').Trim()
                    $receiptsDir = Join-Path $script:appRoot "data\Courses\$cleanCName\receipts"

                    $foundFile = $null
                    if ($cleanRoll -and (Test-Path -LiteralPath $receiptsDir)) {
                        $allFiles = @(Get-ChildItem -LiteralPath $receiptsDir -ErrorAction SilentlyContinue | Where-Object {
                            $_.Name -like "${cleanRoll}_receipt.*" -and $_.Length -gt 0
                        })
                        if ($allFiles.Count -gt 0) {
                            $foundFile = ($allFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
                        }
                    }

                    if ($foundFile -and (Test-Path -LiteralPath $foundFile)) {
                        try {
                            [System.Diagnostics.Process]::Start([System.Diagnostics.ProcessStartInfo]@{
                                FileName = $foundFile
                                UseShellExecute = $true
                            }) | Out-Null
                        } catch {
                            [System.Windows.MessageBox]::Show("Unable to open receipt file:`n$_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                        }
                    } else {
                        [System.Windows.MessageBox]::Show(
                            "No saved receipt file found on disk for $($targetSt.Name) ($($targetSt.RollNo)).`n`nPlease click [Open Student] to download or attach a receipt.",
                            "Receipt Not Found",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Warning
                        )
                    }
                })
                $null = $actionsPanel.Children.Add($btnRec)

                # Button 3: Approve / Unapprove Toggle
                if ($isStaged) {
                    $btnUnapprove = New-Object System.Windows.Controls.Button
                    $btnUnapprove.Content = "Unapprove"
                    $btnUnapprove.Style = [System.Windows.Application]::Current.FindResource("BtnSecondary")
                    $btnUnapprove.BorderBrush = [System.Windows.Application]::Current.FindResource("DangerBrush")
                    $btnUnapprove.Foreground = [System.Windows.Application]::Current.FindResource("DangerBrush")
                    $btnUnapprove.Padding = New-Object System.Windows.Thickness(10, 4, 10, 4)
                    $btnUnapprove.FontSize = 11
                    $btnUnapprove.Cursor = [System.Windows.Input.Cursors]::Hand
                    $btnUnapprove.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
                    $btnUnapprove.Tag = $st
                    $btnUnapprove.ToolTip = "Revert staged approval back to Under Review"
                    $btnUnapprove.Add_Click({
                        $targetSt = $this.Tag
                        if (-not $targetSt -or -not $script:activeCourse) { return }
                        $stName = if ($targetSt.Name) { [string]$targetSt.Name } else { "this student" }
                        $stRoll = if ($targetSt.RollNo) { [string]$targetSt.RollNo } else { "No Roll No" }

                        $confirm = [System.Windows.MessageBox]::Show(
                            "Revert approval for:`n`nName: $stName`nRoll No: $stRoll`n`nStatus will be reverted to 'Under Review' and un-staged.",
                            "Unapprove Student",
                            [System.Windows.MessageBoxButton]::YesNo,
                            [System.Windows.MessageBoxImage]::Question
                        )
                        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

                        $targetKey = if ($targetSt.RollNo) { [string]$targetSt.RollNo } else { [string]$targetSt.Email }

                        $origStatus = "Under Review"
                        $origRemarks = ""
                        if ($script:reviewStagedSolved.ContainsKey($targetKey)) {
                            $stagedEntry = $script:reviewStagedSolved[$targetKey]
                            if ($stagedEntry.OriginalStatus) { $origStatus = [string]$stagedEntry.OriginalStatus }
                            if ($stagedEntry.OriginalRemarks -ne $null) { $origRemarks = [string]$stagedEntry.OriginalRemarks }
                            $null = $script:reviewStagedSolved.Remove($targetKey)
                        }

                        $targetSt.VerificationStatus = $origStatus
                        $targetSt.VerificationRemarks = $origRemarks

                        if ($script:reviewSessionSolvedRolls.Contains($targetKey)) {
                            $null = $script:reviewSessionSolvedRolls.Remove($targetKey)
                        }

                        Update-ReviewView -Course $script:activeCourse
                    })
                    $null = $actionsPanel.Children.Add($btnUnapprove)
                } elseif (-not $isSolved) {
                    $btnApprove = New-Object System.Windows.Controls.Button
                    $btnApprove.Content = "Approve"
                    $btnApprove.Style = [System.Windows.Application]::Current.FindResource("BtnPrimary")
                    $btnApprove.Background = [System.Windows.Application]::Current.FindResource("SageBrush")
                    $btnApprove.Foreground = [System.Windows.Application]::Current.FindResource("BgBrush")
                    $btnApprove.Padding = New-Object System.Windows.Thickness(10, 4, 10, 4)
                    $btnApprove.FontSize = 11
                    $btnApprove.Cursor = [System.Windows.Input.Cursors]::Hand
                    $btnApprove.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
                    $btnApprove.Tag = $st
                    $btnApprove.ToolTip = "Quick-approve student verification and stage for main sheet push"
                    $btnApprove.Add_Click({
                        $targetSt = $this.Tag
                        if (-not $targetSt -or -not $script:activeCourse) { return }
                        $stName = if ($targetSt.Name) { [string]$targetSt.Name } else { "this student" }
                        $stRoll = if ($targetSt.RollNo) { [string]$targetSt.RollNo } else { "No Roll No" }

                        $confirm = [System.Windows.MessageBox]::Show(
                            "Quick-approve verification for:`n`nName: $stName`nRoll No: $stRoll`n`nStatus will be changed to 'Verified' and staged to push to the main sheet.",
                            "Quick Approve Student",
                            [System.Windows.MessageBoxButton]::YesNo,
                            [System.Windows.MessageBoxImage]::Question
                        )
                        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

                        $targetKey = if ($targetSt.RollNo) { [string]$targetSt.RollNo } else { [string]$targetSt.Email }
                        $origStatus = if ($targetSt.VerificationStatus -and $targetSt.VerificationStatus -ne "Verified") { [string]$targetSt.VerificationStatus } else { "Under Review" }
                        $origRemarks = if ($targetSt.VerificationRemarks) { [string]$targetSt.VerificationRemarks } else { "" }

                        $nowStr = (Get-Date).ToString("dd/MM/yyyy HH:mm")
                        $newRem = "Manually approved by coordinator on $nowStr"

                        $targetSt.VerificationStatus = "Verified"
                        $targetSt.VerificationRemarks = $newRem

                        $null = $script:reviewSessionSolvedRolls.Add($targetKey)
                        $script:reviewStagedSolved[$targetKey] = @{
                            Student         = $targetSt
                            RollNo          = $targetSt.RollNo
                            Email           = $targetSt.Email
                            NewStatus       = "Verified"
                            NewRemarks      = $newRem
                            OriginalStatus  = $origStatus
                            OriginalRemarks = $origRemarks
                        }

                        Update-ReviewView -Course $script:activeCourse
                    })
                    $null = $actionsPanel.Children.Add($btnApprove)
                }

                # Button 4: Open Student
                $btnOpen = New-Object System.Windows.Controls.Button
                $btnOpen.Content = "Open Student"
                $btnOpen.Style = [System.Windows.Application]::Current.FindResource("BtnSecondary")
                $btnOpen.BorderBrush = [System.Windows.Application]::Current.FindResource("AccentBrush")
                $btnOpen.Foreground = [System.Windows.Application]::Current.FindResource("AccentBrush")
                $btnOpen.Padding = New-Object System.Windows.Thickness(12, 4, 12, 4)
                $btnOpen.FontSize = 11
                $btnOpen.FontWeight = [System.Windows.FontWeights]::SemiBold
                $btnOpen.Cursor = [System.Windows.Input.Cursors]::Hand
                $btnOpen.Tag = $st
                $btnOpen.ToolTip = "Open full split-screen inspection workspace for this student"
                $btnOpen.Add_Click({
                    $targetSt = $this.Tag
                    if (-not $targetSt) { return }
                    $rView = $script:views["ReviewView"]
                    if (-not $rView) { return }

                    $panelOverview = $rView.FindName("ReviewQueueOverviewPanel")
                    $panelDetail = $rView.FindName("ReviewStudentDetailPanel")

                    if ($panelOverview) { $panelOverview.Visibility = [System.Windows.Visibility]::Collapsed }
                    if ($panelDetail) { $panelDetail.Visibility = [System.Windows.Visibility]::Visible }

                    Show-StudentReviewDetails -Student $targetSt
                })
                $null = $actionsPanel.Children.Add($btnOpen)

                $null = $rowGrid.Children.Add($actionsPanel)
                $cardBorder.Child = $rowGrid
                $null = $hostPanel.Children.Add($cardBorder)
            }
        } else {
            if ($emptyNotice) { $emptyNotice.Visibility = [System.Windows.Visibility]::Visible }
        }
    }
}

function Show-StudentReviewDetails {
    param(
        $Student
    )
    if (-not $Student) { return }
    $rv = Get-OrCreateView "ReviewView"
    if (-not $rv) { return }

    # Toggle View State: Mode B (Detail) active, Mode A (Queue Overview) hidden
    $panelOverview = $rv.FindName("ReviewQueueOverviewPanel")
    $panelDetail = $rv.FindName("ReviewStudentDetailPanel")
    if ($panelOverview) { $panelOverview.Visibility = [System.Windows.Visibility]::Collapsed }
    if ($panelDetail) { $panelDetail.Visibility = [System.Windows.Visibility]::Visible }

    $workspace = $rv.FindName("ReviewWorkspaceGrid")
    if ($workspace) { $workspace.Visibility = [System.Windows.Visibility]::Visible }

    # 3. Populate Header & Identity
    $txtName = $rv.FindName("TxtReviewStudentName")
    $txtRoll = $rv.FindName("TxtReviewStudentRoll")
    $txtStatus = $rv.FindName("TxtReviewStatus")
    $badgeStatus = $rv.FindName("BadgeReviewStatus")

    if ($txtName) { $txtName.Text = if ($Student.Name) { [string]$Student.Name } else { "Unnamed Student" } }
    if ($txtRoll) { $txtRoll.Text = if ($Student.RollNo) { "Roll No: $($Student.RollNo)" } else { "Roll No: Not Assigned" } }
    if ($txtStatus) {
        $stVal = if ($Student.VerificationStatus) { [string]$Student.VerificationStatus } else { "UNDER REVIEW" }
        $txtStatus.Text = $stVal.ToUpper()
        if ($badgeStatus) {
            if ($stVal -eq "Verified") {
                $badgeStatus.BorderBrush = [System.Windows.Application]::Current.FindResource("SageBrush")
                $badgeStatus.Background = [System.Windows.Application]::Current.FindResource("SageTintBrush")
                $txtStatus.Foreground = [System.Windows.Application]::Current.FindResource("SageBrush")
            } else {
                $badgeStatus.BorderBrush = [System.Windows.Application]::Current.FindResource("AccentBrush")
                $badgeStatus.Background = [System.Windows.Application]::Current.FindResource("AccentTintBrush")
                $txtStatus.Foreground = [System.Windows.Application]::Current.FindResource("AccentBrush")
            }
        }
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

    # Store currently selected student on the workspace and reset details scroll
    $workspace.Tag = $Student
    $detailsScroll = $rv.FindName("ReviewDetailsScrollViewer")
    if ($detailsScroll) { $detailsScroll.ScrollToTop() }

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
    $btnApprove = $rv.FindName("BtnApproveOverride")
    if ($btnApprove) { $btnApprove.Tag = $Student }
    $btnAttach = $rv.FindName("BtnAttachLocalReceipt")
    if ($btnAttach) { $btnAttach.Tag = $Student }

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
        $dDir = if ($script:dataDir) { $script:dataDir } else { (Join-Path $script:appRoot "data") }
        $receiptsDir = Get-CourseReceiptsDirectory -CourseId $script:activeCourse.Id -CourseName $cName -DataDir $dDir

        $cleanRoll = (($Student.RollNo) -replace '[\\/:*?"<>|]', '_').Trim()
        if (Test-Path -LiteralPath $receiptsDir) {
            $allFiles = @(Get-ChildItem -LiteralPath $receiptsDir -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -like "${cleanRoll}_receipt.*" -and $_.Length -gt 0
            })
            if ($allFiles.Count -gt 0) {
                # Pick the newest receipt file if multiple extensions exist
                $matchedFile = ($allFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
                $receiptFound = $true
                $receiptPath = $matchedFile.FullName

                $ext = $matchedFile.Extension.ToLower()
                if ($ext -eq ".pdf") {
                    $expectedPng = Join-Path $receiptsDir "${cleanRoll}_receipt_page1.png"
                    if (Test-Path -LiteralPath $expectedPng) {
                        $displayImgPath = $expectedPng
                    } else {
                        try {
                            $displayImgPath = ConvertTo-ReceiptImage -FilePath $receiptPath
                        } catch {
                            $displayImgPath = $null
                        }
                    }
                } elseif ($ext -in @('.png', '.jpg', '.jpeg', '.bmp', '.webp')) {
                    $displayImgPath = $receiptPath
                }
            }
        }
    }

    if ($receiptFound -and $displayImgPath -and (Test-Path -LiteralPath $displayImgPath)) {
        try {
            # Release any previous image binding in WPF
            if ($imgReceipt) { $imgReceipt.Source = $null }

            # Read into memory stream to eliminate OS file locks and bypass WPF URI cache
            $rawImgBytes = [System.IO.File]::ReadAllBytes($displayImgPath)
            $memStream = New-Object System.IO.MemoryStream( ,$rawImgBytes )
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit()
            $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.StreamSource = $memStream
            $bmp.EndInit()
            $bmp.Freeze()
            $memStream.Close()
            $memStream.Dispose()

            if ($imgReceipt) { $imgReceipt.Source = $bmp }
            if ($scrollViewer) { $scrollViewer.Visibility = [System.Windows.Visibility]::Visible }
            if ($missingPanel) { $missingPanel.Visibility = [System.Windows.Visibility]::Collapsed }

            if ($txtBadge) {
                $extName = [System.IO.Path]::GetExtension($receiptPath).TrimStart('.').ToUpper()
                $txtBadge.Text = "Saved ($extName)"
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
            $txtBadge.Text = "Not Saved"
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
    if ($rv) {
        $panelOverview = $rv.FindName("ReviewQueueOverviewPanel")
        $panelDetail = $rv.FindName("ReviewStudentDetailPanel")
        if ($panelOverview) { $panelOverview.Visibility = [System.Windows.Visibility]::Visible }
        if ($panelDetail) { $panelDetail.Visibility = [System.Windows.Visibility]::Collapsed }
    }
    Update-ReviewView -Course $script:activeCourse
    Navigate-To "ReviewView"
}

# =====================================================================
# Branch 4: Email Management Center Helpers
# =====================================================================
$script:emailCurrentTemplate = "StandardTemplate"

function Open-EmailView {
    if (-not $script:activeCourse) { return }
    $null = Get-OrCreateView "EmailView"
    Update-EmailView -Course $script:activeCourse
    Navigate-To "EmailView"
}

function Get-SelectedStudents {
    $selected = [System.Collections.Generic.List[PSCustomObject]]::new()
    $ev = if ($script:views) { $script:views["EmailView"] } else { $null }
    if (-not $ev) { return $selected }

    $hostP = $ev.FindName("EmailRecipientsHost")
    if (-not $hostP) { return $selected }

    foreach ($card in $hostP.Children) {
        $grid = $card.Child
        if ($grid -and $grid.Children.Count -gt 0) {
            $chk = $grid.Children[0]
            if ($chk -is [System.Windows.Controls.CheckBox] -and $chk.IsChecked -eq $true) {
                $st = $chk.Tag
                if ($st) {
                    $selected.Add($st)
                }
            }
        }
    }
    return $selected
}

function Get-SelectedEmailRecipients {
    $emails = [System.Collections.Generic.List[string]]::new()
    $selected = Get-SelectedStudents
    foreach ($st in $selected) {
        if ($st.Email -and [string]$st.Email.Trim()) {
            $emails.Add([string]$st.Email.Trim())
        }
    }
    return $emails
}

function Update-EmailSelectionMetrics {
    $ev = if ($script:views) { $script:views["EmailView"] } else { $null }
    if (-not $ev) { return }

    $emails = Get-SelectedEmailRecipients
    $txtBadge = $ev.FindName("TxtEmailHeaderBadge")
    if ($txtBadge) {
        $count = $emails.Count
        $plural = if ($count -eq 1) { "1 Selected" } else { "$count Selected" }
        $txtBadge.Text = $plural
    }

    $btnLaunch = $ev.FindName("BtnLaunchGmailDraft")
    $btnCopyBcc = $ev.FindName("BtnCopyBccEmails")
    $hasSelected = ($emails.Count -gt 0)
    if ($btnLaunch) { $btnLaunch.IsEnabled = $hasSelected }
    if ($btnCopyBcc) { $btnCopyBcc.IsEnabled = $hasSelected }
}

function Update-EmailComposerPreview {
    $ev = if ($script:views) { $script:views["EmailView"] } else { $null }
    if (-not $ev -or -not $script:activeCourse) { return }

    $cName = if ($script:activeCourse.Name) { [string]$script:activeCourse.Name } else { "NPTEL Course" }
    $cDept = if ($script:activeCourse.Department) { [string]$script:activeCourse.Department } else { "" }
    $cSem  = if ($script:activeCourse.Semester) { [string]$script:activeCourse.Semester } else { "" }

    $deptStr = if ($cDept) { "$cDept Department" } else { "Department Coordinator" }
    $semStr  = if ($cSem) { " - Semester $cSem" } else { "" }

    $txtSubject = $ev.FindName("TxtEmailSubject")
    $txtBody = $ev.FindName("TxtEmailBodyPreview")
    $tpl = if ($script:emailCurrentTemplate) { $script:emailCurrentTemplate } else { "StandardTemplate" }

    switch ($tpl) {
        "CustomDraft" {
            if ($txtSubject) {
                $txtSubject.Text = "[URGENT] Notice Regarding NPTEL Examination Verification - $cName"
            }
            if ($txtBody) {
                $txtBody.Text = "Dear Students,`n`nThis is an official notice regarding your NPTEL exam registration for course `"$cName`".`n`n[Type your custom instructions, Google Form resubmission link, or lab verification schedule here]`n`nDEADLINE:`nPlease complete the required action within 48 hours of this notice.`n`nRegards,`nNPTEL Local Chapter / Course Coordinator`n$deptStr$semStr"
            }
        }
        default {
            # Standard Rule-Based Template (5 Rules Checklist & Resubmission Guidelines)
            if ($txtSubject) {
                $txtSubject.Text = "[ACTION REQUIRED] NPTEL Exam Registration Receipt Verification Failed - $cName"
            }
            if ($txtBody) {
                $txtBody.Text = "Dear Student,`n`nDuring the institutional verification of NPTEL exam registrations for course `"$cName`", your submitted proof of registration could not be verified and has been marked as UNDER REVIEW.`n`nTo ensure your examination registration is approved and credited by the college, you are required to resubmit a valid, official payment receipt that satisfies ALL of the following criteria:`n`nMANDATORY RECEIPT REQUIREMENTS:`n1. Payment Status: Must clearly show `"Payment Successful`" or `"Transaction Complete`".`n2. Fee Amount: Must clearly display Rs. 1,000 (or Rs. 500 for approved SC/ST/PwD concession).`n3. Course Title: Must match `"$cName`" exactly.`n4. Platform Authenticity: Must be an official NPTEL / SWAYAM / Razorpay generated receipt (UPI debit SMS or banking app screenshots are NOT accepted).`n5. Student Identity: Must clearly show your Name, Roll Number, or Application Number matching college records.`n`nCOMMON REASONS FOR REJECTION:`n- Uploading course enrollment screenshot instead of exam registration payment receipt.`n- UPI / Google Pay / PhonePe transaction debit screenshot without course details.`n- Receipt of a different course or incomplete cropped screenshot.`n- Drive link permission set to `"Restricted`" / Access Denied.`n`nHOW TO RESUBMIT:`nPlease reply directly to this email with a clear PDF or readable image of your official receipt, or submit it to your departmental coordinator.`n`nDEADLINE FOR RESUBMISSION:`nWithin 48 hours of this notice. Failure to resubmit will result in your registration remaining unverified.`n`nRegards,`nNPTEL Local Chapter / Course Coordinator`n$deptStr$semStr"
            }
        }
    }
}

function Set-EmailTemplate {
    param([string]$TplName)
    $script:emailCurrentTemplate = $TplName
    $ev = if ($script:views) { $script:views["EmailView"] } else { $null }
    if (-not $ev) { return }

    $bStandard = $ev.FindName("BtnTplStandardRuleNotice")
    $bCustom   = $ev.FindName("BtnTplCustomDraft")

    $actStyle = [System.Windows.Application]::Current.FindResource("BtnNavActive")
    $defStyle = [System.Windows.Application]::Current.FindResource("BtnNav")

    if ($bStandard) { $bStandard.Style = if ($TplName -eq "StandardTemplate") { $actStyle } else { $defStyle } }
    if ($bCustom)   { $bCustom.Style   = if ($TplName -eq "CustomDraft")      { $actStyle } else { $defStyle } }

    Update-EmailComposerPreview
}

function Mark-SelectedStudentsNotified {
    param($SelectedStudents)
    if (-not $SelectedStudents -or $SelectedStudents.Count -eq 0 -or -not $script:activeCourse) { return }

    $cName = if ($script:activeCourse.Name) { [string]$script:activeCourse.Name } else { "Course" }
    $store = Get-CourseStudentStore -CourseId $script:activeCourse.Id -RegistrationSheet $script:activeCourse.RegistrationSheet -CourseName $cName
    $students = [System.Collections.ArrayList]@($store.Students)

    $nowStr = (Get-Date).ToString("yyyy-MM-dd HH:mm")
    $matched = 0

    # Build unique lookup keys for selected students using RollNo (or Email fallback)
    $selectedRolls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $selectedEmails = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($sel in $SelectedStudents) {
        if ($sel -is [string]) {
            # Backward compatibility if an email string was passed
            $null = $selectedEmails.Add($sel.Trim())
        } else {
            if ($sel.RollNo -and [string]$sel.RollNo.Trim()) {
                $null = $selectedRolls.Add([string]$sel.RollNo.Trim())
            } elseif ($sel.Email -and [string]$sel.Email.Trim()) {
                $null = $selectedEmails.Add([string]$sel.Email.Trim())
            }
        }
    }

    foreach ($s in $students) {
        # Only mark students who are actually Under Review (flagged)
        if ($s.VerificationStatus -ne "Under Review") { continue }

        $match = $false
        if ($s.RollNo -and [string]$s.RollNo.Trim() -and $selectedRolls.Contains([string]$s.RollNo.Trim())) {
            $match = $true
        } elseif ($s.Email -and [string]$s.Email.Trim() -and $selectedEmails.Contains([string]$s.Email.Trim())) {
            $match = $true
        }

        if ($match) {
            $s | Add-Member -NotePropertyName "Notified" -NotePropertyValue $true -Force
            $s | Add-Member -NotePropertyName "NotifiedTimestamp" -NotePropertyValue $nowStr -Force
            $matched++
        }
    }

    if ($matched -gt 0) {
        Save-CourseStudents -CourseId $script:activeCourse.Id -Students $students -ColumnMap $store.ColumnMap -CourseName $cName
        Update-EmailView -Course $script:activeCourse
    }
    return $matched
}

function Unmark-SelectedStudentsNotified {
    param($SelectedStudents)
    if (-not $SelectedStudents -or $SelectedStudents.Count -eq 0 -or -not $script:activeCourse) { return 0 }

    $cName = if ($script:activeCourse.Name) { [string]$script:activeCourse.Name } else { "Course" }
    $store = Get-CourseStudentStore -CourseId $script:activeCourse.Id -RegistrationSheet $script:activeCourse.RegistrationSheet -CourseName $cName
    $students = [System.Collections.ArrayList]@($store.Students)

    $matched = 0

    # Build unique lookup keys for selected students using RollNo (or Email fallback)
    $selectedRolls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $selectedEmails = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($sel in $SelectedStudents) {
        if ($sel -is [string]) {
            $null = $selectedEmails.Add($sel.Trim())
        } else {
            if ($sel.RollNo -and [string]$sel.RollNo.Trim()) {
                $null = $selectedRolls.Add([string]$sel.RollNo.Trim())
            } elseif ($sel.Email -and [string]$sel.Email.Trim()) {
                $null = $selectedEmails.Add([string]$sel.Email.Trim())
            }
        }
    }

    foreach ($s in $students) {
        if ($s.VerificationStatus -ne "Under Review") { continue }

        $match = $false
        if ($s.RollNo -and [string]$s.RollNo.Trim() -and $selectedRolls.Contains([string]$s.RollNo.Trim())) {
            $match = $true
        } elseif ($s.Email -and [string]$s.Email.Trim() -and $selectedEmails.Contains([string]$s.Email.Trim())) {
            $match = $true
        }

        if ($match) {
            $s | Add-Member -NotePropertyName "Notified" -NotePropertyValue $false -Force
            $s | Add-Member -NotePropertyName "NotifiedTimestamp" -NotePropertyValue $null -Force
            $matched++
        }
    }

    if ($matched -gt 0) {
        Save-CourseStudents -CourseId $script:activeCourse.Id -Students $students -ColumnMap $store.ColumnMap -CourseName $cName
        Update-EmailView -Course $script:activeCourse
    }
    return $matched
}

function Update-EmailView {
    param(
        $Course = $script:activeCourse
    )
    if (-not $Course) { $Course = $script:activeCourse }
    if (-not $Course) { return }

    $ev = Get-OrCreateView "EmailView"
    if (-not $ev) { return }

    $cName = if ($Course.Name) { [string]$Course.Name } else { "Untitled Course" }
    $cCode = if ($Course.Code) { [string]$Course.Code } else { "" }

    # 1. Breadcrumb
    $txtBreadcrumb = $ev.FindName("TxtEmailBreadcrumb")
    if ($txtBreadcrumb) {
        $codeStr = if ($cCode) { " ($cCode)" } else { "" }
        $upperName = $cName.ToUpper()
        $txtBreadcrumb.Text = "COURSES > $upperName$codeStr > EMAIL OUTREACH"
    }

    # 2. Retrieve store & students
    $store = Get-CourseStudentStore -CourseId $Course.Id -RegistrationSheet $Course.RegistrationSheet -CourseName $Course.Name
    $allStudents = @($store.Students)
    $flagged = @($allStudents | Where-Object { $_.VerificationStatus -eq "Under Review" })

    # 3. Mini Dashboard Metrics
    $txtQueued = $ev.FindName("TxtEmailQueuedCount")
    $txtNotified = $ev.FindName("TxtEmailNotifiedCount")
    $txtSummary = $ev.FindName("TxtEmailIssuesSummary")

    $notifiedCount = @($flagged | Where-Object { $_.Notified -eq $true }).Count
    if ($txtQueued) { $txtQueued.Text = $flagged.Count.ToString() }
    if ($txtNotified) { $txtNotified.Text = $notifiedCount.ToString() }

    # Summarize discrepancies
    $missingReceiptCount = @($flagged | Where-Object {
        $r = [string]$_.VerificationRemarks
        $r -like "*Missing*" -or $r -like "*No proof*" -or $r -like "*Not Found*" -or -not $_.ProofUrl
    }).Count
    $feeMismatchCount = @($flagged | Where-Object {
        $r = [string]$_.VerificationRemarks
        $r -like "*Fee*" -or $r -like "*Amount*" -or $r -like "*₹*"
    }).Count

    if ($txtSummary) {
        $bullet = [char]0x2022
        if ($flagged.Count -eq 0) {
            $txtSummary.Text = "No issues detected"
        } else {
            $txtSummary.Text = "$missingReceiptCount Missing Receipt $bullet $feeMismatchCount Fee Discrepancy"
        }
    }

    # 4. Populate Recipient List
    $hostPanel = $ev.FindName("EmailRecipientsHost")
    $emptyNotice = $ev.FindName("EmailEmptyStateNotice")

    if ($hostPanel) {
        $hostPanel.Children.Clear()

        if ($flagged.Count -gt 0) {
            if ($emptyNotice) { $emptyNotice.Visibility = [System.Windows.Visibility]::Collapsed }

            $panelBrush = [System.Windows.Application]::Current.FindResource("Panel2Brush")
            $borderBrush = [System.Windows.Application]::Current.FindResource("BorderBrush")
            $textBrush = [System.Windows.Application]::Current.FindResource("TextBrush")
            $mutedBrush = [System.Windows.Application]::Current.FindResource("MutedBrush")
            $dangerBrush = [System.Windows.Application]::Current.FindResource("DangerBrush")
            $sageBrush = [System.Windows.Application]::Current.FindResource("SageBrush")
            $dangerTint = [System.Windows.Application]::Current.FindResource("DangerTintBrush")
            $sageTint = [System.Windows.Application]::Current.FindResource("SageTintBrush")

            foreach ($st in $flagged) {
                $card = New-Object System.Windows.Controls.Border
                $card.Background = $panelBrush
                $card.BorderBrush = $borderBrush
                $card.BorderThickness = New-Object System.Windows.Thickness(1)
                $card.CornerRadius = New-Object System.Windows.CornerRadius(6)
                $card.Padding = New-Object System.Windows.Thickness(12, 10, 12, 10)
                $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)

                $rowGrid = New-Object System.Windows.Controls.Grid
                $col0 = New-Object System.Windows.Controls.ColumnDefinition
                $col0.Width = New-Object System.Windows.GridLength(28, [System.Windows.GridUnitType]::Pixel)
                $col1 = New-Object System.Windows.Controls.ColumnDefinition
                $col1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                $null = $rowGrid.ColumnDefinitions.Add($col0)
                $null = $rowGrid.ColumnDefinitions.Add($col1)

                # Checkbox
                $chk = New-Object System.Windows.Controls.CheckBox
                $chk.IsChecked = $true
                $chk.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
                $chk.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
                $chk.Tag = $st
                $chk.Add_Checked({ Update-EmailSelectionMetrics })
                $chk.Add_Unchecked({ Update-EmailSelectionMetrics })
                [System.Windows.Controls.Grid]::SetColumn($chk, 0)
                $null = $rowGrid.Children.Add($chk)

                # Details Stack
                $detailStack = New-Object System.Windows.Controls.StackPanel
                [System.Windows.Controls.Grid]::SetColumn($detailStack, 1)

                # Name & Roll
                $nameGrid = New-Object System.Windows.Controls.Grid
                $cLeft = New-Object System.Windows.Controls.ColumnDefinition
                $cLeft.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
                $cRight = New-Object System.Windows.Controls.ColumnDefinition
                $cRight.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
                $null = $nameGrid.ColumnDefinitions.Add($cLeft)
                $null = $nameGrid.ColumnDefinitions.Add($cRight)

                $stName = if ($st.Name) { [string]$st.Name } else { "Unnamed Student" }
                $stRoll = if ($st.RollNo) { [string]$st.RollNo } else { "-" }

                $txtName = New-Object System.Windows.Controls.TextBlock
                $txtName.Text = $stName
                $txtName.FontWeight = [System.Windows.FontWeights]::SemiBold
                $txtName.FontSize = 13
                $txtName.Foreground = $textBrush
                [System.Windows.Controls.Grid]::SetColumn($txtName, 0)
                $null = $nameGrid.Children.Add($txtName)

                $txtRoll = New-Object System.Windows.Controls.TextBlock
                $txtRoll.Text = $stRoll
                $txtRoll.FontFamily = New-Object System.Windows.Media.FontFamily("IBM Plex Mono, Consolas")
                $txtRoll.FontSize = 11
                $txtRoll.Foreground = $mutedBrush
                [System.Windows.Controls.Grid]::SetColumn($txtRoll, 1)
                $null = $nameGrid.Children.Add($txtRoll)
                $null = $detailStack.Children.Add($nameGrid)

                # Email
                $stEmail = if ($st.Email) { [string]$st.Email } else { "No email listed" }
                $txtEmail = New-Object System.Windows.Controls.TextBlock
                $txtEmail.Text = $stEmail
                $txtEmail.FontFamily = New-Object System.Windows.Media.FontFamily("IBM Plex Mono, Consolas")
                $txtEmail.FontSize = 11
                $txtEmail.Foreground = $mutedBrush
                $txtEmail.Margin = New-Object System.Windows.Thickness(0, 2, 0, 4)
                $null = $detailStack.Children.Add($txtEmail)

                # Remarks / Discrepancy Pill
                $remarks = if ($st.VerificationRemarks) { [string]$st.VerificationRemarks } else { "Flagged under review" }
                $pillBorder = New-Object System.Windows.Controls.Border
                $pillBorder.Background = $dangerTint
                $pillBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
                $pillBorder.Padding = New-Object System.Windows.Thickness(6, 2, 6, 2)
                $pillBorder.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
                $pillBorder.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)

                $txtPill = New-Object System.Windows.Controls.TextBlock
                $txtPill.Text = $remarks
                $txtPill.FontSize = 10
                $txtPill.FontWeight = [System.Windows.FontWeights]::SemiBold
                $txtPill.Foreground = $dangerBrush
                $pillBorder.Child = $txtPill
                $null = $detailStack.Children.Add($pillBorder)

                # Notification Status indicator
                if ($st.Notified -eq $true) {
                    $notifPill = New-Object System.Windows.Controls.Border
                    $notifPill.Background = $sageTint
                    $notifPill.CornerRadius = New-Object System.Windows.CornerRadius(4)
                    $notifPill.Padding = New-Object System.Windows.Thickness(6, 2, 6, 2)
                    $notifPill.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left

                    $checkIcon = [char]0x2713
                    $txtNotif = New-Object System.Windows.Controls.TextBlock
                    $timeStr = if ($st.NotifiedTimestamp) { " ($($st.NotifiedTimestamp))" } else { "" }
                    $txtNotif.Text = "$checkIcon Notified$timeStr"
                    $txtNotif.FontSize = 10
                    $txtNotif.FontWeight = [System.Windows.FontWeights]::SemiBold
                    $txtNotif.Foreground = $sageBrush
                    $notifPill.Child = $txtNotif
                    $null = $detailStack.Children.Add($notifPill)
                }

                $null = $rowGrid.Children.Add($detailStack)
                $card.Child = $rowGrid
                $null = $hostPanel.Children.Add($card)
            }
        } else {
            if ($emptyNotice) { $emptyNotice.Visibility = [System.Windows.Visibility]::Visible }
        }
    }

    # 5. Refresh composer preview & selection metrics
    Set-EmailTemplate $script:emailCurrentTemplate
    Update-EmailSelectionMetrics
}

# Dynamic Pipeline Progress State Manager (Script Scope)
function Update-PipelineBarState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        [int]$Current = 0,
        [int]$Total = 0,
        [string]$ItemText = "",
        [string]$Headline = ""
    )

    $s1 = if ($script:views) { $script:views["Stage1View"] } else { $null }
    if (-not $s1) { return }

    $panelProg  = $s1.FindName("PanelPipelineProgress")
    $txtTitle   = $s1.FindName("TxtPipelineTitle")
    $txtStatus  = $s1.FindName("TxtPipelineStatus")
    $txtHead    = $s1.FindName("TxtProgressHeadline")
    $txtCounter = $s1.FindName("TxtProgressCounter")
    $txtDetail  = $s1.FindName("TxtProgressDetail")
    $pBar       = $s1.FindName("ProgressBarPipeline")

    $btnImport   = $s1.FindName("BtnImportReceipts")
    $btnDownload = $s1.FindName("BtnDownloadReceipts")
    $btnVerify   = $s1.FindName("BtnVerifyAll")

    switch ($Mode) {
        'Idle' {
            if ($panelProg) { $panelProg.Visibility = [System.Windows.Visibility]::Collapsed }
            if ($txtTitle) { $txtTitle.Text = "Receipt Verification & OCR" }
            if ($btnImport) { $btnImport.IsEnabled = $true; $btnImport.Content = ([string][char]0xD83D + [char]0xDCC1 + " Import") }
            if ($btnDownload) { $btnDownload.IsEnabled = $true; $btnDownload.Content = ([string][char]0xD83D + [char]0xDCE5 + " Download") }
            if ($btnVerify) { $btnVerify.IsEnabled = $true; $btnVerify.Content = ([string][char]0x25B6 + " Run OCR") }
        }
        'Download' {
            if ($panelProg) { $panelProg.Visibility = [System.Windows.Visibility]::Visible }
            if ($txtTitle) { $txtTitle.Text = ([string][char]0xD83D + [char]0xDCE5 + " Downloading Receipts from Drive...") }
            if ($txtStatus) { $txtStatus.Text = "Fetching payment receipts from Google Drive" }
            if ($btnImport) { $btnImport.IsEnabled = $false }
            if ($btnDownload) { $btnDownload.IsEnabled = $false; $btnDownload.Content = ([string][char]0x23F3 + " Downloading...") }
            if ($btnVerify) { $btnVerify.IsEnabled = $false }

            $pct = if ($Total -gt 0) { [math]::Min(100, [math]::Round(($Current / $Total) * 100)) } else { 0 }
            if ($pBar) { $pBar.Value = $pct }
            if ($txtHead) { $txtHead.Text = if ($Headline) { $Headline } else { "DOWNLOADING RECEIPTS" } }
            if ($txtCounter) { $txtCounter.Text = "$Current / $Total ($pct%)" }
            if ($txtDetail) { $txtDetail.Text = $ItemText }
        }
        'Import' {
            if ($panelProg) { $panelProg.Visibility = [System.Windows.Visibility]::Visible }
            if ($txtTitle) { $txtTitle.Text = ([string][char]0xD83D + [char]0xDCC1 + " Ingesting Receipts from Archive...") }
            if ($txtStatus) { $txtStatus.Text = "Extracting and matching receipts to roster" }
            if ($btnImport) { $btnImport.IsEnabled = $false; $btnImport.Content = ([string][char]0x23F3 + " Importing...") }
            if ($btnDownload) { $btnDownload.IsEnabled = $false }
            if ($btnVerify) { $btnVerify.IsEnabled = $false }

            $pct = if ($Total -gt 0) { [math]::Min(100, [math]::Round(($Current / $Total) * 100)) } else { 0 }
            if ($pBar) { $pBar.Value = $pct }
            if ($txtHead) { $txtHead.Text = if ($Headline) { $Headline } else { "INGESTING LOCAL ARCHIVE" } }
            if ($txtCounter) { $txtCounter.Text = "$Current / $Total ($pct%)" }
            if ($txtDetail) { $txtDetail.Text = $ItemText }
        }
        'Verify' {
            if ($panelProg) { $panelProg.Visibility = [System.Windows.Visibility]::Visible }
            if ($txtTitle) { $txtTitle.Text = ([string][char]0xD83D + [char]0xDD0D + " Verifying Receipts (WinRT OCR)...") }
            if ($txtStatus) { $txtStatus.Text = "Auditing 5 verification rules with native OCR" }
            if ($btnImport) { $btnImport.IsEnabled = $false }
            if ($btnDownload) { $btnDownload.IsEnabled = $false }
            if ($btnVerify) { $btnVerify.IsEnabled = $false; $btnVerify.Content = ([string][char]0x23F3 + " Verifying...") }

            $pct = if ($Total -gt 0) { [math]::Min(100, [math]::Round(($Current / $Total) * 100)) } else { 0 }
            if ($pBar) { $pBar.Value = $pct }
            if ($txtHead) { $txtHead.Text = if ($Headline) { $Headline } else { "RUNNING OCR AUDIT" } }
            if ($txtCounter) { $txtCounter.Text = "$Current / $Total ($pct%)" }
            if ($txtDetail) { $txtDetail.Text = $ItemText }
        }
        'Complete' {
            if ($pBar) { $pBar.Value = 100 }
            if ($txtCounter) { $txtCounter.Text = "$Total / $Total (100%)" }
            if ($txtHead) { $txtHead.Text = "COMPLETED" }
            if ($txtDetail) { $txtDetail.Text = $ItemText }
            if ($btnImport) { $btnImport.IsEnabled = $true; $btnImport.Content = ([string][char]0xD83D + [char]0xDCC1 + " Import") }
            if ($btnDownload) { $btnDownload.IsEnabled = $true; $btnDownload.Content = ([string][char]0xD83D + [char]0xDCE5 + " Download") }
            if ($btnVerify) { $btnVerify.IsEnabled = $true; $btnVerify.Content = ([string][char]0x25B6 + " Run OCR") }
        }
    }

    # Dispatcher pump to immediately render UI changes
    try {
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
            [Action]{},
            [System.Windows.Threading.DispatcherPriority]::Render
        )
    } catch {
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}
    }
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

                    if ($script:courses -isnot [System.Collections.ArrayList]) {
                        $script:courses = [System.Collections.ArrayList]@($script:courses)
                    }
                    $null = $script:courses.Add($newCourse)
                    Save-Courses

                    # Ingest and persist student enrollment records
                    if ($newCourse.RegistrationSheet -and (Test-Path -LiteralPath $newCourse.RegistrationSheet)) {
                        $parsedSheet = Import-StudentSheet -Path $newCourse.RegistrationSheet
                        if ($parsedSheet.Success -and $parsedSheet.Students.Count -gt 0) {
                            Save-CourseStudents -CourseId $newCourse.Id -Students $parsedSheet.Students -CourseName $newCourse.Name
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
                    $null = Get-CourseStudentStore -CourseId $script:activeCourse.Id -RegistrationSheet $sheetPath -Force -CourseName $script:activeCourse.Name

                    # Refresh views with updated store and health badges
                    Select-Course $script:activeCourse

                    [System.Windows.MessageBox]::Show("Registration sheet health rechecked and updated successfully.", "Health Rechecked", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                })
            }

            # Toggle Registration Sheet Health Details Handler
            $btnToggleHealth = $viewObj.FindName("BtnToggleHealthDetails")
            if ($btnToggleHealth) {
                $btnToggleHealth.Add_Click({
                    $s1 = $script:views["Stage1View"]
                    $panel = if ($s1) { $s1.FindName("HealthDetailsContainer") } else { $null }
                    $btn = $this
                    if ($panel -and $btn) {
                        if ($panel.Visibility -eq [System.Windows.Visibility]::Visible) {
                            $panel.Visibility = [System.Windows.Visibility]::Collapsed
                            $btn.Content = "View Details " + [char]0x25BC
                        } else {
                            $panel.Visibility = [System.Windows.Visibility]::Visible
                            $btn.Content = "Hide Details " + [char]0x25B2
                        }
                    }
                })
            }

            # Update Registration Sheet Handler (Direct File Explorer Browse)
            $btnUpdateSheet = $viewObj.FindName("BtnUpdateSheet")
            if (-not $btnUpdateSheet) { $btnUpdateSheet = $viewObj.FindName("BtnChangeRegistrationSheet") }
            if ($btnUpdateSheet) {
                $btnUpdateSheet.Add_Click({
                    if (-not $script:activeCourse) { return }
                    $cName = [string]$script:activeCourse.Name
                    $currentPath = [string]$script:activeCourse.RegistrationSheet

                    # Directly open native File Explorer dialog
                    $selected = Show-ExcelBrowseDialog "Select Updated Student Registration Spreadsheet (.xlsx, .csv)"
                    if (-not $selected) { return }

                    $targetFile = $selected
                    $script:activeCourse.RegistrationSheet = $selected
                    Save-Courses

                    if (-not $targetFile -or -not (Test-Path -LiteralPath $targetFile)) {
                        [System.Windows.MessageBox]::Show("The spreadsheet file could not be found:`n$targetFile`nPlease check the file location.", "File Not Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                        return
                    }

                    $origCursor = [System.Windows.Input.Mouse]::OverrideCursor
                    try {
                        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait

                        $dDir = if ($script:dataDir) { $script:dataDir } else { (Join-Path $script:appRoot "data") }
                        $syncResult = Sync-CourseResponses -Course $script:activeCourse -NewSheetPath $targetFile -DataDir $dDir

                        # Refresh views, metrics, and on-disk counters
                        Select-Course $script:activeCourse

                        # Build friendly, clear coordinator summary
                        $reportText = "Registration Sheet Updated for '$cName'!`n`n" +
                            "Total Active Students: $($syncResult.TotalRoster)`n" +
                            "[Preserved Verified]: $($syncResult.PreservedVerifiedCount)`n" +
                            "[New Students Added]: $($syncResult.NewStudents)`n" +
                            "[Resubmitted / Updated]: $($syncResult.UpdatedReviewStudents)`n"

                        if ($syncResult.DuplicateCount -gt 0) {
                            $reportText += "[Duplicate Rows De-duplicated]: $($syncResult.DuplicateCount) (kept newest submissions)`n"
                        }

                        if ($syncResult.UpdatedReviewStudents -gt 0 -or $syncResult.NewStudents -gt 0) {
                            $reportText += "`nOld receipts for resubmitted students were purged from disk.`n`n" +
                                "Next Steps:`n" +
                                "1. Click [Download Receipts] to download the updated receipt(s).`n" +
                                "2. Click [Run Verification (OCR)] to verify."
                        } else {
                            $reportText += "`nAll student enrollment records are up to date."
                        }

                        [System.Windows.MessageBox]::Show(
                            $reportText,
                            "Sheet Updated Successfully",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Information
                        )
                    } catch {
                        [System.Windows.MessageBox]::Show(
                            "Failed to update registration sheet:`n$($_.Exception.Message)",
                            "Update Error",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Error
                        )
                    } finally {
                        [System.Windows.Input.Mouse]::OverrideCursor = $origCursor
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

            # -- Step 1: Import Local Receipts (Folder or .ZIP Archive) Handler --
            $btnImport = $viewObj.FindName("BtnImportReceipts")
            if ($btnImport) {
                $btnImport.Add_Click({
                    try {
                        if (-not $script:activeCourse) {
                            [System.Windows.MessageBox]::Show(
                                "Please select a course first before importing receipts.",
                                "No Active Course",
                                [System.Windows.MessageBoxButton]::OK,
                                [System.Windows.MessageBoxImage]::Warning
                            )
                            return
                        }

                        $store = Get-CourseStudentStore -CourseId $script:activeCourse.Id -RegistrationSheet $script:activeCourse.RegistrationSheet -CourseName $script:activeCourse.Name
                        $students = @($store.Students)
                        $regStudents = @($students | Where-Object {
                            if ($_.PSObject.Properties['IsRegistered']) { $_.IsRegistered -ne $false } else { $true }
                        })

                        if ($regStudents.Count -eq 0) {
                            [System.Windows.MessageBox]::Show(
                                "No registered students found in course '$($script:activeCourse.Name)'.",
                                "No Students Found",
                                [System.Windows.MessageBoxButton]::OK,
                                [System.Windows.MessageBoxImage]::Information
                            )
                            return
                        }

                        $cName = [string]$script:activeCourse.Name
                        $dDir = if ($script:dataDir) { $script:dataDir } else { (Join-Path $script:appRoot "data") }

                        # Prompt user for source type: .ZIP archive or Extracted Folder
                        $sourceChoice = [System.Windows.MessageBox]::Show(
                            "Import Student Receipts for '$cName':`n`n" +
                            "Registered students queued: $($regStudents.Count)`n`n" +
                            "Choose your receipt source format:`n" +
                            " [ Yes ]    Browse for a Google Drive .ZIP archive`n" +
                            " [ No ]     Browse for an extracted / local Folder`n" +
                            " [ Cancel ] Abort import",
                            "Import Student Receipts (Local / ZIP)",
                            [System.Windows.MessageBoxButton]::YesNoCancel,
                            [System.Windows.MessageBoxImage]::Question
                        )

                        if ($sourceChoice -eq [System.Windows.MessageBoxResult]::Cancel) { return }

                        $chosenSourcePath = $null

                        if ($sourceChoice -eq [System.Windows.MessageBoxResult]::Yes) {
                            # OpenFileDialog for .zip archive
                            $openDlg = New-Object Microsoft.Win32.OpenFileDialog
                            $openDlg.Title = "Select Google Drive Receipt ZIP Archive"
                            $openDlg.Filter = "ZIP Archive (*.zip)|*.zip|All Files (*.*)|*.*"
                            $openDlg.InitialDirectory = [Environment]::GetFolderPath("Desktop")
                            if ($openDlg.ShowDialog() -eq $true) {
                                $chosenSourcePath = $openDlg.FileName
                            }
                        } else {
                            # FolderBrowserDialog for unzipped directory
                            $folderDlg = New-Object System.Windows.Forms.FolderBrowserDialog
                            $folderDlg.Description = "Select the folder containing student receipt files (PDF/Images)"
                            $folderDlg.ShowNewFolderButton = $false
                            $desktopPath = [Environment]::GetFolderPath("Desktop")
                            if (Test-Path $desktopPath) { $folderDlg.SelectedPath = $desktopPath }
                            if ($folderDlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                                $chosenSourcePath = $folderDlg.SelectedPath
                            }
                        }

                        if (-not $chosenSourcePath -or -not (Test-Path -LiteralPath $chosenSourcePath)) {
                            return
                        }

                        $origCursor = [System.Windows.Input.Mouse]::OverrideCursor
                        try {
                            [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
                            Update-PipelineBarState -Mode 'Import' -Current 0 -Total $regStudents.Count -Headline "INGESTING LOCAL ARCHIVE" -ItemText "Reading and extracting files..."

                            $importCb = {
                                param($cur, $tot, $st, $msg)
                                $stRoll = if ($st.RollNo) { [string]$st.RollNo } else { "" }
                                $stName = if ($st.Name) { [string]$st.Name } else { "" }
                                $nameStr = if ($stName) { " - $stName" } else { "" }
                                $itemStr = "$stRoll$nameStr ($msg)"
                                Update-PipelineBarState -Mode 'Import' -Current $cur -Total $tot -Headline "INGESTING LOCAL ARCHIVE" -ItemText $itemStr
                            }

                            $importSummary = Import-ReceiptsFromLocalSource -CourseId $script:activeCourse.Id -CourseName $cName -SourcePath $chosenSourcePath -Students $regStudents -DataDir $dDir -ProgressCallback $importCb

                            # Refresh course views to update on-disk counter immediately
                            Select-Course $script:activeCourse

                            # Format friendly, informative report
                            $sourceDisplay = [System.IO.Path]::GetFileName($chosenSourcePath)
                            $reportLines = [System.Collections.ArrayList]@()
                            $null = $reportLines.Add("Receipt Ingestion Completed for '$cName'!")
                            $null = $reportLines.Add("Source: $sourceDisplay")
                            $null = $reportLines.Add("Total Registered Students: $($importSummary.TotalRegistered)`n")
                            $null = $reportLines.Add("  [+] Newly Ingested: $($importSummary.IngestedCount)")
                            $null = $reportLines.Add("  [*] Already on Disk: $($importSummary.ExistingCount)")
                            $null = $reportLines.Add("  [-] Missing Receipts: $($importSummary.MissingCount)")
                            if ($importSummary.UnassignedCount -gt 0) {
                                $null = $reportLines.Add("  [i] Unassigned Files in Source: $($importSummary.UnassignedCount)")
                            }

                            if ($importSummary.MissingCount -gt 0) {
                                $null = $reportLines.Add("`nMissing Students ($($importSummary.MissingCount)):")
                                $sampleMissing = @($importSummary.MissingStudents | Select-Object -First 5 | ForEach-Object {
                                    "  - $($_.RollNo) ($($_.Name))"
                                }) -join "`n"
                                $null = $reportLines.Add($sampleMissing)
                                if ($importSummary.MissingCount -gt 5) {
                                    $null = $reportLines.Add("  - ... and $($importSummary.MissingCount - 5) more")
                                }
                            }

                            $null = $reportLines.Add("`nSaved location: data/Courses/$cName/receipts/")

                            $msgIcon = if ($importSummary.MissingCount -gt 0) { [System.Windows.MessageBoxImage]::Warning } else { [System.Windows.MessageBoxImage]::Information }
                            [System.Windows.MessageBox]::Show(
                                ($reportLines -join "`n"),
                                "Receipt Import Summary",
                                [System.Windows.MessageBoxButton]::OK,
                                $msgIcon
                            )
                        } finally {
                            [System.Windows.Input.Mouse]::OverrideCursor = $origCursor
                            Update-PipelineBarState -Mode 'Idle'
                            Select-Course $script:activeCourse
                        }
                    } catch {
                        [System.Windows.MessageBox]::Show(
                            "Failed to import receipts:`n$($_.Exception.Message)",
                            "Import Error",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Error
                        )
                    }
                })
            }

            # -- Step 1: Download Receipts Handler --
            $btnDownload = $viewObj.FindName("BtnDownloadReceipts")
            if ($btnDownload) {
                $btnDownload.Add_Click({
                    try {
                        if (-not $script:activeCourse) {
                            [System.Windows.MessageBox]::Show("Please select a course first before downloading receipts.", "No Active Course", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                            return
                        }

                        $store = Get-CourseStudentStore -CourseId $script:activeCourse.Id -RegistrationSheet $script:activeCourse.RegistrationSheet -CourseName $script:activeCourse.Name
                        $students = @($store.Students)
                        $regStudents = @($students | Where-Object { $_.IsRegistered -eq $true })

                        if ($regStudents.Count -eq 0) {
                            [System.Windows.MessageBox]::Show("No registered students found in course '$($script:activeCourse.Name)'.", "No Students Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                            return
                        }

                        $cName = [string]$script:activeCourse.Name
                        $dDir = if ($script:dataDir) { $script:dataDir } else { (Join-Path $script:appRoot "data") }

                        $confirm = [System.Windows.MessageBox]::Show(
                            "Download payment receipts for '$cName'?`n`n" +
                            "Registered students queued: $($regStudents.Count)`n" +
                            "Target directory: data/Courses/$cName/receipts/`n`n" +
                            "Existing receipts will be skipped (resumable cache).",
                            "Download Student Receipts",
                            [System.Windows.MessageBoxButton]::YesNo,
                            [System.Windows.MessageBoxImage]::Question
                        )
                        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

                        $origCursor = [System.Windows.Input.Mouse]::OverrideCursor
                        try {
                            [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
                            Update-PipelineBarState -Mode 'Download' -Current 0 -Total $regStudents.Count -Headline "DOWNLOADING RECEIPTS" -ItemText "Connecting to Google Drive..."

                            $dlCb = {
                                param($cur, $tot, $st, $msg)
                                $stRoll = if ($st.RollNo) { [string]$st.RollNo } else { "" }
                                $stName = if ($st.Name) { [string]$st.Name } else { "" }
                                $nameStr = if ($stName) { " - $stName" } else { "" }
                                $itemStr = "$stRoll$nameStr ($msg)"
                                Update-PipelineBarState -Mode 'Download' -Current $cur -Total $tot -Headline "DOWNLOADING RECEIPTS" -ItemText $itemStr
                            }

                            $dlSummary = Invoke-ReceiptBatchDownload -CourseId $script:activeCourse.Id -CourseName $cName -Students $regStudents -DataDir $dDir -ProgressCallback $dlCb

                            # Refresh views to update on-disk counter
                            Select-Course $script:activeCourse

                            # Build results report
                            $reportText = "Batch Receipt Download Completed for '$cName'!`n`n" +
                                "Total Registered: $($regStudents.Count)`n" +
                                "[Downloaded Now]: $($dlSummary.Downloaded)`n" +
                                "[Already on Disk / Cached]: $($dlSummary.FromCache + $dlSummary.FromLocal)`n" +
                                "[Failed / Inaccessible]: $($dlSummary.Failed)`n`n" +
                                "Saved to: data/Courses/$cName/receipts/"

                            if ($dlSummary.Failed -gt 0) {
                                $failedList = @($dlSummary.Results | Where-Object { $_.Success -eq $false -and $_.Source -ne "Skipped" })
                                $failedSample = @($failedList | Select-Object -First 5 | ForEach-Object { " - $($_.RollNo) ($($_.Name)): $($_.Error)" }) -join "`n"
                                if ($failedList.Count -gt 5) {
                                    $failedSample += "`n - ... and $($failedList.Count - 5) more."
                                }

                                $reportText += "`n`n[!] The following receipt(s) could not be downloaded:`n$failedSample`n`n" +
                                    "Note: If Google Drive links fail with 'Access Denied', the student must set link sharing to 'Anyone with the link can view'."
                            }

                            $msgIcon = if ($dlSummary.Failed -gt 0) { [System.Windows.MessageBoxImage]::Warning } else { [System.Windows.MessageBoxImage]::Information }
                            [System.Windows.MessageBox]::Show(
                                $reportText,
                                "Receipt Download Complete",
                                [System.Windows.MessageBoxButton]::OK,
                                $msgIcon
                            )
                        } finally {
                            [System.Windows.Input.Mouse]::OverrideCursor = $origCursor
                            Update-PipelineBarState -Mode 'Idle'
                            Select-Course $script:activeCourse
                        }
                    } catch {
                        [System.Windows.MessageBox]::Show(
                            "Receipt download failed:`n$($_.Exception.Message)",
                            "Download Error",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Error
                        )
                    }
                })
            }

            # -- Step 2: Automated Batch Verification (OCR) Handler --
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

                        # 3. Check receipts on disk
                        $cName = [string]$script:activeCourse.Name
                        $dDir = if ($script:dataDir) { $script:dataDir } else { (Join-Path $script:appRoot "data") }
                        $cleanCName = ($cName -replace '[\\/:*?"<>|]', '_').Trim()
                        $rDir = Join-Path $dDir "Courses\$cleanCName\receipts"
                        $diskReceipts = @(Get-ChildItem -LiteralPath $rDir -Filter "*_receipt.*" -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 })

                        $skipDownload = $false
                        if ($diskReceipts.Count -lt $regStudents.Count) {
                            $missingCount = $regStudents.Count - $diskReceipts.Count
                            $choice = [System.Windows.MessageBox]::Show(
                                "Found $($diskReceipts.Count) receipt(s) on disk for $($regStudents.Count) registered student(s) ($missingCount missing).`n`n" +
                                "- Click [Yes] to download missing receipts first, then verify.`n" +
                                "- Click [No] to run OCR verification only for receipts already on disk.`n" +
                                "- Click [Cancel] to stop.",
                                "Missing Receipts on Disk",
                                [System.Windows.MessageBoxButton]::YesNoCancel,
                                [System.Windows.MessageBoxImage]::Question
                            )
                            if ($choice -eq [System.Windows.MessageBoxResult]::Cancel) { return }
                            if ($choice -eq [System.Windows.MessageBoxResult]::No) {
                                $skipDownload = $true
                            }
                        } else {
                            $confirm = [System.Windows.MessageBox]::Show(
                                "Run automated OCR verification for '$cName'?`n`n" +
                                "All $($regStudents.Count) registered student receipt(s) are ready on disk.`n`n" +
                                "The pipeline will execute locally:`n" +
                                "1. Native WinRT OCR text extraction (PDF / Images)`n" +
                                "2. Evaluate the 5 verification rules (Status, Rs. 1,000 / Rs. 500 Concession Fee, Course Title, Authenticity, Identity)`n" +
                                "3. Delta-sync and auto-update students.json and the Excel Verification Sheet.",
                                "Confirm OCR Verification",
                                [System.Windows.MessageBoxButton]::YesNo,
                                [System.Windows.MessageBoxImage]::Question
                            )
                            if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }
                            $skipDownload = $true
                        }

                        # 4. Run Pipeline with Wait Cursor & Visual Feedback
                        $origCursor = [System.Windows.Input.Mouse]::OverrideCursor
                        try {
                            [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
                            Update-PipelineBarState -Mode 'Verify' -Current 0 -Total $regStudents.Count -Headline "RUNNING WINRT OCR AUDIT" -ItemText "Starting OCR audit engine..."

                            $verCb = {
                                param($cur, $tot, $st, $msg)
                                $stRoll = if ($st.RollNo) { [string]$st.RollNo } else { "" }
                                $stName = if ($st.Name) { [string]$st.Name } else { "" }
                                $nameStr = if ($stName) { " - $stName" } else { "" }
                                $itemStr = "$stRoll$nameStr ($msg)"
                                Update-PipelineBarState -Mode 'Verify' -Current $cur -Total $tot -Headline "RUNNING WINRT OCR AUDIT" -ItemText $itemStr
                            }

                            $summary = Invoke-CourseVerificationPipeline -Course $script:activeCourse -DataDir $dDir -SkipDownload:$skipDownload -ProgressCallback $verCb

                            # Refresh views and mini cards
                            Select-Course $script:activeCourse

                            $vFileName = if ($script:activeCourse.VerificationSheet) { [System.IO.Path]::GetFileName($script:activeCourse.VerificationSheet) } else { "Verification Sheet" }
                            [System.Windows.MessageBox]::Show(
                                "Automated Verification Completed for '$cName'!`n`n" +
                                "[Verified]: $($summary.VerifiedCount)`n" +
                                "[Under Review]: $($summary.ReviewCount)`n" +
                                "[Did Not Register]: $($summary.UnregCount)`n" +
                                "Total Processed: $($summary.ProcessedCount) of $($summary.TotalStudents)`n`n" +
                                "Database: data/Courses/$cName/students.json`n" +
                                "Excel Sheet: $vFileName",
                                "Verification Complete",
                                [System.Windows.MessageBoxButton]::OK,
                                [System.Windows.MessageBoxImage]::Information
                            )
                        } finally {
                            [System.Windows.Input.Mouse]::OverrideCursor = $origCursor
                            Update-PipelineBarState -Mode 'Idle'
                            Select-Course $script:activeCourse
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
            # Back to Stage 1 (With staged unpushed changes safety check)
            $btnBack = $viewObj.FindName("BtnBackToStage1")
            if ($btnBack) {
                $btnBack.Add_Click({
                    if ($script:reviewStagedSolved.Count -gt 0) {
                        $ask = [System.Windows.MessageBox]::Show(
                            "You have $($script:reviewStagedSolved.Count) unpushed change(s) staged in this session.`n`nDo you want to return to Stage 1 anyway?`n(Your unpushed changes will remain staged until you click Push or exit the app.)",
                            "Unpushed Changes Staged",
                            [System.Windows.MessageBoxButton]::YesNo,
                            [System.Windows.MessageBoxImage]::Warning
                        )
                        if ($ask -ne [System.Windows.MessageBoxResult]::Yes) { return }
                    }

                    if ($script:activeCourse) {
                        Select-Course $script:activeCourse -TargetView "Stage1View"
                    } else {
                        Navigate-To "CoursesView"
                    }
                })
            }

            # Back to Queue Table (From Mode B Detail to Mode A Queue Overview)
            $btnBackQueue = $viewObj.FindName("BtnBackToQueueTable")
            if ($btnBackQueue) {
                $btnBackQueue.Add_Click({
                    $rv = $script:views["ReviewView"]
                    if (-not $rv) { return }

                    $panelOverview = $rv.FindName("ReviewQueueOverviewPanel")
                    $panelDetail = $rv.FindName("ReviewStudentDetailPanel")

                    if ($panelDetail) { $panelDetail.Visibility = [System.Windows.Visibility]::Collapsed }
                    if ($panelOverview) { $panelOverview.Visibility = [System.Windows.Visibility]::Visible }

                    if ($script:activeCourse) {
                        Update-ReviewView -Course $script:activeCourse
                    }
                })
            }

            # Push Solved Changes to Main Sheet
            $btnPushSolved = $viewObj.FindName("BtnPushSolvedChanges")
            if ($btnPushSolved) {
                $btnPushSolved.Add_Click({
                    if (-not $script:activeCourse) { return }
                    $stagedCount = $script:reviewStagedSolved.Count
                    if ($stagedCount -le 0) {
                        [System.Windows.MessageBox]::Show("There are no pending solved changes to push.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                        return
                    }

                    $cName = if ($script:activeCourse.Name) { [string]$script:activeCourse.Name } else { "Default" }
                    $targetExcel = if ($script:activeCourse.VerificationSheet) { [string]$script:activeCourse.VerificationSheet } else { "Main Verification Sheet" }

                    $plural = if ($stagedCount -eq 1) { "1 solved student" } else { "$stagedCount solved students" }
                    $confirm = [System.Windows.MessageBox]::Show(
                        "Push $plural to Main Sheet?`n`n" +
                        "Course: $cName`n" +
                        "Target Sheet: $targetExcel`n`n" +
                        "This will commit student statuses, update the verification spreadsheet, and refresh the Stage 1 panel counts.",
                        "Push Changes to Main Sheet",
                        [System.Windows.MessageBoxButton]::YesNo,
                        [System.Windows.MessageBoxImage]::Question
                    )
                    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

                    $origCursor = [System.Windows.Input.Mouse]::OverrideCursor
                    try {
                        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait

                        $store = Get-CourseStudentStore -CourseId $script:activeCourse.Id -RegistrationSheet $script:activeCourse.RegistrationSheet -CourseName $cName
                        $students = [System.Collections.ArrayList]@($store.Students)

                        # Apply all staged changes to the store
                        foreach ($entry in $script:reviewStagedSolved.Values) {
                            $eRoll = if ($entry.RollNo) { [string]$entry.RollNo } else { "" }
                            $eEmail = if ($entry.Email) { [string]$entry.Email } else { "" }

                            foreach ($s in $students) {
                                $match = $false
                                if ($eRoll -and $s.RollNo -and ($s.RollNo.Trim().ToLower() -eq $eRoll.Trim().ToLower())) {
                                    $match = $true
                                } elseif ($eEmail -and $s.Email -and ($s.Email.Trim().ToLower() -eq $eEmail.Trim().ToLower())) {
                                    $match = $true
                                }

                                if ($match) {
                                    $s.VerificationStatus = $entry.NewStatus
                                    $s.VerificationRemarks = $entry.NewRemarks
                                    break
                                }
                            }
                        }

                        # 1. Save students.json
                        Save-CourseStudents -CourseId $script:activeCourse.Id -Students $students -ColumnMap $store.ColumnMap -CourseName $cName

                        # 2. Export / Sync Verification Excel Sheet
                        Export-CourseVerificationSheetData -Course $script:activeCourse -Students $students

                        # 3. Clear staged changes (committed!)
                        $committedCount = $script:reviewStagedSolved.Count
                        $script:reviewStagedSolved.Clear()

                        # 4. Refresh Stage 1 View metrics in background
                        $s1View = if ($script:views.ContainsKey("Stage1View")) { $script:views["Stage1View"] } else { $null }
                        if ($s1View) {
                            $verCount = @($students | Where-Object { $_.VerificationStatus -eq "Verified" }).Count
                            $revCount = @($students | Where-Object { $_.VerificationStatus -eq "Under Review" }).Count
                            $unregCount = @($students | Where-Object { $_.VerificationStatus -eq "Did Not Register" }).Count

                            $txtVer = $s1View.FindName("TxtVerStatVerified")
                            $txtRev = $s1View.FindName("TxtVerStatReview")
                            $txtUnr = $s1View.FindName("TxtVerStatUnreg")
                            $txtSum = $s1View.FindName("TxtVerificationSheetSummary")

                            if ($txtVer) { $txtVer.Text = $verCount.ToString() }
                            if ($txtRev) { $txtRev.Text = $revCount.ToString() }
                            if ($txtUnr) { $txtUnr.Text = $unregCount.ToString() }
                            if ($txtSum) {
                                $txtSum.Text = "$($students.Count) Students | $verCount Verified, $revCount Under Review, $unregCount Did Not Register"
                            }
                        }

                        # 5. Refresh Review Queue
                        Update-ReviewView -Course $script:activeCourse -Students $students

                        [System.Windows.MessageBox]::Show(
                            "Successfully pushed $committedCount change(s) to Main Sheet!`n`n" +
                            "- Statuses updated in $targetExcel`n" +
                            "- Stage 1 counts updated: Under Review decreased, Verified increased.",
                            "Push Complete",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Information
                        )
                    } catch {
                        [System.Windows.MessageBox]::Show(
                            "Failed to push changes to main sheet:`n$($_.Exception.Message)",
                            "Push Error",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Error
                        )
                    } finally {
                        [System.Windows.Input.Mouse]::OverrideCursor = $origCursor
                    }
                })
            }

            # Send Email to Flagged Students -> Open Email Management Center
            $btnNotifyFlagged = $viewObj.FindName("BtnNotifyFlaggedStudents")
            if ($btnNotifyFlagged) {
                $btnNotifyFlagged.Add_Click({
                    if (-not $script:activeCourse) { return }
                    Open-EmailView
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

            # Coordinator Action: Approve Override
            $btnApprove = $viewObj.FindName("BtnApproveOverride")
            if ($btnApprove) {
                $btnApprove.Add_Click({
                    $rv = $script:views["ReviewView"]
                    $ws = if ($rv) { $rv.FindName("ReviewWorkspaceGrid") } else { $null }
                    $st = if ($ws) { $ws.Tag } else { $null }
                    if (-not $st -or -not $script:activeCourse) { return }

                    $stName = if ($st.Name) { [string]$st.Name } else { "this student" }
                    $stRoll = if ($st.RollNo) { [string]$st.RollNo } else { "No Roll No" }

                    $confirm = [System.Windows.MessageBox]::Show(
                        "Manually approve enrollment verification for:`n`nName: $stName`nRoll No: $stRoll`n`nStatus will be changed to 'Verified' and staged to push to the main sheet.",
                        "Approve Override",
                        [System.Windows.MessageBoxButton]::YesNo,
                        [System.Windows.MessageBoxImage]::Question
                    )
                    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

                    $targetKey = if ($st.RollNo) { [string]$st.RollNo } else { [string]$st.Email }
                    $origStatus = if ($st.VerificationStatus -and $st.VerificationStatus -ne "Verified") { [string]$st.VerificationStatus } else { "Under Review" }
                    $origRemarks = if ($st.VerificationRemarks) { [string]$st.VerificationRemarks } else { "" }

                    $nowStr = (Get-Date).ToString("dd/MM/yyyy HH:mm")
                    $newRem = "Manually approved by coordinator on $nowStr"

                    $st.VerificationStatus = "Verified"
                    $st.VerificationRemarks = $newRem

                    $null = $script:reviewSessionSolvedRolls.Add($targetKey)
                    $script:reviewStagedSolved[$targetKey] = @{
                        Student         = $st
                        RollNo          = $st.RollNo
                        Email           = $st.Email
                        NewStatus       = "Verified"
                        NewRemarks      = $newRem
                        OriginalStatus  = $origStatus
                        OriginalRemarks = $origRemarks
                    }

                    $askReturn = [System.Windows.MessageBox]::Show(
                        "Student '$stName' ($stRoll) approved and staged for this session!`n`nWould you like to return to the Review Queue now to push changes to the main sheet?",
                        "Student Approved",
                        [System.Windows.MessageBoxButton]::YesNo,
                        [System.Windows.MessageBoxImage]::Information
                    )
                    if ($askReturn -eq [System.Windows.MessageBoxResult]::Yes) {
                        $panelOverview = $rv.FindName("ReviewQueueOverviewPanel")
                        $panelDetail = $rv.FindName("ReviewStudentDetailPanel")
                        if ($panelDetail) { $panelDetail.Visibility = [System.Windows.Visibility]::Collapsed }
                        if ($panelOverview) { $panelOverview.Visibility = [System.Windows.Visibility]::Visible }
                        Update-ReviewView -Course $script:activeCourse
                    } else {
                        Show-StudentReviewDetails -Student $st
                    }
                })
            }

            # Coordinator Action: Attach Local Receipt File & Auto-Verify with OCR
            $btnAttach = $viewObj.FindName("BtnAttachLocalReceipt")
            if ($btnAttach) {
                $btnAttach.Add_Click({
                    $rv = $script:views["ReviewView"]
                    $ws = if ($rv) { $rv.FindName("ReviewWorkspaceGrid") } else { $null }
                    $st = if ($ws) { $ws.Tag } else { $null }
                    if (-not $st -or -not $script:activeCourse) { return }

                    $stName = if ($st.Name) { [string]$st.Name } else { "Student" }
                    $cleanRoll = if ($st.RollNo) { ($st.RollNo -replace '[\\/:*?"<>|]', '_').Trim() } else { "receipt" }

                    $fileDlg = New-Object Microsoft.Win32.OpenFileDialog
                    $fileDlg.Title = "Select Receipt File for $stName ($cleanRoll)"
                    $fileDlg.Filter = "Receipt Files (*.pdf;*.png;*.jpg;*.jpeg)|*.pdf;*.png;*.jpg;*.jpeg|PDF Documents (*.pdf)|*.pdf|Image Files (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg|All Files (*.*)|*.*"

                    if ($fileDlg.ShowDialog() -eq $true) {
                        $selectedFile = $fileDlg.FileName
                        if (-not (Test-Path -LiteralPath $selectedFile)) { return }

                        $origCursor = [System.Windows.Input.Mouse]::OverrideCursor
                        try {
                            [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait

                            $cName = if ($script:activeCourse.Name) { [string]$script:activeCourse.Name } else { "Default" }
                            $dDir = if ($script:dataDir) { $script:dataDir } else { (Join-Path $script:appRoot "data") }
                            $receiptsDir = Get-CourseReceiptsDirectory -CourseId $script:activeCourse.Id -CourseName $cName -DataDir $dDir

                            if (-not (Test-Path -LiteralPath $receiptsDir)) {
                                $null = New-Item -ItemType Directory -Path $receiptsDir -Force
                            }

                            # 1. Clean up any leftover staged files from prior attempts
                            Get-ChildItem -LiteralPath $receiptsDir -Filter "${cleanRoll}_staged*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

                            # 2. Stage the new file in a temporary staging path
                            $ext = [System.IO.Path]::GetExtension($selectedFile).ToLower()
                            $stagedFile = Join-Path $receiptsDir "${cleanRoll}_staged$ext"
                            Copy-Item -LiteralPath $selectedFile -Destination $stagedFile -Force

                            # 3. If PDF, rasterize Page 1 to PNG
                            $stagedImg = ConvertTo-ReceiptImage -FilePath $stagedFile -Force

                            # 4. Ensure OCR engine and rules are loaded, then extract text
                            if (-not (Get-Command "Invoke-ReceiptOcr" -ErrorAction SilentlyContinue)) {
                                $ocrMod = Join-Path $script:appRoot "modules\OcrEngine.ps1"
                                if (Test-Path -LiteralPath $ocrMod) { . $ocrMod }
                            }
                            if (-not (Get-Command "Test-ReceiptVerificationRules" -ErrorAction SilentlyContinue)) {
                                $verMod = Join-Path $script:appRoot "modules\VerificationEngine.ps1"
                                if (Test-Path -LiteralPath $verMod) { . $verMod }
                            }

                            $ocrRes = Invoke-ReceiptOcr -ImagePath $stagedImg
                            $ruleRes = Test-ReceiptVerificationRules -Student $st -OcrText $ocrRes.Text -OcrLines $ocrRes.Lines -CourseName $cName
                            if (-not $ocrRes.Success -and $ocrRes.Error) {
                                $ruleRes.Remarks = "OCR Read Error: $($ocrRes.Error); " + $ruleRes.Remarks
                            }

                            if ($ruleRes.Status -eq "Verified") {
                                # --- CASE 1: All 5 Rules Matched (Correct Receipt!) ---
                                $approvePrompt = "All 5 verification rules matched on the new receipt for '$stName' ($cleanRoll)!`n`n" +
                                    "- Payment Status: Successful`n" +
                                    "- Fee Amount: Verified (Rs. 1,000 / Rs. 500 Concession)`n" +
                                    "- Course Title: Matched ('$cName')`n" +
                                    "- Authenticity: Confirmed (NPTEL / Razorpay)`n" +
                                    "- Student Identity: Matched ('$stName')`n`n" +
                                    "Would you like to approve this student now?`n" +
                                    "(The old receipt will be safely replaced with this new verified receipt.)"

                                $askApprove = [System.Windows.MessageBox]::Show(
                                    $approvePrompt,
                                    "Receipt Verified - Approve Student?",
                                    [System.Windows.MessageBoxButton]::YesNo,
                                    [System.Windows.MessageBoxImage]::Question
                                )

                                if ($askApprove -eq [System.Windows.MessageBoxResult]::Yes) {
                                    # Safe Replacement: Release viewer image first so no locks exist
                                    $imgReceiptCtrl = if ($rv) { $rv.FindName("ReceiptImage") } else { $null }
                                    if ($imgReceiptCtrl) { $imgReceiptCtrl.Source = $null }

                                    # Delete all old receipt files now that new receipt is verified and approved
                                    $allOld = @(Get-ChildItem -LiteralPath $receiptsDir -Filter "${cleanRoll}_receipt*" -ErrorAction SilentlyContinue)
                                    foreach ($oldF in $allOld) {
                                        Remove-Item -LiteralPath $oldF.FullName -Force -ErrorAction SilentlyContinue
                                    }

                                    # Promote staged file to official receipt path
                                    $finalPath = Join-Path $receiptsDir "${cleanRoll}_receipt$ext"
                                    Move-Item -LiteralPath $stagedFile -Destination $finalPath -Force

                                    if ($ext -eq ".pdf") {
                                        $finalPng = Join-Path $receiptsDir "${cleanRoll}_receipt_page1.png"
                                        if (Test-Path -LiteralPath $stagedImg) {
                                            Move-Item -LiteralPath $stagedImg -Destination $finalPng -Force
                                        }
                                    }

                                    # Update Student status in store
                                    $store = Get-CourseStudentStore -CourseId $script:activeCourse.Id -RegistrationSheet $script:activeCourse.RegistrationSheet -CourseName $cName
                                    $students = [System.Collections.ArrayList]@($store.Students)
                                    $nowStr = (Get-Date).ToString("dd/MM/yyyy HH:mm")

                                    $matchedSt = $null
                                    foreach ($s in $students) {
                                        if ($st.RollNo -and $s.RollNo -and ($s.RollNo.Trim().ToLower() -eq $st.RollNo.Trim().ToLower())) {
                                            $matchedSt = $s
                                            break
                                        } elseif ($st.Email -and $s.Email -and ($s.Email.Trim().ToLower() -eq $st.Email.Trim().ToLower())) {
                                            $matchedSt = $s
                                            break
                                        }
                                    }

                                    if ($matchedSt) {
                                        $matchedSt.VerificationStatus = "Verified"
                                        $matchedSt.VerificationRemarks = "Verified (OCR passed on newly attached receipt on $nowStr)"
                                    }
                                    $st.VerificationStatus = "Verified"
                                    $st.VerificationRemarks = "Verified (OCR passed on newly attached receipt on $nowStr)"

                                    $stKey = if ($st.RollNo) { [string]$st.RollNo } else { [string]$st.Email }
                                    $null = $script:reviewSessionSolvedRolls.Add($stKey)
                                    if ($script:reviewStagedSolved.ContainsKey($stKey)) {
                                        $null = $script:reviewStagedSolved.Remove($stKey)
                                    }

                                    Save-CourseStudents -CourseId $script:activeCourse.Id -Students $students -ColumnMap $store.ColumnMap -CourseName $cName
                                    Export-CourseVerificationSheetData -Course $script:activeCourse -Students $students

                                    # Reload student details with new receipt displayed and updated status
                                    Show-StudentReviewDetails -Student $st

                                    # Refresh Review Queue metrics in-place
                                    Update-ReviewView

                                    [System.Windows.MessageBox]::Show(
                                        "Student '$stName' ($cleanRoll) approved successfully!`n`nStatus updated to 'Verified'.",
                                        "Approval Complete",
                                        [System.Windows.MessageBoxButton]::OK,
                                        [System.Windows.MessageBoxImage]::Information
                                    )
                                } else {
                                    # Coordinator clicked No on approval -> clean up staged files, keep old receipt
                                    Remove-Item -LiteralPath $stagedFile -Force -ErrorAction SilentlyContinue
                                    if ($stagedImg -and $stagedImg -ne $stagedFile) {
                                        Remove-Item -LiteralPath $stagedImg -Force -ErrorAction SilentlyContinue
                                    }
                                    Show-StudentReviewDetails -Student $st
                                }
                            } else {
                                # --- CASE 2: OCR Rules Failed (Discrepancies Found) ---
                                $failRemarks = $ruleRes.Remarks
                                $discrepancyPrompt = "The newly attached receipt for '$stName' was scanned, but verification discrepancies were found:`n`n" +
                                    "Issues: $failRemarks`n`n" +
                                    "Would you like to replace the old receipt with this new file anyway for manual inspection?`n`n" +
                                    "[Yes] Replace with new receipt (you can still manually override).`n" +
                                    "[No] Cancel and keep the previous receipt intact."

                                $keepChoice = [System.Windows.MessageBox]::Show(
                                    $discrepancyPrompt,
                                    "OCR Discrepancies Found",
                                    [System.Windows.MessageBoxButton]::YesNo,
                                    [System.Windows.MessageBoxImage]::Warning
                                )

                                if ($keepChoice -eq [System.Windows.MessageBoxResult]::Yes) {
                                    # Safe Replacement: Release viewer image first so no locks exist
                                    $imgReceiptCtrl = if ($rv) { $rv.FindName("ReceiptImage") } else { $null }
                                    if ($imgReceiptCtrl) { $imgReceiptCtrl.Source = $null }

                                    # Remove all old receipt files for this student
                                    $allOld = @(Get-ChildItem -LiteralPath $receiptsDir -Filter "${cleanRoll}_receipt*" -ErrorAction SilentlyContinue)
                                    foreach ($oldF in $allOld) {
                                        Remove-Item -LiteralPath $oldF.FullName -Force -ErrorAction SilentlyContinue
                                    }

                                    # Promote new file to official receipt path
                                    $finalPath = Join-Path $receiptsDir "${cleanRoll}_receipt$ext"
                                    Move-Item -LiteralPath $stagedFile -Destination $finalPath -Force

                                    if ($ext -eq ".pdf") {
                                        $finalPng = Join-Path $receiptsDir "${cleanRoll}_receipt_page1.png"
                                        if (Test-Path -LiteralPath $stagedImg) {
                                            Move-Item -LiteralPath $stagedImg -Destination $finalPng -Force
                                        }
                                    }

                                    # Persist updated remarks to store and sync verification sheet
                                    $store = Get-CourseStudentStore -CourseId $script:activeCourse.Id -RegistrationSheet $script:activeCourse.RegistrationSheet -CourseName $cName
                                    $students = [System.Collections.ArrayList]@($store.Students)
                                    $matchedSt = $null
                                    foreach ($s in $students) {
                                        if ($st.RollNo -and $s.RollNo -and ($s.RollNo.Trim().ToLower() -eq $st.RollNo.Trim().ToLower())) {
                                            $matchedSt = $s
                                            break
                                        } elseif ($st.Email -and $s.Email -and ($s.Email.Trim().ToLower() -eq $st.Email.Trim().ToLower())) {
                                            $matchedSt = $s
                                            break
                                        }
                                    }
                                    if ($matchedSt) {
                                        $matchedSt.VerificationRemarks = "Attached receipt: $failRemarks"
                                    }
                                    $st.VerificationRemarks = "Attached receipt: $failRemarks"

                                    Save-CourseStudents -CourseId $script:activeCourse.Id -Students $students -ColumnMap $store.ColumnMap -CourseName $cName
                                    Export-CourseVerificationSheetData -Course $script:activeCourse -Students $students

                                    # Reload student details with new receipt displayed
                                    Show-StudentReviewDetails -Student $st
                                } else {
                                    # Discard staged files, preserve old receipt
                                    Remove-Item -LiteralPath $stagedFile -Force -ErrorAction SilentlyContinue
                                    if ($stagedImg -and $stagedImg -ne $stagedFile) {
                                        Remove-Item -LiteralPath $stagedImg -Force -ErrorAction SilentlyContinue
                                    }
                                    Show-StudentReviewDetails -Student $st
                                }
                            }
                        } catch {
                            [System.Windows.MessageBox]::Show(
                                "Failed to process attached receipt:`n$($_.Exception.Message)",
                                "Processing Error",
                                [System.Windows.MessageBoxButton]::OK,
                                [System.Windows.MessageBoxImage]::Error
                            )
                        } finally {
                            [System.Windows.Input.Mouse]::OverrideCursor = $origCursor
                        }
                    }
                })
            }
        }

        "EmailView" {
            # 1. Back button -> Return to ReviewView
            $btnBack = $viewObj.FindName("BtnBackToReview")
            if ($btnBack) {
                $btnBack.Add_Click({
                    if ($script:activeCourse) {
                        Open-ReviewView
                    } else {
                        Navigate-To "CoursesView"
                    }
                })
            }

            # 2. Function Switcher (Standard Rule Template vs Custom Draft Mail)
            $btnTplStandard = $viewObj.FindName("BtnTplStandardRuleNotice")
            $btnTplCustom   = $viewObj.FindName("BtnTplCustomDraft")

            if ($btnTplStandard) { $btnTplStandard.Add_Click({ Set-EmailTemplate "StandardTemplate" }) }
            if ($btnTplCustom)   { $btnTplCustom.Add_Click({ Set-EmailTemplate "CustomDraft" }) }

            # 3. Select All / Clear All
            $btnSelectAll = $viewObj.FindName("BtnSelectAllRecipients")
            if ($btnSelectAll) {
                $btnSelectAll.Add_Click({
                    $ev = $script:views["EmailView"]
                    if (-not $ev) { return }
                    $hostP = $ev.FindName("EmailRecipientsHost")
                    if (-not $hostP) { return }
                    foreach ($child in $hostP.Children) {
                        $grid = $child.Child
                        if ($grid -and $grid.Children.Count -gt 0) {
                            $chk = $grid.Children[0]
                            if ($chk -is [System.Windows.Controls.CheckBox]) {
                                $chk.IsChecked = $true
                            }
                        }
                    }
                    Update-EmailSelectionMetrics
                })
            }

            $btnDeselectAll = $viewObj.FindName("BtnDeselectAllRecipients")
            if ($btnDeselectAll) {
                $btnDeselectAll.Add_Click({
                    $ev = $script:views["EmailView"]
                    if (-not $ev) { return }
                    $hostP = $ev.FindName("EmailRecipientsHost")
                    if (-not $hostP) { return }
                    foreach ($child in $hostP.Children) {
                        $grid = $child.Child
                        if ($grid -and $grid.Children.Count -gt 0) {
                            $chk = $grid.Children[0]
                            if ($chk -is [System.Windows.Controls.CheckBox]) {
                                $chk.IsChecked = $false
                            }
                        }
                    }
                    Update-EmailSelectionMetrics
                })
            }

            # 3b. Manual Delivery Status Actions (Mark Notified / Unmark)
            $btnMarkNotified = $viewObj.FindName("BtnMarkSelectedNotified")
            if ($btnMarkNotified) {
                $btnMarkNotified.Add_Click({
                    $selectedStudents = Get-SelectedStudents
                    if ($selectedStudents.Count -eq 0) {
                        [System.Windows.MessageBox]::Show(
                            "No students selected. Please check at least one student in the roster.",
                            "No Selection",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Warning
                        )
                        return
                    }
                    $count = Mark-SelectedStudentsNotified -SelectedStudents $selectedStudents
                    [System.Windows.MessageBox]::Show(
                        "Successfully marked $count student(s) as Notified.`n`nStatus badges and dashboard metrics have been updated.",
                        "Status Updated",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    )
                })
            }

            $btnUnmarkNotified = $viewObj.FindName("BtnUnmarkSelectedNotified")
            if ($btnUnmarkNotified) {
                $btnUnmarkNotified.Add_Click({
                    $selectedStudents = Get-SelectedStudents
                    if ($selectedStudents.Count -eq 0) {
                        [System.Windows.MessageBox]::Show(
                            "No students selected. Please check at least one student in the roster.",
                            "No Selection",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Warning
                        )
                        return
                    }
                    $count = Unmark-SelectedStudentsNotified -SelectedStudents $selectedStudents
                    [System.Windows.MessageBox]::Show(
                        "Reset notification status for $count student(s).`n`nStatus badges and dashboard metrics have been updated.",
                        "Status Reset",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Information
                    )
                })
            }

            # 4. Copy Notice Text (for WhatsApp/Telegram)
            $btnCopyNotice = $viewObj.FindName("BtnCopyNoticeText")
            if ($btnCopyNotice) {
                $btnCopyNotice.Add_Click({
                    $ev = $script:views["EmailView"]
                    if (-not $ev) { return }
                    $txtBody = $ev.FindName("TxtEmailBodyPreview")
                    if ($txtBody -and $txtBody.Text) {
                        try {
                            [System.Windows.Clipboard]::SetText($txtBody.Text)
                            [System.Windows.MessageBox]::Show(
                                "Notice text copied to clipboard!`n`nYou can paste it directly into WhatsApp, Telegram, or email announcements.",
                                "Notice Copied",
                                [System.Windows.MessageBoxButton]::OK,
                                [System.Windows.MessageBoxImage]::Information
                            )
                        } catch {
                            [System.Windows.MessageBox]::Show("Failed to copy text: $($_.Exception.Message)", "Clipboard Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                        }
                    }
                })
            }

            # 5. Copy BCC Emails
            $btnCopyBcc = $viewObj.FindName("BtnCopyBccEmails")
            if ($btnCopyBcc) {
                $btnCopyBcc.Add_Click({
                    $emails = Get-SelectedEmailRecipients
                    if ($emails.Count -eq 0) {
                        [System.Windows.MessageBox]::Show("No recipients selected. Please check at least one student in the roster.", "No Recipients Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                        return
                    }
                    try {
                        $bccStr = ($emails | Select-Object -Unique) -join ", "
                        [System.Windows.Clipboard]::SetText($bccStr)
                        [System.Windows.MessageBox]::Show(
                            "Copied $($emails.Count) student email address(es) to clipboard!`n`nPaste into the BCC line of your email client to notify all flagged students at once while protecting their privacy.",
                            "BCC Emails Copied",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Information
                        )
                    } catch {
                        [System.Windows.MessageBox]::Show("Failed to copy emails: $($_.Exception.Message)", "Clipboard Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                    }
                })
            }

            # 6. Open in Gmail (Web Draft)
            $btnLaunchGmail = $viewObj.FindName("BtnLaunchGmailDraft")
            if ($btnLaunchGmail) {
                $btnLaunchGmail.Add_Click({
                    $selectedStudents = Get-SelectedStudents
                    if ($selectedStudents.Count -eq 0) {
                        [System.Windows.MessageBox]::Show("No recipients selected. Please check at least one student in the roster.", "No Recipients Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                        return
                    }

                    $emails = [System.Collections.Generic.List[string]]::new()
                    foreach ($st in $selectedStudents) {
                        if ($st.Email -and [string]$st.Email.Trim()) {
                            $emails.Add([string]$st.Email.Trim())
                        }
                    }

                    if ($emails.Count -eq 0) {
                        [System.Windows.MessageBox]::Show("Selected students have no email addresses listed.", "Missing Emails", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                        return
                    }

                    $ev = $script:views["EmailView"]
                    if (-not $ev) { return }
                    $txtSub = $ev.FindName("TxtEmailSubject")
                    $txtBody = $ev.FindName("TxtEmailBodyPreview")

                    $subText = if ($txtSub -and $txtSub.Text) { $txtSub.Text } else { "NPTEL Verification Notice" }
                    $bodyText = if ($txtBody -and $txtBody.Text) { $txtBody.Text } else { "" }

                    $bccList = ($emails | Select-Object -Unique) -join ","
                    $encBcc = [System.Uri]::EscapeDataString($bccList)
                    $encSub = [System.Uri]::EscapeDataString($subText)
                    $encBody = [System.Uri]::EscapeDataString($bodyText)

                    $gmailUrl = "https://mail.google.com/mail/?view=cm&fs=1&tf=1&bcc=$encBcc&su=$encSub&body=$encBody"

                    try {
                        [System.Diagnostics.Process]::Start($gmailUrl)

                        # Mark recipients as Notified in store
                        $null = Mark-SelectedStudentsNotified -SelectedStudents $selectedStudents

                        [System.Windows.MessageBox]::Show(
                            "Gmail Web Draft opened in your default browser!`n`n- Recipients: $($emails.Count) student email(s) placed in BCC`n- Flagged Students: $($selectedStudents.Count) marked as Notified in database.`n`nTip: If you do not send the email or the send fails, you can select the students and click '[ ↺ Unmark ]' to reset their status.",
                            "Gmail Draft Launched",
                            [System.Windows.MessageBoxButton]::OK,
                            [System.Windows.MessageBoxImage]::Information
                        )
                    } catch {
                        [System.Windows.MessageBox]::Show("Failed to open browser:`n$($_.Exception.Message)", "Launch Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
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
    if ($NavBtnCourses) { $NavBtnCourses.Style = if ($ViewName -eq "CoursesView" -or $ViewName -eq "WorkspaceView" -or $ViewName -eq "Stage1View" -or $ViewName -eq "Stage2View" -or $ViewName -eq "ReviewView" -or $ViewName -eq "EmailView") { $activeStyle } else { $defaultStyle } }
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
