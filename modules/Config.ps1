<#
.SYNOPSIS
    Config.ps1 - Configuration and state persistence module for NPTEL Management System.
#>

$script:AppConfigDir  = Join-Path $env:APPDATA 'NPTELManager'
$script:AppConfigPath = Join-Path $script:AppConfigDir 'config.json'

function Get-AppConfig {
    [CmdletBinding()]
    param()

    if (Test-Path -LiteralPath $script:AppConfigPath) {
        try {
            return Get-Content -LiteralPath $script:AppConfigPath -Raw | ConvertFrom-Json
        }
        catch {
            Write-Warning "App config corrupted, resetting to defaults."
        }
    }

    return [PSCustomObject]@{
        GoogleSheetElectivesUrl     = $null
        GoogleSheetRegistrationsUrl = $null
        GoogleSheetResultsUrl       = $null
        TesseractCliPath            = "C:\Program Files\Tesseract-OCR\tesseract.exe"
        CurrentSemester             = "Semester 5"
        CurrentAcademicYear         = "2026-2027"
        AutoVerifyThresholdConfidence = 70.0
    }
}

function Save-AppConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    if (-not (Test-Path -LiteralPath $script:AppConfigDir)) {
        New-Item -ItemType Directory -Path $script:AppConfigDir -Force | Out-Null
    }

    try {
        $Config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:AppConfigPath -Encoding UTF8
        return $true
    }
    catch {
        Write-Warning "Failed to save application config: $($_.Exception.Message)"
        return $false
    }
}
