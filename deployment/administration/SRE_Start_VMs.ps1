param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Start all VMs
# -------------
Add-LogMessage -Level Info "Starting AD DC..."
Add-LogMessage -Level Info "Waiting for AD to start before starting other VMs to ensure domain joining works..."
Restart-AzVM -ResourceGroupName $config.sre.dc.rg -Name $config.sre.dc.vmName
Add-LogMessage -Level Info "Starting RDS gateway..."
Restart-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.gateway.vmName -NoWait
Add-LogMessage -Level Info "Starting RDS session hosts..."
Restart-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.sessionHost1.vmName -NoWait
Restart-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.sessionHost2.vmName -NoWait
Add-LogMessage -Level Info "Starting dataserver..."
Restart-AzVM -ResourceGroupName $config.sre.dataserver.rg -Name $config.sre.dataserver.vmName -NoWait
Add-LogMessage -Level Info "Starting web app servers..."
Restart-AzVM -ResourceGroupName $config.sre.webapps.rg -Name $config.sre.webapps.gitlab.vmName -NoWait
Restart-AzVM -ResourceGroupName $config.sre.webapps.rg -Name $config.sre.webapps.hackmd.vmName -NoWait
Add-LogMessage -Level Info "Starting all compute VMs..."
Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | Restart-AzVM -NoWait


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
