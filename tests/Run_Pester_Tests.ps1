#Requires -Version 7.0.0
#Requires -Modules @{ ModuleName="Az.RecoveryServices"; ModuleVersion="1.3.0" }
#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="5.1.0" }
#Requires -Modules @{ ModuleName="PSScriptAnalyzer"; ModuleVersion="1.19.0" }

# Parameter sets in Powershell are a bit counter-intuitive. See here (https://docs.microsoft.com/en-us/powershell/scripting/developer/cmdlet/cmdlet-parameter-sets?view=powershell-7) for details
param(
    [Parameter(Mandatory = $false, HelpMessage = "Name of the test(s) to run")]
    [string]$TestNameContains
)

# Set up a Pester run block with one parameter
# --------------------------------------------
$pesterBlock = {
    param($RunPath, $TestNameContains)
    Import-Module Pester -ErrorAction Stop

    # Configuration with one parameter
    $configuration = [PesterConfiguration]::Default
    $configuration.Output.Verbosity = "Detailed"
    $configuration.Run.PassThru = $true
    $configuration.Run.Path = $RunPath
    if ($TestNameContains) { $configuration.Filter.FullName = "*${TestNameContains}*" }

    # Run Pester
    $results = Invoke-Pester -Configuration $configuration
    if ($results.Result -eq "Failed") {
        throw "Tests Passed: $($results.PassedCount), Failed: $($results.FailedCount), Skipped: $($results.Skipped.Count) NotRun: $($results.NotRun.Count)"
    }
}


# Run Pester tests in a fresh Powershell context
# ----------------------------------------------
$job = Start-Job -ScriptBlock $pesterBlock -ArgumentList @((Join-Path $PSScriptRoot "pester"), $TestNameContains)
$job | Receive-Job -Wait -AutoRemoveJob
if ($job.State -eq "Failed") { exit 1 }
