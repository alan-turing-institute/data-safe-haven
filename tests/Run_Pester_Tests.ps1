Import-Module Pester -ErrorAction Stop


# Set Pester configuration
# ------------------------
$configuration = [PesterConfiguration]::Default
$configuration.Output.Verbosity = "Detailed"
$configuration.Run.Exit = $true
$configuration.Run.Path = (Join-Path $PSScriptRoot "pester")


# Run Pester tests
# ----------------
Invoke-Pester -Configuration $configuration
