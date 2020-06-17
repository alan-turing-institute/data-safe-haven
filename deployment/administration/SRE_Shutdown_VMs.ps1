param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Stop all VMs
# ------------
Add-LogMessage -Level Info "Stopping all compute VMs..."
Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | Stop-AzVM -Force -NoWait
Add-LogMessage -Level Info "Stopping web app servers..."
Stop-AzVM -ResourceGroupName $config.sre.webapps.rg -Name $config.sre.webapps.gitlab.vmName -Force -NoWait
Stop-AzVM -ResourceGroupName $config.sre.webapps.rg -Name $config.sre.webapps.hackmd.vmName -Force -NoWait
Add-LogMessage -Level Info "Stopping dataserver..."
Stop-AzVM -ResourceGroupName $config.sre.dataserver.rg -Name $config.sre.dataserver.vmName -Force -NoWait
Add-LogMessage -Level Info "Stopping RDS session hosts..."
Stop-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.sessionHost1.vmName -Force -NoWait
Stop-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.sessionHost2.vmName -Force -NoWait
Add-LogMessage -Level Info "Stopping RDS gateway..."
Stop-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.gateway.vmName -Force -NoWait
Add-LogMessage -Level Info "Stopping AD DC..."
Stop-AzVM -ResourceGroupName $config.sre.dc.rg -Name $config.sre.dc.vmName -Force -NoWait


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
