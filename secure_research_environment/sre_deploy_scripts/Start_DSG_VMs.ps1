param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force

# Get DSG config
$config = Get-SreConfig($dsgId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

Write-Host "===Starting AD DC==="
Write-Host " - Waiting for AD to start before starting other VMs to ensure domain joining works."
Start-AzVM -ResourceGroupName $config.dsg.dc.rg -Name $config.dsg.dc.vmName
Write-Host "===Starting RDS gateway==="
Start-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.gateway.vmName -NoWait
Write-Host "===Starting RDS session hosts==="
Start-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.sessionHost1.vmName -NoWait
Start-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.sessionHost2.vmName -NoWait
Write-Host "===Starting dataserver==="
Start-AzVM -ResourceGroupName $config.dsg.dataserver.rg -Name $config.dsg.dataserver.vmName -NoWait
Write-Host "===Starting web app servers==="
Start-AzVM -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.gitlab.vmName -NoWait
Start-AzVM -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.hackmd.vmName -NoWait
Write-Host "===Starting all compute VMs==="
Get-AzVM -ResourceGroupName $config.dsg.dsvm.rg | Start-AzVM -NoWait

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
