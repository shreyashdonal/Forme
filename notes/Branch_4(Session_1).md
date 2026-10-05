# Branch 4 (Session 1) — Dedicated Email Management Center, Review Entry Point & Zero-Password Browser Dispatch

---

## 1) The Outreach Entry Point Pattern

### 1.1 The Problem
When a course coordinator verifies dozens or hundreds of student submissions, some records inevitably fail verification (e.g. missing receipts, wrong payment amount, blurry image, drive link access denied). These students are placed into the `Under Review` queue.

Previously, coordinators had to manually open external email programs, look up each student's email, write individual notices, and track who was contacted on paper. There was no direct bridge from the Review Queue into communication outreach.

### 1.2 The Solution
In `UI/Views/ReviewView.xaml`, we integrated a dedicated outreach action directly into the primary Mode A action bar alongside `BtnPushSolvedChanges`:

```xml
<!-- 2. Action Bar: Push Changes & Student Outreach -->
<Border Grid.Row="1"
        Background="{DynamicResource PanelBrush}"
        BorderBrush="{DynamicResource BorderBrush}"
        BorderThickness="1"
        CornerRadius="10"
        Padding="16,10"
        Margin="0,0,0,12">
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <!-- Push Button (Left) -->
        <Button x:Name="BtnPushSolvedChanges"
                Grid.Column="0"
                Content="Push Changes to Main Sheet"
                ... />

        <!-- Status Indicator (Middle) -->
        <StackPanel Grid.Column="1" ... >
            <TextBlock x:Name="TxtPushChangesBadge" ... />
        </StackPanel>

        <!-- Send Email to Flagged Students (Right) -->
        <Button x:Name="BtnNotifyFlaggedStudents"
                Grid.Column="2"
                Content="✉ Send Email to Flagged Students"
                Style="{DynamicResource BtnSecondary}"
                Padding="16,8"
                FontSize="12"
                FontWeight="SemiBold"
                Cursor="Hand"
                ToolTip="Open the Email Management Center to notify flagged students with issues"/>
    </Grid>
</Border>
```

In `NPTEL-Manager.ps1`, `Update-ReviewView` dynamically updates the button with the live student count:

```powershell
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
```

---

## 2) Two-Column Email Management Center Architecture

### 2.1 Design Objectives
1. **Clean Workspace**: Use the Warm Dark Minimalist palette (`#151513` canvas, `#1E1E1B` panel, `#E8B04B` accent).
2. **Selective Batching**: Allow coordinators to check/uncheck individual students or use 1-click `Select All` / `Clear All`.
3. **Live Feedback**: Show immediate metrics for queued recipients, students already notified, and discrepancy breakdown.
4. **Standardized Notices**: Give coordinators pre-written institutional templates with clear instructions and deadlines.

### 2.2 Layout Structure (`UI/Views/EmailView.xaml`)
```
+-----------------------------------------------------------------------------------------+
| COURSES > COURSE NAME > STAGE 1 — EMAIL MANAGEMENT CENTER         [ ← Back to Review ]  |
| Student Notification & Email Center                              [ 3 Flagged Queued ]  |
+-----------------------------------------------------------------------------------------+
| [ FLAGGED RECIPIENTS: 3 ] | [ ALREADY NOTIFIED: 1 ] | [ DISCREPANCY SUMMARY: 2 Missing ]|
+-----------------------------------------------------------------------------------------+
| LEFT (420px): RECIPIENT ROSTER              | RIGHT (*): NOTICE COMPOSER & PREVIEW      |
| [Select All] [Clear All]                    | [Missing Receipt] [Fee Mismatch] [General]|
|                                             |                                           |
| [X] Sneha Sharma (Roll: 101)                | EMAIL SUBJECT:                            |
|     sneha@college.edu                       | [URGENT] Action Required: Missing Exam... |
|     [Missing Receipt] [✓ Notified]          |                                           |
|                                             | NOTICE BODY PREVIEW:                      |
| [X] Rahul Verma (Roll: 102)                 | Dear Student,                             |
|     rahul@college.edu                       | During institutional verification...      |
|     [Fee Rs. 500 Discrepancy]               |                                           |
|                                             | +---------------------------------------+ |
|                                             | | [📋 Copy Notice]   [✉ Open in Gmail] | |
|                                             | | [📋 Copy BCC]                         | |
|                                             | +---------------------------------------+ |
+-----------------------------------------------------------------------------------------+
```

---

## 3) Zero-Password Browser Draft Dispatch (Sub-Branch 4.1)

### 3.1 The Problem with SMTP Setup
Configuring SMTP requires coordinators to:
1. Enable 2-Factor Authentication on their Google accounts.
2. Generate an external 16-character Google App Password.
3. Configure ports, server addresses (`smtp.gmail.com`), and security protocols.

Many college coordinators do not have permissions or technical comfort to generate App Passwords, or their institutions enforce restricted SSO logins.

### 3.2 The Zero-Password Solution: Gmail Web Compose URL
By constructing a URL conforming to Google's Web Compose interface, the app launches the coordinator's default web browser with all fields pre-filled:

```powershell
$bccList = ($emails | Select-Object -Unique) -join ","
$encBcc = [System.Uri]::EscapeDataString($bccList)
$encSub = [System.Uri]::EscapeDataString($subText)
$encBody = [System.Uri]::EscapeDataString($bodyText)

$gmailUrl = "https://mail.google.com/mail/?view=cm&fs=1&tf=1&bcc=$encBcc&su=$encSub&body=$encBody"
[System.Diagnostics.Process]::Start($gmailUrl)
```

### 3.3 Critical Privacy Feature: BCC Addressing
All selected student email addresses are placed into the **`bcc`** parameter rather than `to` or `cc`.
- **Privacy Protection**: FERPA / privacy guidelines prevent exposing all flagged students' email addresses to one another.
- **Single Dispatch**: The coordinator reviews the draft in their browser and clicks "Send" once, delivering individual copies to all students simultaneously.

---

## 4) Multi-Channel Communication: WhatsApp & Telegram Tools

Not all students check their academic email promptly. Coordinators often post announcements on department WhatsApp groups, Telegram channels, or official notice boards.

We provided two 1-click clipboard utilities:
1. **`[ 📋 Copy Notice Text ]`**: Copies the full formatted template to the Windows clipboard using `[System.Windows.Clipboard]::SetText($txtBody.Text)`.
2. **`[ 📋 Copy BCC Emails ]`**: Formats the selected student emails as a comma-separated list (`student1@edu, student2@edu`) so coordinators can paste them into Outlook, Thunderbird, or mobile mail apps.

---

## 5) Audit Tracking & Delivery Status

When the coordinator clicks `[ ✉ Open in Gmail (Web Draft) ]`:
1. The recipients' emails are passed to `Mark-SelectedStudentsNotified`:
   ```powershell
   $nowStr = (Get-Date).ToString("yyyy-MM-dd HH:mm")
   foreach ($s in $students) {
       if ($s.Email -and ($s.Email.Trim().ToLower() -eq $cleanEm)) {
           $s | Add-Member -NotePropertyName "Notified" -NotePropertyValue $true -Force
           $s | Add-Member -NotePropertyName "NotifiedTimestamp" -NotePropertyValue $nowStr -Force
       }
   }
   ```
2. The records are saved to `data/Courses/<CourseName>/students.json`.
3. The UI refreshes immediately:
   - A sage green pill appears on each contacted student card: `[ ✓ Notified (2026-10-05 14:48) ]`.
   - The mini-dashboard metric `ALREADY NOTIFIED` increments automatically.

---

## 6) SPA Router Integration & Tab State

The SPA router in `NPTEL-Manager.ps1` was updated so that navigating between `Stage1View`, `ReviewView`, and `EmailView` preserves navigation tab styling:

```powershell
if ($NavBtnCourses) {
    $NavBtnCourses.Style = if ($ViewName -eq "CoursesView" -or
                              $ViewName -eq "WorkspaceView" -or
                              $ViewName -eq "Stage1View" -or
                              $ViewName -eq "Stage2View" -or
                              $ViewName -eq "ReviewView" -or
                              $ViewName -eq "EmailView") { $activeStyle } else { $defaultStyle }
}
```

The coordinator can navigate seamlessly:
`Stage 1 (Automated Verification)` ➔ `Review Queue` ➔ `Email Management Center` ➔ `Review Queue` ➔ `Stage 1`.

---

---

## 7) The Two-Function Composer Architecture: Standard Template vs Custom Draft

### 7.1 The Limitation of Discrete Issue Presets
Initially, the Composer featured 3 preset buttons (*Missing Receipt*, *Fee Mismatch*, *General Notice*). However, in actual departmental operations:
1. When sending a batch **BCC email** to multiple flagged students, each student may have failed different rules (one has a missing receipt, another has a ₹0 fee, a third has a blurry image).
2. The coordinator cannot send multiple separate emails for every failure permutation.
3. In *every* case, the requested student action is identical: **"Your receipt failed verification. Resubmit a new receipt that satisfies the mandatory rules."**

### 7.2 The Solution
We consolidated the composer into two clear operational modes:
- **`[ 📋 Standard Template (5 Rules) ]`**: Automatically pre-fills an authoritative, institutional resubmission notice detailing the 5 mandatory verification criteria (Payment Status, Fee Amount, Course Name, Platform Authenticity, Student Identity) and common rejection reasons.
- **`[ ✏️ Custom Draft Mail ]`**: Provides an editable canvas with dynamic subject line and starter skeleton for custom announcements (e.g. Google Form resubmission links, physical lab verification schedules, deadline extensions).

---

## 8) Identity Resolution & Shared Email Collision Handling

### 8.1 The Shared Email Bug
In real-world testing (e.g. Google Forms responses), students frequently enter identical test emails (e.g. `satishmandloi301@gmail.com`). 
When notification dispatch matched students strictly by `Email` with a single `break` statement:
1. It matched the first student in the roster sharing that email (even if already `Verified`).
2. It terminated search, completely skipping the second student who was actually `Under Review`.
3. Consequently, only 1 of 2 flagged students was recorded as notified.

### 8.2 The Roll Number Keying Fix
`Mark-SelectedStudentsNotified` was refactored:
- Checkbox selections now pass the full student objects via `Get-SelectedStudents`.
- A student is indexed by their unique **`RollNo`** (with `Email` only as secondary fallback).
- A defensive filter (`if ($s.VerificationStatus -ne "Under Review") { continue }`) guarantees verified students are never touched.
- All selected students are evaluated without premature `break` termination.

---

## 9) PowerShell WPF Scope Closure & Top-Level Handler Promotion

### 9.1 The Trap of Nested Event Scriptblocks
In PowerShell WPF scripting, declaring a helper scriptblock inside an event setup block (e.g. `$setTpl = { param(...) ... }` inside `Setup-ViewEventBindings`) and binding it to an event via `$btn.Add_Click({ & $setTpl "..." })` creates a scope closure trap:
- When the application starts and executes `Setup-ViewEventBindings`, `$setTpl` exists as a local variable within that execution frame.
- When the coordinator later clicks the button in the UI, the WPF `Click` event runs on the dispatcher thread inside a distinct execution scope where `$setTpl` is out of scope (`$null`).
- PowerShell attempts to evaluate `& $null "CustomDraft"` and throws a runtime exception:
  > `The expression after '&' in a pipeline element produced an object that was not valid. It must result in a command name, a script block, or a CommandInfo object.`

### 9.2 The Solution: Module-Scoped Controller Functions
In PowerShell GUI architectures, never store event action logic in local variables across event boundaries. Instead:
1. Promote the logic to a first-class script-scoped function (`function Set-EmailTemplate { param([string]$TplName) ... }`).
2. Bind the WPF click event handler directly to the function call without variable indirection:
   ```powershell
   $btnTplStandard.Add_Click({ Set-EmailTemplate "StandardTemplate" })
   $btnTplCustom.Add_Click({ Set-EmailTemplate "CustomDraft" })
   ```
This guarantees the command resolves consistently across all WPF dispatcher thread invocations.

---

## 10) UI Decluttering & Minimalism Design Principles

### 10.1 The Visual Fatigue Problem
In enterprise and academic software, developers often fall into the trap of over-explaining features with subtitles, paragraph-length hints, and verbose button titles (e.g. `OFFICIAL NOTICE COMPOSER - 5-rule compliance notice for resubmission or custom coordinator draft`). 
This creates cognitive clutter, consumes valuable vertical screen space, and makes the interface look dated.

### 10.2 Principles Applied in the Email Center Redesign
1. **Self-Evident Controls**: Action buttons should say what they do directly (`[ 📋 Standard (5 Rules) ]`, `[ ✏️ Custom Draft ]`, `[ ✉ Open in Gmail ]`) rather than carrying long marketing or descriptive labels.
2. **Elimination of Redundant State Indicators**: The left-hand roster already only contains students with `Under Review` status; having a prominent gray banner reading `"Showing students with 'Under Review' status"` was pure noise. Removing it provided an extra 30px of vertical list height.
3. **Card Noise Reduction**: Metric cards should highlight the key number and its identity (`FLAGGED: 2`, `NOTIFIED: 1`, `ISSUES: 2 Missing Receipt`) without explanatory third-line text (`"Awaiting notice dispatch"`).
4. **Focused Context**: Main page titles are kept crisp (`Email Center`), while context is provided via concise breadcrumbs (`COURSES > SOFT COMPUTING > EMAIL OUTREACH`).

---

## 11) 2-Way Delivery Status Management: Automated Dispatch vs Manual Audit Rollback

### 11.1 The Risk of Unchecked Auto-Marking
In automated web-draft dispatch (`[ ✉ Open in Gmail ]`), our desktop application hands off an RFC-compliant URL to the operating system's default browser.
However, from an audit and reliability standpoint:
- The coordinator might close the browser tab without hitting the "Send" button.
- The web browser could fail to load or lose network connectivity.
- The coordinator might choose to send the notice through an external system (e.g., college ERP or MS Outlook) instead of Gmail.
If our software blindly assumes delivery succeeded upon browser launch and locks the records as `Notified`, future coordinator audits are corrupted.

### 11.2 The Dual-Path Solution
We implemented a 2-way delivery audit system:
1. **Way 1: Automated Draft Dispatch (`[ ✉ Open in Gmail ]`)**:
   - Launches Gmail Web Compose with pre-filled BCC recipients and notice body.
   - Automatically marks selected students as `Notified = $true` with formatted timestamps.
   - Displays an informative tip alerting the coordinator that if the send was aborted, status can be instantly reverted.
2. **Way 2: Manual Coordinator Controls (`[ ✓ Mark Notified ]` & `[ ↺ Unmark ]`)**:
   - **`[ ✓ Mark Notified ]`**: Operates on currently selected students. Updates `Notified = $true` and records the current timestamp in `students.json`, incrementing the `NOTIFIED` dashboard counter and rendering green `✓ Notified` pills on student cards.
   - **`[ ↺ Unmark ]`**: Operates on currently selected students. Resets `Notified = $false` and clears `NotifiedTimestamp` in `students.json`, decrementing the `NOTIFIED` dashboard counter and stripping the green badge.
   - Functions (`Mark-SelectedStudentsNotified` and `Unmark-SelectedStudentsNotified`) return the matched count and guard against touching already verified students.

---

## 12) Decommissioning Redundant State Transitions: The "Flag for Resubmit" Elimination

### 12.1 The Redundant State Transition Trap
A common architectural flaw in workflow management tools is providing a button that transitions an entity into a state it already occupies:
- In the NPTEL Operations Studio, all student records that fail automated verification (OCR fee mismatch, title mismatch, blurry image, missing file) are **automatically assigned the status `Under Review`**.
- The Review Queue (Mode A) filters exclusively for students who are `Under Review`.
- When the coordinator opens a student in the detailed inspection workspace (Mode B), that student is **already under review**.
- Having a button labeled `[ Flag for Resubmit ]` on an already-flagged student introduced unnecessary cognitive overhead, misleading coordinators into thinking they had to take an explicit action just to maintain the rejected status.

### 12.2 Streamlined Decision Architecture
By eliminating `BtnFlagResubmit` and the `ModalFlagResubmit` dialog:
1. **Single Primary Mode B Action**: The coordinator has exactly one primary positive action: **`[ Approve (Override) ]`** if human inspection determines the receipt is valid despite OCR flags.
2. **Default Inaction = Maintained Flag**: If the receipt is invalid, blurry, or missing, the coordinator simply does nothing. The student remains `Under Review`.
3. **Seamless Hand-Off to Outreach**: When the coordinator returns to the queue and clicks **`[ ✉ Send Email to Flagged Students ]`**, all remaining `Under Review` students are automatically routed to the Email Center for batch 5-rule resubmission notice dispatch.

---

## 13) Table of Contents

- [1) The Outreach Entry Point Pattern](#1-the-outreach-entry-point-pattern)
- [2) Two-Column Email Management Center Architecture](#2-two-column-email-management-center-architecture)
- [3) Zero-Password Browser Draft Dispatch (Sub-Branch 4.1)](#3-zero-password-browser-draft-dispatch-sub-branch-41)
- [4) Multi-Channel Communication: WhatsApp & Telegram Tools](#4-multi-channel-communication-whatsapp--telegram-tools)
- [5) Audit Tracking & Delivery Status](#5-audit-tracking--delivery-status)
- [6) SPA Router Integration & Tab State](#6-spa-router-integration--tab-state)
- [7) The Two-Function Composer Architecture: Standard Template vs Custom Draft](#7-the-two-function-composer-architecture-standard-template-vs-custom-draft)
- [8) Identity Resolution & Shared Email Collision Handling](#8-identity-resolution--shared-email-collision-handling)
- [9) PowerShell WPF Scope Closure & Top-Level Handler Promotion](#9-powershell-wpf-scope-closure--top-level-handler-promotion)
- [10) UI Decluttering & Minimalism Design Principles](#10-ui-decluttering--minimalism-design-principles)
- [11) 2-Way Delivery Status Management: Automated Dispatch vs Manual Audit Rollback](#11-2-way-delivery-status-management-automated-dispatch-vs-manual-audit-rollback)
- [12) Decommissioning Redundant State Transitions: The "Flag for Resubmit" Elimination](#12-decommissioning-redundant-state-transitions-the-flag-for-resubmit-elimination)




