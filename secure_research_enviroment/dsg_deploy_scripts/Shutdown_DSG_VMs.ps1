param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

Write-Host "===Stopping all compute VMs==="
Get-AzVM -ResourceGroupName $config.dsg.dsvm.rg | Stop-AzVM -Force -NoWait
Write-Host "===Stopping web app servers==="
Stop-AzVM -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.gitlab.vmName -Force -NoWait
Stop-AzVM -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.hackmd.vmName -Force -NoWait
Write-Host "===Stopping dataserver==="
Stop-AzVM -ResourceGroupName $config.dsg.dataserver.rg -Name $config.dsg.dataserver.vmName -Force -NoWait
Write-Host "===Stopping RDS session hosts==="
Stop-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.sessionHost1.vmName -Force -NoWait
Stop-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.sessionHost2.vmName -Force -NoWait
Write-Host "===Stopping RDS gateway==="
Stop-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.gateway.vmName -Force -NoWait
Write-Host "===Stopping AD DC==="
Stop-AzVM -ResourceGroupName $config.dsg.dc.rg -Name $config.dsg.dc.vmName -Force -NoWait

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
