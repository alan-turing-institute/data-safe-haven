param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force

# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Start all VMs
# -------------
Write-Host "===Starting AD DC==="
Write-Host " - Waiting for AD to start before starting other VMs to ensure domain joining works."
Start-AzVM -ResourceGroupName $config.sre.dc.rg -Name $config.sre.dc.vmName
Write-Host "===Starting RDS gateway==="
Start-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.gateway.vmName -NoWait
Write-Host "===Starting RDS session hosts==="
Start-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.sessionHost1.vmName -NoWait
Start-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.sessionHost2.vmName -NoWait
Write-Host "===Starting dataserver==="
Start-AzVM -ResourceGroupName $config.sre.dataserver.rg -Name $config.sre.dataserver.vmName -NoWait
Write-Host "===Starting web app servers==="
Start-AzVM -ResourceGroupName $config.sre.webapps.rg -Name $config.sre.webapps.gitlab.vmName -NoWait
Start-AzVM -ResourceGroupName $config.sre.webapps.rg -Name $config.sre.webapps.hackmd.vmName -NoWait
Write-Host "===Starting all compute VMs==="
Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | Start-AzVM -NoWait


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
