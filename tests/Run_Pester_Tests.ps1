param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az -ErrorAction Stop
Import-Module Pester -ErrorAction Stop
# Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
# Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
# Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
# Import-Module $PSScriptRoot/../../common/Mirrors -Force -ErrorAction Stop
# Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop
# Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Run Pester tests
# ----------------
Invoke-Pester $(Join-Path $PSScriptRoot "pester")


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext