# Set up a Pester run block with one parameter
# --------------------------------------------
$pesterBlock = {
    param($RunPath)
    Import-Module Pester -ErrorAction Stop

    # Configuration with one parameter
    $configuration = [PesterConfiguration]::Default
    $configuration.Output.Verbosity = "Detailed"
    $configuration.Run.Exit = $true
    $configuration.Run.Path = $RunPath

    # Run Pester
    Invoke-Pester -Configuration $configuration
}


# Run Pester tests in a fresh Powershell context
# ----------------------------------------------
Start-Job -ScriptBlock $pesterBlock -Arg (Join-Path $PSScriptRoot "pester") | Receive-Job -Wait -AutoRemoveJob
