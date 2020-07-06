param(
  [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName


# Stopping the deployment servers
# -------------------------------
Add-LogMessage -Level Info "Stopping all Deployment Servers"
Get-AzVM -ResourceGroupName "RG_SHM_DEPLOYMENT_POOL" | Stop-AzVM -Force -NoWait


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
