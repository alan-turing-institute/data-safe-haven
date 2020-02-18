param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a number e.g enter '9' for DSG9)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../common_powershell/Configuration.psm1 -Force

# Get SHM config
$config = Get-ShmFullConfig($shmId)

# Temporarily switch to SHM subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName;

Write-Host "===Starting all Mirror Servers==="
Get-AzVM -ResourceGroupName "RG_SHM_PKG_MIRRORS" | Start-AzVM -NoWait

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
