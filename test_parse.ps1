try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Xaml

    # 1. Test Theme
    $themeXaml = Get-Content -LiteralPath "$PSScriptRoot\UI\Styles\Theme.xaml" -Raw -Encoding UTF8
    $readerTheme = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($themeXaml))
    $theme = [System.Windows.Markup.XamlReader]::Load($readerTheme)
    Write-Host "[OK] Theme.xaml parsed successfully."

    if (-not [System.Windows.Application]::Current) {
        $null = New-Object System.Windows.Application
    }
    [System.Windows.Application]::Current.Resources.MergedDictionaries.Add($theme)

    # 2. Test MainWindow
    $mainXaml = Get-Content -LiteralPath "$PSScriptRoot\UI\MainWindow.xaml" -Raw -Encoding UTF8
    $readerMain = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($mainXaml))
    $win = [System.Windows.Markup.XamlReader]::Load($readerMain)
    Write-Host "[OK] MainWindow.xaml parsed successfully. Title: $($win.Title)"

    # 3. Test Views
    Get-ChildItem -Path "$PSScriptRoot\UI\Views" -Filter "*.xaml" | ForEach-Object {
        $vXaml = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
        $vReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($vXaml))
        $vObj = [System.Windows.Markup.XamlReader]::Load($vReader)
        Write-Host "[OK] View $($_.Name) parsed successfully into $($vObj.GetType().Name)."
    }

} catch {
    Write-Host "XAML ERROR: $_"
    exit 1
}

try {
    $null = [System.Management.Automation.ScriptBlock]::Create(
        (Get-Content -LiteralPath "$PSScriptRoot\NPTEL-Manager.ps1" -Raw -Encoding UTF8)
    )
    Write-Host "[OK] NPTEL-Manager.ps1 syntax and scriptblock compilation OK"

    # 4. Test Modules
    Get-ChildItem -Path "$PSScriptRoot\modules" -Filter "*.ps1" | ForEach-Object {
        $null = [System.Management.Automation.ScriptBlock]::Create(
            (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8)
        )
        Write-Host "[OK] Module $($_.Name) syntax and scriptblock compilation OK"
    }
} catch {
    Write-Host "PS1 ERROR: $_"
    exit 1
}
