# Set up a Pester run block with one parameter
# --------------------------------------------
$pesterBlock = {
    param($RunPath)
    Import-Module Pester -ErrorAction Stop

    # Configuration with one parameter
    $configuration = [PesterConfiguration]::Default
    $configuration.Output.Verbosity = "Detailed"
    $configuration.Run.PassThru = $true
    $configuration.Run.Path = $RunPath

    # Run Pester
    $results = Invoke-Pester -Configuration $configuration
    if ($results.Result -eq "Failed") {
        throw "Tests Passed: $($results.PassedCount), Failed: $($results.FailedCount), Skipped: $($results.Skipped.Count) NotRun: $($results.NotRun.Count)"
    }
}


# Run Pester tests in a fresh Powershell context
# ----------------------------------------------
$job = Start-Job -ScriptBlock $pesterBlock -Arg (Join-Path $PSScriptRoot "pester") #| Receive-Job -Wait -AutoRemoveJob
$job | Receive-Job -Wait -AutoRemoveJob
if ($job.State -eq "Failed") { exit 1 }
