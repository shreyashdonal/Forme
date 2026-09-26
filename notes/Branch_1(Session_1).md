# Branch 1 (Session 1) — Web Developer's Guide & Session Notes

> **Target Audience:** Web Developer learning the PowerShell + WPF Desktop Stack  
> **Topic:** Modular UI Architecture, SPA Routing, Theme Tokens, and Course Registration  
> **Date:** September 2026  

---

## 1. The Big Picture: Desktop vs. Web Architecture

If you know **React**, **HTML/CSS**, and **Node.js**, building a desktop app with **PowerShell + WPF** is surprisingly similar once you learn the vocabulary:

| Web Concept (React / HTML) | WPF + PowerShell Desktop Equivalent | What It Does |
| :--- | :--- | :--- |
| **HTML / JSX** | **XAML (`.xaml`)** | Markup language for building layout, UI elements, and styling. |
| **CSS Variables / Design Tokens** | **`ResourceDictionary` (`Theme.xaml`)** | Centralized colors, fonts, border radii, and button styles. |
| **React Components (`<Component/>`)** | **`UserControl` (`UI/Views/*.xaml`)** | Modular, reusable UI views created as separate files. |
| **React Router (`<Outlet/>`)** | **`ContentControl` (`ViewContainer`)** | The container in the shell where active views are swapped dynamically. |
| **JavaScript `onClick` Handler** | **`$button.Add_Click({ ... })`** | Script block that runs whenever the user clicks a button. |
| **HTML `data-*` Attributes** | **WPF `.Tag` Property** | Custom data attached to any UI element (e.g. `$btn.Tag = $course.Id`). |
| **`localStorage` / Local JSON DB** | **`data/courses.json`** | Simple local JSON file where state is persisted between app launches. |

---

## 2. What We Built in Branch 1 (Session 1)

### 2.1 The Theme System (`UI/Styles/Theme.xaml`)
In CSS, you define custom properties in `:root`:
```css
:root {
  --bg-primary: #151513;
  --panel: #1E1E1B;
  --accent: #E8B04B;
  --text: #EAE6DD;
}
```
In WPF, we define them inside a **`ResourceDictionary`**:
```xml
<SolidColorBrush x:Key="BgBrush" Color="#151513"/>
<SolidColorBrush x:Key="PanelBrush" Color="#1E1E1B"/>
<SolidColorBrush x:Key="AccentBrush" Color="#E8B04B"/>
<SolidColorBrush x:Key="TextBrush" Color="#EAE6DD"/>
```
And we defined reusable button styles:
- **`BtnPrimary`**: Amber accent button (`#E8B04B`) for main actions (e.g., Save, Submit).
- **`BtnSecondary`**: Subtle dark button with a 1px border (`#2A2A24`) for secondary actions (e.g., Browse, Cancel).
- **`BtnNav` / `BtnNavActive`**: Clean pill buttons for top navigation.

---

### 2.2 The App Shell (`UI/MainWindow.xaml`)
Think of `MainWindow.xaml` as your **`App.jsx`** or **`layout.tsx`**:
- **Fixed Top Header**:
  - Logo (`NPTEL Operations Studio`).
  - Active course status badge (`TxtStatusBadge`).
  - Navigation links: `[ Home ]`, `[ Courses ]`, `[ Settings ]`.
- **Dynamic Content Outlet**:
  ```xml
  <ContentControl x:Name="ViewContainer"/>
  ```
  Instead of rendering all views in one giant monolithic file, `ViewContainer` starts empty. Whenever the user clicks a tab or button, our router injects the appropriate view inside this container.

---

### 2.3 The SPA Router in PowerShell (`NPTEL-Manager.ps1`)
In a React app, you use `useNavigate()` to change pages without reloading:
```javascript
navigate('/dashboard');
```
In our PowerShell controller, we created the **`Navigate-To`** function:
```powershell
function Navigate-To {
    param([string]$ViewName)

    # 1. Get or load the requested UserControl (e.g. HomeView, CoursesView)
    $view = Get-OrCreateView $ViewName

    # 2. Swap it into the shell's ViewContainer outlet
    $script:viewContainer.Content = $view

    # 3. Update top navigation button highlighting (BtnNavActive vs BtnNav)
    Update-NavState $ViewName
}
```
This gives us a lightning-fast, smooth Single Page Application (SPA) experience on the desktop.

---

### 2.4 The Home Launcher & Registration Form (`UI/Views/HomeView.xaml`)
Instead of opening a separate popup window or immediately forcing the user into a form, `HomeView` uses a **two-state panel toggle** (like conditional rendering in React: `{isRegistering ? <Form/> : <WelcomeCards/>}`):

1. **`PanelHomeWelcome` (Default Visible)**:
   - Card 1: `+ Register Course` (reveals setup form).
   - Card 2: `View Courses ->` (navigates to Courses Hub).
   - A clean guide explaining the 2-stage semester lifecycle.
2. **`PanelRegisterForm` (Hidden by default)**:
   - Smoothly slides in when `+ Register Course` is clicked.
   - Collects: Course Title, Course Code, Department, Semester, and Registration Spreadsheet path.
   - Includes `<- Back to Home` and `Cancel` buttons to return to the launcher.

---

### 2.5 Strict Course Validation & Storage (`data/courses.json`)
Before creating a course, we validate:
1. **Title Required**: The course name cannot be blank.
2. **Spreadsheet Required**: An `.xlsx`, `.xls`, or `.csv` spreadsheet must be selected.
3. **File Must Exist on Disk**: We check `Test-Path $sheet` so broken paths can never enter the database.

Once validated, the course object is appended to `$script:courses` and saved as formatted JSON into `data/courses.json`.

---

## 3. Critical PowerShell & WPF Gotchas (Web Dev Edition)

If you are coming from JavaScript/Web, here are the most important quirks we solved:

### ⚠️ Gotcha 1: PowerShell Event Closures vs JavaScript Closures
In JavaScript, functions retain access to outer variables via closures:
```javascript
const nameInput = document.getElementById('name');
button.addEventListener('click', () => {
    console.log(nameInput.value); // Always works in JS
});
```
**In PowerShell 5.1, this fails!**  
When a PowerShell function exits, its local variables (`$nameInput`) are destroyed from memory. When the WPF button is clicked 5 minutes later, `$nameInput` evaluates to `$null`, throwing:
> `You cannot call a method on a null-valued expression.`

**The Fix:**
Always look up controls dynamically at the exact moment of the click:
```powershell
$button.Add_Click({
    $view = $script:views["HomeView"]
    $nameInput = $view.FindName("TxtCourseName")
    $value = $nameInput.Text.Trim()
})
```

---

### ⚠️ Gotcha 2: Loop Variables inside Clicks (Use `.Tag` like `data-*`)
In a loop rendering multiple course cards:
```powershell
# BAD: Loop variable $c is destroyed or overwritten by the next loop iteration
foreach ($c in $courses) {
    $btn.Add_Click({ Open-Course $c }) # $c will be null or the last item!
}
```
**The Fix:**
In web dev, you attach IDs to buttons with `data-id="123"`. In WPF, every UI element has a **`.Tag`** property designed for this exact purpose:
```powershell
foreach ($c in $courses) {
    $btn.Tag = [string]$c.Id
    $btn.Add_Click({
        # $this refers to the clicked WPF Button
        $clickedId = [string]$this.Tag
        $course = $script:courses | Where-Object { $_.Id -eq $clickedId }
        Select-Course $course
    })
}
```

---

### ⚠️ Gotcha 3: Reserved Variable Trap in PowerShell
In PowerShell, certain variable names are **system constants**:
- `$home` $\rightarrow$ points to your Windows user directory (e.g. `C:\Users\Asus`).
- `$host` $\rightarrow$ PowerShell host engine.
- `$profile` $\rightarrow$ PowerShell user profile script path.

Never use `$home = ...` in PowerShell! We use `$homeView` or `$viewHome`.

---

### ⚠️ Gotcha 4: WPF `Thickness` Constructor Overloads
In CSS: `padding: 12px 6px;` (2 values: vertical, horizontal).  
In WPF, calling `New-Object System.Windows.Thickness(12, 6)` **throws an error** because the .NET constructor only supports:
- 1 argument: Uniform padding `Thickness(10)`
- 4 arguments: Left, Top, Right, Bottom `Thickness(12, 6, 12, 6)`

Always pass 4 arguments: `New-Object System.Windows.Thickness(12, 6, 12, 6)`.

---

## 4. Summary of Files Created / Touched in Branch 1 Session 1

- [`UI/Styles/Theme.xaml`](file:///D:/Coding/Project/PDQA%20Project/UI/Styles/Theme.xaml): Central design tokens, color palette, and component styles.
- [`UI/MainWindow.xaml`](file:///D:/Coding/Project/PDQA%20Project/UI/MainWindow.xaml): Application shell, navigation bar, and view container outlet.
- [`UI/Views/HomeView.xaml`](file:///D:/Coding/Project/PDQA%20Project/UI/Views/HomeView.xaml): Welcome action cards + toggleable course registration form.
- [`UI/Views/CoursesView.xaml`](file:///D:/Coding/Project/PDQA%20Project/UI/Views/CoursesView.xaml): Course cards list and empty state.
- [`UI/Views/DashboardView.xaml`](file:///D:/Coding/Project/PDQA%20Project/UI/Views/DashboardView.xaml): Active course workspace.
- [`data/courses.json`](file:///D:/Coding/Project/PDQA%20Project/data/courses.json): Persistent course store.
- [`NPTEL-Manager.ps1`](file:///D:/Coding/Project/PDQA%20Project/NPTEL-Manager.ps1): Router controller and event wire-up.
