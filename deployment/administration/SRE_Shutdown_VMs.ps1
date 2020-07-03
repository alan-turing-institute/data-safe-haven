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
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Stop all VMs
# ------------
Add-LogMessage -Level Info "Stopping all compute VMs..."

Add-LogMessage -Level Info "Resizing compute VMs..."
Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | ForEach-Object {
    Stop-AzVM -ResourceGroupName $config.sre.dsvm.rg -Name $_.Name -Force -NoWait
}

Add-LogMessage -Level Info "Resizing web app servers..."
Get-AzVM -ResourceGroupName $config.sre.webapps.rg | ForEach-Object {
    Stop-AzVM -ResourceGroupName $config.sre.webapps.rg -Name $_.Name -Force -NoWait
}

Add-LogMessage -Level Info "Resizing dataserver..."
Get-AzVM -ResourceGroupName $config.sre.dataserver.rg | ForEach-Object {
    Stop-AzVM -ResourceGroupName $config.sre.dataserver.rg -Name $_.Name -Force -NoWait
}

Add-LogMessage -Level Info "Resizing RDS gateway and session hosts..."
Get-AzVM -ResourceGroupName $config.sre.rds.rg | ForEach-Object {
    Stop-AzVM -ResourceGroupName $config.sre.rds.rg -Name $_.Name -Force -NoWait
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
