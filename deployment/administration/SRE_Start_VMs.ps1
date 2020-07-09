param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Start all VMs
# -------------
Add-LogMessage -Level Info "Starting RDS gateway..."
Enable-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.gateway.vmName
Add-LogMessage -Level Info "Starting RDS session hosts..."
Enable-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.appSessionHost.vmName
Enable-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.sessionHost2.vmName
Add-LogMessage -Level Info "Starting data server..."
Enable-AzVM -ResourceGroupName $config.sre.dataserver.rg -Name $config.sre.dataserver.vmName
Add-LogMessage -Level Info "Starting web app servers..."
Enable-AzVM -ResourceGroupName $config.sre.webapps.rg -Name $config.sre.webapps.gitlab.vmName
Enable-AzVM -ResourceGroupName $config.sre.webapps.rg -Name $config.sre.webapps.hackmd.vmName
Add-LogMessage -Level Info "Starting all compute VMs..."
Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | ForEach-Object { Enable-AzVM -Name $_.Name -ResourceGroupName $_.ResourceGroupName }


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
