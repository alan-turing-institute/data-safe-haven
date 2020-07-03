param(
  [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a number e.g enter '9' for DSG9)")]
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


# Stopping the package mirrors
# ----------------------------
Add-LogMessage -Level Info "Stopping all package mirror servers"
Get-AzVM -ResourceGroupName "RG_SHM_PKG_MIRRORS" | Stop-AzVM -Force -NoWait


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
