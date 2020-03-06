param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a number e.g enter '9' for DSG9)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force

# Get SHM config
$config = Get-ShmFullConfig($shmId)

# Temporarily switch to SHM subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName;

Add-LogMessage -Level Info "Starting all Mirror Servers"
Get-AzVM -ResourceGroupName "RG_SHM_PKG_MIRRORS" | Restart-AzVM -NoWait

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
