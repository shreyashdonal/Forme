<#
.SYNOPSIS
    DataSync.ps1 - Ingests published Google Sheets CSV data without requiring OAuth or API keys.
#>

function Import-PublishedCsvUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CsvUrl
    )

    try {
        $response = Invoke-WebRequest -Uri $CsvUrl -UseBasicParsing -TimeoutSec 15
        if ($response.StatusCode -eq 200) {
            $data = $response.Content | ConvertFrom-Csv
            return $data
        }
    }
    catch {
        Write-Error "Failed to fetch data from CSV URL ($CsvUrl): $($_.Exception.Message)"
        return $null
    }
}

function Join-CohortData {
    <#
    .SYNOPSIS
        Joins Elective Selections and Exam Registrations by student Roll Number.
    #>
    param(
        [array]$Electives,
        [array]$Registrations
    )

    $joined = @()
    foreach ($el in $Electives) {
        $reg = $Registrations | Where-Object { $_.'Roll Number' -eq $el.'Roll Number' } | Select-Object -First 1
        $joined += [PSCustomObject]@{
            RollNo           = $el.'Roll Number'
            Name             = $el.'Name'
            Branch           = $el.'Branch'
            SelectedElective = $el.'Selected Elective'
            RegisteredCourse = if ($reg) { $reg.'NPTEL Course' } else { $null }
            RegistrationId   = if ($reg) { $reg.'Registration ID' } else { $null }
            ReceiptPath      = if ($reg) { $reg.'Payment Receipt' } else { $null }
            ConfirmationPath = if ($reg) { $reg.'Confirmation Email' } else { $null }
            HasSubmittedReg  = ($null -ne $reg)
        }
    }
    return $joined
}
