param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId,
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force

# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Stop all VMs
# ------------
Write-Host "===Stopping all compute VMs==="
Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | Stop-AzVM -Force -NoWait
Write-Host "===Stopping web app servers==="
Stop-AzVM -ResourceGroupName $config.sre.webapps.rg -Name $config.sre.webapps.gitlab.vmName -Force -NoWait
Stop-AzVM -ResourceGroupName $config.sre.webapps.rg -Name $config.sre.webapps.hackmd.vmName -Force -NoWait
Write-Host "===Stopping dataserver==="
Stop-AzVM -ResourceGroupName $config.sre.dataserver.rg -Name $config.sre.dataserver.vmName -Force -NoWait
Write-Host "===Stopping RDS session hosts==="
Stop-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.sessionHost1.vmName -Force -NoWait
Stop-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.sessionHost2.vmName -Force -NoWait
Write-Host "===Stopping RDS gateway==="
Stop-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.gateway.vmName -Force -NoWait
Write-Host "===Stopping AD DC==="
Stop-AzVM -ResourceGroupName $config.sre.dc.rg -Name $config.sre.dc.vmName -Force -NoWait


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext