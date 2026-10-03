# Branch 3 (Session 6) — Collapsible Sheet Health, 'Import Receipts' Local/ZIP Ingestion & Fee Concession Matching

---

## 1) Defensive Property Injection & Typo Tolerance in Spreadsheet Ingestion

### 1.1 The Problem

When importing student records from an Excel or CSV file via `Import-StudentSheet.ps1`, each row is converted into a PowerShell custom object (`[PSCustomObject]`). Later in the verification pipeline, the application assigns verification results to each student:

```powershell
$student.VerificationStatus = "Pending"
```

If the original spreadsheet or JSON cache did not already contain a column named `VerificationStatus`, PowerShell throws a fatal runtime exception:
```text
The property 'VerificationStatus' cannot be found on this object. Verify that the property exists and can be set.
```

Furthermore, real-world Google Forms created by teachers often contain human typos in column headers—for example, `"Reistration Done"` (missing the letter 'g'). Because our earlier regex looked strictly for `registration`, the column was marked as missing, leading to inaccurate sheet health audits.

### 1.2 The Fix: Safe Member Initialization & Widened Regex

We introduced defensive property initialization in `modules/Import-StudentSheet.ps1` and defensive runtime guards in `modules/VerificationEngine.ps1`:

```powershell
# 1. Initialize default verification properties on every imported student
$studentObj = [PSCustomObject]@{
    RollNo              = $rollVal
    Name                = $nameVal
    Email               = $emailVal
    Subject             = $subjVal
    IsEnrolled          = $isEnrolled
    IsRegistered        = $isRegistered
    ProofUrl            = $proofVal
    Timestamp           = $timeVal
    VerificationStatus  = "Pending"
    VerificationRemarks = "Awaiting Verification"
    Raw                 = [ordered]@{}
}
```

And in `modules/VerificationEngine.ps1`:

```powershell
# 2. Defensive runtime property assignment guard
if ($student.PSObject.Properties['VerificationStatus']) {
    $student.VerificationStatus = "Under Review"
} else {
    $student | Add-Member -NotePropertyName 'VerificationStatus' -NotePropertyValue "Under Review" -Force
}
```

For header matching, we updated the regular expression:

```powershell
# Typo-tolerant regex: matches 'Registration', 'Registered', or 'Reistration Done'
'IsRegistered' = 're[g]?istr.*(done|complete)|registration|registered'
```

### 1.3 Wrong vs Right

* ❌ **Wrong:** Assuming imported objects always have every property:
  ```powershell
  $student.VerificationStatus = "Verified" # Fails if property doesn't exist
  ```
* ✅ **Right:** Initialize properties upon ingestion and check `.PSObject.Properties` before setting:
  ```powershell
  if ($student.PSObject.Properties['VerificationStatus']) {
      $student.VerificationStatus = "Verified"
  } else {
      $student | Add-Member -NotePropertyName 'VerificationStatus' -NotePropertyValue "Verified" -Force
  }
  ```

**Rule:** Never assume objects constructed from external data (Excel/CSV/JSON) possess your application's mutable properties. Always initialize defaults or use `Add-Member -Force`.

**Why?** In strongly-typed languages (like C# or TypeScript), classes define static fields at compile time. In dynamic scripting environments (PowerShell PSCustomObjects), an object only possesses the exact keys present when it was instantiated.

---

## 2) WPF Scope Closures & The UI Element Lookup Trap

### 2.1 The Problem

When attaching click handlers to WPF buttons in PowerShell, developers often capture local outer variables:

```powershell
# BROKEN PATTERN
$panelHealthDetails = $viewObj.FindName("PanelSheetHealthDetails")
$btnToggleHealth.Add_Click({
    $panelHealthDetails.Visibility = [System.Windows.Visibility]::Visible
})
```

When this runs, PowerShell throws:
```text
The property 'Visibility' cannot be found on this object. Verify that the property exists and can be set.
```

### 2.2 The Solution: Dynamic View Resolution & `$this`

When a function finishes executing, its local scope variables (like `$panelHealthDetails`) are cleaned up by the engine. The scriptblock attached to `.Add_Click()` runs later on the UI thread when the user clicks the button. If the outer variable has gone out of scope, it evaluates to `$null`.

To fix this, we resolve controls dynamically at the exact moment the click occurs:

```powershell
$btnToggleHealth = $viewObj.FindName("BtnToggleHealthDetails")
if ($btnToggleHealth) {
    $btnToggleHealth.Add_Click({
        # 1. Resolve parent view dynamically from global view dictionary
        $s1 = $script:views["Stage1View"]
        if (-not $s1) { return }

        # 2. Look up the panel dynamically
        $panel = $s1.FindName("PanelSheetHealthDetails")
        if (-not $panel) { return }

        # 3. Use $this to refer to the clicked button itself
        if ($panel.Visibility -eq [System.Windows.Visibility]::Visible) {
            $panel.Visibility = [System.Windows.Visibility]::Collapsed
            $this.Content = "View Details " + [char]0x25BC
        } else {
            $panel.Visibility = [System.Windows.Visibility]::Visible
            $this.Content = "Hide Details " + [char]0x25B2
        }
    })
}
```

### 2.3 Wrong vs Right

* ❌ **Wrong:** Relying on captured function variables inside WPF event handlers:
  ```powershell
  $myButton.Add_Click({ $outerVariable.DoSomething() })
  ```
* ✅ **Right:** Use `$this` for the sender and query the active view dynamically:
  ```powershell
  $myButton.Add_Click({
      $view = $script:views["ActiveView"]
      $target = $view.FindName("TargetControl")
      $target.DoSomething()
  })
  ```

**Rule:** Never use outer local function variables inside WPF event scriptblocks. Always resolve controls via `$script:views[...]` or reference the clicked control with `$this`.

**Why?** PowerShell event scriptblocks do not maintain true lexically-bound closures over temporary stack variables once the enclosing function scope exits.

---

## 3) Collapsible Sheet Health Panel & Impact Guidance

### 3.1 The Problem

The Sheet Health Audit displays whether all 7 standard columns are present. In earlier designs, this panel was permanently expanded, consuming significant vertical screen space and pushing the Verification Pipeline toolbar off the screen.

Furthermore, coordinators seeing warning alerts for missing columns did not know which missing columns actually break verification and which are merely optional.

```text
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  REGISTRATION SHEET AUDIT & SCHEMA HEALTH                                [ Update ]    │
│  103 Total Students  •  98 Exam Registered  •  6/7 Standard Columns Detected           │
│                                                                   [ View Details ▼ ]   │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 The Implementation: Compact Summary & Toggled Visibility

We redesigned the panel into two states:
1. **Collapsed State (Default)**: A slim, single-line header row displaying live metrics (`Total Students • Exam Registered • Detected/7 Standard Columns`) and a toggle button `[ View Details ▼ ]`.
2. **Expanded State**: Displays the 7 column status cards, sync timestamp, and categorized operational guidance.

```xml
<!-- Mini Summary Bar on the Header -->
<TextBlock x:Name="TxtMiniSheetHealthSummary"
           Text="103 Total Students  •  98 Exam Registered  •  6/7 Columns"
           FontFamily="IBM Plex Mono"
           FontSize="12"
           Foreground="{DynamicResource MutedBrush}"/>

<Button x:Name="BtnToggleHealthDetails"
        Content="View Details ▼"
        Style="{DynamicResource BtnSecondary}"
        Padding="10,4"/>
```

### 3.3 Critical vs Optional Column Classification

In `NPTEL-Manager.ps1`, missing columns are separated into two distinct categories:

```powershell
# Critical Columns: Automated verification CANNOT run without these
$hasCriticalMissing = ('RollNo' -in $missingCols -or 'Name' -in $missingCols -or 'Proof Receipt' -in $missingCols)

if ('RollNo' -in $missingCols) {
    $warnLines.Add("• Roll Number Missing: Required to identify students and name files on disk.")
}
if ('Name' -in $missingCols) {
    $warnLines.Add("• Student Name Missing: Required to verify receipt greeting (Rule 5).")
}
if ('Proof Receipt' -in $missingCols) {
    $warnLines.Add("• Receipt Link Missing: Required to download and verify payment receipts.")
}

# Optional Columns: System continues with graceful fallbacks
if ('Email' -in $missingCols) {
    $warnLines.Add("• Email Missing: Automated emails disabled; class notice text remains available.")
}
if ('Exam Registered' -in $missingCols) {
    $warnLines.Add("• Registration Done Missing: All respondents will be treated as registered.")
}
if ('Subject' -in $missingCols) {
    $warnLines.Add("• Subject Missing: The Course Title will be used for receipt matching.")
}
```

**Rule:** Always distinguish fatal missing data from optional convenience data in user validation feedback.

**Why?** An alert saying *"1 Column Missing"* creates unnecessary panic if the missing column is just student email, which does not prevent receipt verification.

---

## 4) Direct Native File Explorer for "Update Sheet"

### 4.1 The Problem

When a coordinator clicks `[ Update Sheet ]`, their primary intent is to browse and select the newly exported spreadsheet from Google Forms. Prompting with multiple intermediary dialogs ("Do you want to re-scan current file or pick a new file?") added unnecessary friction.

### 4.2 The Fix: Direct File Dialog Integration

In `NPTEL-Manager.ps1`:

```powershell
$btnUpdateSheet = $viewObj.FindName("BtnUpdateRegistrationSheet")
if ($btnUpdateSheet) {
    $btnUpdateSheet.Add_Click({
        # 1. Open native Windows File Explorer directly
        $newSheetPath = Show-ExcelBrowseDialog "Select Updated Student Registration Spreadsheet"
        if (-not $newSheetPath -or -not (Test-Path -LiteralPath $newSheetPath)) { return }

        # 2. Ingest, de-duplicate rows, update course record, and refresh views
        $parsed = Import-StudentSheet -Path $newSheetPath -DeDuplicate
        $script:activeCourse.RegistrationSheet = $newSheetPath
        Save-Courses $script:courses
        Select-Course $script:activeCourse
    })
}
```

**Rule:** When a user clicks a button whose name implies picking a file, launch the system file dialog immediately.

**Why?** Reducing click depth between intent and execution makes desktop applications feel responsive and purposeful.

---

## 5) `[ 📁 Import Receipts ]` Local Folder & Google Drive ZIP Ingestion Engine

### 5.1 The Problem

When students submit receipts via Google Forms:
1. Google Drive stores files in a private response folder.
2. Background scripts (like `WebClient` or `curl`) connect without browser cookies, causing Google to block anonymous downloads with an HTTP 403 or sign-in redirect (`Private link / Sign-in required`).
3. However, coordinators can easily download the entire response folder in 1 click from Google Drive as a `.zip` archive (e.g. `Upload proof of registration.zip`).
4. Coordinators needed a native way in the app to feed this `.zip` file or an unzipped folder directly into the system.

### 5.2 The UI Placement

In `UI/Views/Stage1View.xaml`, we positioned **`[ 📁 Import Receipts ]`** directly to the left of **`[ 📥 Download Receipts ]`**:

```text
┌────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ 📁 Import Receipts (Folder/.ZIP)  │  📥 Download Receipts (Drive)  │  ▶ Run Verification (OCR)         │
└────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 5.3 The 4-Tier Smart Cascade Matching Engine

Google Forms renames student uploads to:
$$\text{<Original\_Filename>} \text{ - } \text{<Student Google Name>}.\text{<ext>}$$

Our matching engine in [`modules/Download-Receipts.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/modules/Download-Receipts.ps1#L364-L569) evaluates files across 4 tiers of confidence:

```
[ Incoming File in Folder / ZIP ]
               │
               ▼
┌──────────────────────────────┐
│ Tier 1: Clean Roll Number    │ ─── Match? ──► [ Matched (100%) ]
│ (e.g. '0801CS221152')        │
└──────────────┬───────────────┘
               │ No
               ▼
┌──────────────────────────────┐
│ Tier 2: Full Student Name    │ ─── Match? ──► [ Matched (98%) ]
│ (e.g. 'Vaibhav Singh')       │
└──────────────┬───────────────┘
               │ No
               ▼
┌──────────────────────────────┐
│ Tier 3: First + Last Token   │ ─── Match? ──► [ Matched (95%) ]
│ (e.g. 'Arjun' + 'Devara')    │
└──────────────┬───────────────┘
               │ No
               ▼
┌──────────────────────────────┐
│ Tier 4: Unique First Name    │ ─── Match? ──► [ Matched (90%) ]
│ (only if unique in class)    │
└──────────────┬───────────────┘
               │ No
               ▼
       [ Missing Receipt ]
```

### 5.4 Auto-Extracting Archives with Zero-Leak Cleanup

If the coordinator selects a `.zip` file, the app automatically extracts it into a secure temporary folder and guarantees deletion in a `finally` block:

```powershell
$isArchive = $false
$tempExtractDir = $null
$scanFolder = $SourcePath

try {
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

    # ... Perform multi-tier matching and copy matched files to data/Courses/<Course>/receipts/ ...
}
finally {
    # Ensure temporary extracted files are NEVER leaked on user's disk
    if ($isArchive -and $tempExtractDir -and (Test-Path -LiteralPath $tempExtractDir)) {
        Remove-Item -LiteralPath $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
```

**Rule:** Never force the coordinator to manually unzip files. Accept both folders and `.zip` files, and clean up temporary directories in a `finally` block.

**Why?** Coordinators frequently work on shared or personal laptops. Leaving hundreds of unzipped receipt images in `$env:TEMP` clutters storage and leaks student records.

---

## 6) Rule 2 Fee Concession & Amount Normalization

### 6.1 The Problem

NPTEL examination fees follow these real-world rates:
* **₹1,000**: Standard examination fee
* **₹1,100**: Late registration fee
* **₹500**: Official 50% concession for SC / ST / PwD students
* **₹550**: Late registration with 50% concession

Previously, Rule 2 only accepted 1000 or 1100. SC/ST students who legitimately paid ₹500 were wrongly flagged with:
`"Fee amount not Rs. 1,000 or Rs. 1,100"`.

Additionally, OCR engines extract numbers formatted with commas (e.g. `Rs. 1,000.00`). When `Normalize-TextForMatching` replaced all non-alphanumeric characters with spaces, `"1,000"` became `"1 000"`, which failed the rigid contiguous regex `\b1000\b`.

### 6.2 The Fix: Multi-Amount Regex & Comma/Decimal Normalization

In [`modules/VerificationEngine.ps1`](file:///D:/Coding/Project/PDQA%20Project/Project/modules/VerificationEngine.ps1#L48-L62):

```powershell
# RULE 2: Fee Amount Check (Standard, Late, or 50% Concession)
$rule2Pass = $false

# Strip commas from raw OCR text to prevent '1,000' becoming '1 000'
$cleanAmtOcr = ($OcrText -replace ',', '')

if ($normOcr -match '\b(?:1000|1100|500|550)\b' -or 
    $cleanAmtOcr -match '\b(?:1000|1100|500|550)(?:\.00)?\b' -or 
    $normOcr -match '\b1\s+000\b' -or 
    $normOcr -match '\b1\s+100\b') {
    $rule2Pass = $true
} else {
    $null = $failedRemarks.Add("Fee amount not Rs. 1,000, Rs. 1,100, or Rs. 500")
}
```

And when generating verified remarks:

```powershell
$feeLabel = if ($normOcr -match '\b500\b' -or $cleanAmtOcr -match '\b500\b') {
    "Fee: Rs. 500 (Concession)"
} elseif ($normOcr -match '\b550\b' -or $cleanAmtOcr -match '\b550\b') {
    "Fee: Rs. 550 (Late Concession)"
} elseif ($normOcr -match '\b1100\b' -or $cleanAmtOcr -match '\b1100\b' -or $normOcr -match '\b1\s+100\b') {
    "Fee: Rs. 1,100 (Late Fee)"
} else {
    "Fee: Rs. 1,000"
}
```

### 6.3 Future-Proofing for Configurable Amounts

By organizing amount checking into a consolidated regex and label builder, the system is architected so that in the future, if NPTEL raises course fees (e.g. to ₹1,200), the accepted amount can be loaded directly from Course Settings without rewriting matching logic.

**Rule:** Always strip commas and handle optional decimal fractions (`(?:\.00)?`) before testing financial amounts against regexes.

**Why?** Payment gateways format currency as `1,000.00` or `1,000`, while students frequently write `1000`. Stripping commas guarantees uniform matching across all representations.

---

## 7) Windows PowerShell 5.1 Script Encoding & The 4-Byte Emoji Trap

### 7.1 The Problem

When saving code containing 4-byte Unicode characters (such as folder emojis `📁` or download icons `📥`) in `.ps1` files without a UTF-8 Byte Order Mark (BOM), Windows PowerShell 5.1 parses the multi-byte sequence using the active Windows ANSI code page (Windows-1252).

This corrupts the bytes into surrogate character tokens, resulting in confusing syntax errors:
```text
Unexpected token '?' in expression or statement.
The string is missing the terminator: ".
```

### 7.2 The Fix: Clean ASCII in Code Strings

To ensure 100% reliability across all PowerShell versions (PS 5.1 and PS 7+):
* **In XAML**: Unicode characters and emojis can be used safely in `.xaml` files (which are parsed as standard UTF-8 XML).
* **In PowerShell (`.ps1`)**: Avoid raw 4-byte surrogate emojis inside `.ps1` string literals. Use plain text or native character code casts (such as `[char]0x25BC` for `▼` or `[char]0x2713` for `✓`).

```powershell
# ❌ RISKY in PS 5.1 (can cause encoding corruption on non-BOM files)
$btn.Content = "📁 Import Receipts"

# ✅ SAFE across all PowerShell versions
$btn.Content = "Import Receipts"
$downArrow = [char]0x25BC # '▼'
$upArrow   = [char]0x25B2 # '▲'
```

**Rule:** Keep PowerShell `.ps1` source files strictly ASCII-clean. If special symbols are needed in code, use `[char]0xXXXX` rather than pasting raw multi-byte characters.

**Why?** Windows PowerShell 5.1 defaults to legacy local system codepages rather than UTF-8, making raw multi-byte characters fragile across different coordinators' computers.

---

## 8) Clean & Adaptive Verification Pipeline Bar (UI Decluttering & Stage 1 Morphing Bar)

### 8.1 The Problem

The initial layout of Stage 1 featured verbose informational text ("Step 1: Download Receipts...", "Step 2: Run Automated OCR...", separate warnings, and static progress placeholders). While functional, this created heavy visual clutter:
- Multiple redundant progress panels taking up vertical space.
- Excessive explanatory paragraphs that coordinators had to scroll past.
- Lack of live feedback on which student receipt was currently being downloaded, matched, or scanned.

### 8.2 The Fix: Minimalist Status Pill & Collapsible Adaptive Pipeline Bar

We stripped away all "Step 1" and "Step 2" textual overhead and replaced it with a clean, unified toolbar in `UI/Views/Stage1View.xaml`:
1. **Header Row**: Clean title `"Automated Verification Pipeline"` paired with a compact status badge pill (`TxtPipelineStatusPill`), defaulting to `"IDLE / READY"`.
2. **Adaptive Collapsible Progress Panel (`PanelPipelineProgress`)**:
   - Collapsed by default (`Visibility = Collapsed`), taking zero space during normal inspection.
   - Automatically expands whenever an operation begins (`Import`, `Download`, or `Verify`).
   - Displays a dynamic headline (e.g. `"INGESTING LOCAL ARCHIVE"`, `"DOWNLOADING RECEIPT"`, `"RUNNING WINRT OCR"`).
   - Displays real-time numerical and percentage progress (`12 / 60 (20%)`).
   - Displays a live monospace student ticker (`TxtPipelineCurrentItem`), showing the student's Roll Number, Name, and current step message:
     ```text
     220104 - Jane Doe (Matched: 220104_receipt.pdf)
     ```

### 8.3 Live Student Ticker & Multi-Mode Morphing

Instead of building 3 separate progress bars for Download, Import, and OCR, a single progress bar morphs its styling, colors, and headlines based on the active mode:

```powershell
switch ($Mode) {
    'Download' {
        $pBar.Foreground = [System.Windows.Application]::Current.FindResource("AccentBrush")
        $pPill.Text = "DOWNLOADING ($Current / $Total)"
        $pHeadline.Text = if ($Headline) { $Headline } else { "DOWNLOADING RECEIPT FROM GOOGLE DRIVE" }
    }
    'Import' {
        $pBar.Foreground = [System.Windows.Application]::Current.FindResource("SageBrush")
        $pPill.Text = "IMPORTING ($Current / $Total)"
        $pHeadline.Text = if ($Headline) { $Headline } else { "INGESTING LOCAL ARCHIVE" }
    }
    'Verify' {
        $pBar.Foreground = [System.Windows.Application]::Current.FindResource("AccentBrush")
        $pPill.Text = "VERIFYING ($Current / $Total)"
        $pHeadline.Text = if ($Headline) { $Headline } else { "RUNNING WINRT OCR ON RECEIPTS" }
    }
    'Idle' {
        $panel.Visibility = [System.Windows.Visibility]::Collapsed
        $pPill.Text = "IDLE / READY"
    }
}
```

### 8.4 Wrong vs Right

* ❌ **Wrong:** Cluttering UI panels with static multi-step text paragraphs and 3 separate progress bars:
  ```xml
  <!-- High cognitive load: duplicate headers and static instructions -->
  <TextBlock Text="Step 1: Download Receipts from Drive (Make sure links are public)" />
  <ProgressBar x:Name="DownloadProgressBar" />
  <TextBlock Text="Step 2: Run WinRT OCR Engine against downloaded receipts" />
  <ProgressBar x:Name="OcrProgressBar" />
  ```
* ✅ **Right:** One clean title, a status pill, and a single collapsible progress container that morphs to the active task:
  ```xml
  <!-- Clean, adaptive, and zero clutter when idle -->
  <TextBlock Text="Automated Verification Pipeline" FontWeight="SemiBold" />
  <Border x:Name="BadgePipelineStatus">
      <TextBlock x:Name="TxtPipelineStatusPill" Text="IDLE / READY" />
  </Border>
  ```

---

## 9) Script-Scope State Managers & WPF Dispatcher Render Pumping

### 9.1 The Problem: Closure Scope Loss in Event Handlers

When modularizing WPF event wiring, developers often define helper functions inside the initialization routine:

```powershell
function Wire-ViewEvents {
    param($viewObj)
    
    # Inner helper function definition
    function Update-PipelineBarState {
        param($Mode, $Current, $Total)
        # ... update UI ...
    }
    
    $btnDownload.Add_Click({
        Update-PipelineBarState -Mode 'Download' ...
    })
}
```

While this works during initial execution, once `Wire-ViewEvents` finishes and returns, local functions are removed from the call stack scope. When the button is subsequently clicked by the user, PowerShell fails:
```text
The term 'Update-PipelineBarState' is not recognized as the name of a cmdlet, function, script file, or operable program.
```

### 9.2 The Fix: Script-Level Function Scope

Helper functions called inside asynchronous event callbacks must be declared at **script scope** (`$script:`) or module root, so they remain permanently available throughout the entire application lifecycle:

```powershell
# In NPTEL-Manager.ps1 (Top-Level Script Scope)
function Update-PipelineBarState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        [int]$Current = 0,
        [int]$Total = 0,
        [string]$Headline = "",
        [string]$ItemText = ""
    )
    $view = $script:views["Stage1View"]
    if (-not $view) { return }
    # ... safely access UI elements and update state ...
}
```

### 9.3 60fps Non-Blocking UI Updates via Dispatcher Render Pumping

In PowerShell WPF applications, long-running loops (such as batch downloading 100 receipts or scanning OCR) run on the main UI thread. Because PowerShell does not yield execution back to WPF's internal event loop during tight `foreach` loops, the window appears to "freeze", and progress bar animations only render at 0% and 100%.

To achieve butter-smooth 60fps real-time updates, we pump the WPF Dispatcher render queue after every item update:

```powershell
# Force immediate UI repaint on the WPF Dispatcher Render priority
[System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
    [Action]{}, 
    [System.Windows.Threading.DispatcherPriority]::Render
)
```

**Rule:** Always declare UI-updating helper functions at script/module scope, and pump the Dispatcher at `Render` priority during synchronous batch operations.

**Why?** Windows Presentation Foundation queues visual redraw operations. Without an explicit Dispatcher pump, synchronous PowerShell scripts monopolize the thread, preventing WPF from painting progress updates.

---

## 10) Windows PowerShell 5.1 Inline Ternary Parser Incompatibility & The Pre-Evaluation Pattern

### 10.1 The Problem: Parser Error on Inline `(if ...)` in String Concatenation

In PowerShell 7+ (Core), developers often write inline conditional expressions inside string concatenation:

```powershell
$itemStr = "$stRoll" + (if ($stName) { " - $stName" } else { "" }) + " ($msg)"
```

While valid in modern PowerShell 7, running this line in **Windows PowerShell 5.1** triggers a fatal syntax parser error before the script even starts:

```text
At D:\...\NPTEL-Manager.ps1:2349 char:78
+ ... "$stRoll" + (if ($stName) { " - $stName" } else { "" }) + " ($msg)"
+                                       ~~~~~~~~~~~~~~~~~~~~~~~~~~~
Unexpected token '$stName" } else { "" }) + "' in expression or statement.
Unexpected token 'if' in expression or statement.
```

The Windows PowerShell 5.1 language parser does not support `if` statements as inline expression operands when chaining with binary operators (`+`).

### 10.2 The Fix: The Pre-Evaluation Pattern

Always pre-evaluate conditional string fragments into a separate local variable before performing string interpolation or concatenation:

```powershell
# Safe across PowerShell 5.1 and PowerShell 7+
$nameStr = if ($stName) { " - $stName" } else { "" }
$itemStr = "$stRoll$nameStr ($msg)"
```

### 10.3 Wrong vs Right

* ❌ **Wrong (Fails in Windows PowerShell 5.1):**
  ```powershell
  $text = "Student: " + (if ($name) { $name } else { "N/A" })
  ```
* ✅ **Right (Works across all PowerShell versions):**
  ```powershell
  $nameLabel = if ($name) { $name } else { "N/A" }
  $text = "Student: $nameLabel"
  ```

**Rule:** Never place `if` statements directly inside binary string concatenations (`+`). Always pre-assign the conditional outcome to an intermediate variable.

**Why?** Windows PowerShell 5.1 enforces strict separation between statement blocks and expression operands. Pre-assignment guarantees 100% backward compatibility on any Windows machine out of the box without requiring PowerShell 7.

---

## Topics Covered in This Chapter

1) Defensive Property Injection & Typo Tolerance in Spreadsheet Ingestion
   - 1.1 The Problem
   - 1.2 The Fix: Safe Member Initialization & Widened Regex
   - 1.3 Wrong vs Right
2) WPF Scope Closures & The UI Element Lookup Trap
   - 2.1 The Problem
   - 2.2 The Solution: Dynamic View Resolution & `$this`
   - 2.3 Wrong vs Right
3) Collapsible Sheet Health Panel & Impact Guidance
   - 3.1 The Problem
   - 3.2 The Implementation: Compact Summary & Toggled Visibility
   - 3.3 Critical vs Optional Column Classification
4) Direct Native File Explorer for "Update Sheet"
   - 4.1 The Problem
   - 4.2 The Fix: Direct File Dialog Integration
5) `[ 📁 Import Receipts ]` Local Folder & Google Drive ZIP Ingestion Engine
   - 5.1 The Problem
   - 5.2 The UI Placement
   - 5.3 The 4-Tier Smart Cascade Matching Engine
   - 5.4 Auto-Extracting Archives with Zero-Leak Cleanup
6) Rule 2 Fee Concession & Amount Normalization
   - 6.1 The Problem
   - 6.2 The Fix: Multi-Amount Regex & Comma/Decimal Normalization
   - 6.3 Future-Proofing for Configurable Amounts
7) Windows PowerShell 5.1 Script Encoding & The 4-Byte Emoji Trap
   - 7.1 The Problem
   - 7.2 The Fix: Clean ASCII in Code Strings
8) Clean & Adaptive Verification Pipeline Bar (UI Decluttering & Stage 1 Morphing Bar)
   - 8.1 The Problem
   - 8.2 The Fix: Minimalist Status Pill & Collapsible Adaptive Pipeline Bar
   - 8.3 Live Student Ticker & Multi-Mode Morphing
   - 8.4 Wrong vs Right
9) Script-Scope State Managers & WPF Dispatcher Render Pumping
   - 9.1 The Problem: Closure Scope Loss in Event Handlers
   - 9.2 The Fix: Script-Level Function Scope
   - 9.3 60fps Non-Blocking UI Updates via Dispatcher Render Pumping
10) Windows PowerShell 5.1 Inline Ternary Parser Incompatibility & The Pre-Evaluation Pattern
    - 10.1 The Problem: Parser Error on `(if ...)` in String Concatenation
    - 10.2 The Fix: The Pre-Evaluation Pattern
    - 10.3 Wrong vs Right
    - 10.4 Rule & Why

