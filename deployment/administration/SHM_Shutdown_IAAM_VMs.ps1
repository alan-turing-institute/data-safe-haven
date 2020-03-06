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

Add-LogMessage -Level Info "Stopping NPS Server"
Stop-AzVM -ResourceGroupName $config.nps.rg -Name $config.nps.vmName -Force -NoWait
Add-LogMessage -Level Info "Stopping AD DCs"
Stop-AzVM -ResourceGroupName $config.dc.rg -Name $config.dc.vmName -Force -NoWait
Stop-AzVM -ResourceGroupName $config.dc.rg -Name $config.dcb.vmName -Force -NoWait

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
