param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a number e.g enter '9' for DSG9)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName


# Start/restart the package mirrors
# ---------------------------------
Add-LogMessage -Level Info "Starting all Mirror Servers"
Get-AzVM -ResourceGroupName "RG_SHM_PKG_MIRRORS" | ForEach-Object { Enable-AzVM -Name $_.Name -ResourceGroupName $_.ResourceGroupName }


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
