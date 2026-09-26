<#
.SYNOPSIS
    Builds NPTEL-Manager.exe from NPTEL-Manager.ps1 using ps2exe.

.DESCRIPTION
    Compiles NPTEL-Manager.ps1 into NPTEL-Manager.exe with no console window.
    The resulting exe is portable and runs with its sibling folders (modules\, UI\, assets\).
#>

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

Write-Host "NPTEL Manager Build - Creating Portable Executable" -ForegroundColor Green

# 1. Ensure ps2exe is installed
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing ps2exe module..." -ForegroundColor Yellow
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe

# 2. Compile
$srcScript = Join-Path $root 'NPTEL-Manager.ps1'
$outExe    = Join-Path $root 'NPTEL-Manager.exe'

$ps2exeArgs = @{
    inputFile    = $srcScript
    outputFile   = $outExe
    noConsole    = $true
    title        = 'NPTEL Management System'
    description  = 'Exception-based NPTEL Verification and Reporting Suite'
    product      = 'NPTEL Manager'
    version      = '1.0.0.0'
    requireAdmin = $false
}

Invoke-ps2exe @ps2exeArgs

if (Test-Path -LiteralPath $outExe) {
    Write-Host "`nBuilt: $outExe" -ForegroundColor Green
    Write-Host "The whole PDQA Project folder (exe + modules + UI + assets) is your portable app." -ForegroundColor Green
} else {
    Write-Host "`nBuild failed. See errors above." -ForegroundColor Red
}
