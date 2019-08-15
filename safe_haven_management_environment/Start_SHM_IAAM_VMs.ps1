param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../new_dsg_environment/dsg_deploy_scripts/DsgConfig.psm1 -Force

# Get SHM config
$config = Get-ShmFullConfig($shmId)

# Temporarily switch to SHM subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName;

Write-Host "===Starting AD DCs==="
Write-Host " - Waiting for Primary AD to start before starting other VMs."
Start-AzVM -ResourceGroupName $config.dc.rg -Name $config.dc.vmName
Write-Host " - Waiting for Backup AD to start before starting other VMs."
Start-AzVM -ResourceGroupName $config.dc.rg -Name $config.dcb.vmName
Write-Host "===Starting NPS Server==="
Start-AzVM -ResourceGroupName $config.nps.rg -Name $config.nps.vmName

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
