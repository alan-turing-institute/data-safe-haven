param(
  [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName


# Stop all IAAM VMs
# -----------------
Add-LogMessage -Level Info "Stopping NPS Server"
Stop-AzVM -ResourceGroupName $config.nps.rg -Name $config.nps.vmName -Force -NoWait
Add-LogMessage -Level Info "Stopping AD DCs"
Stop-AzVM -ResourceGroupName $config.dc.rg -Name $config.dc.vmName -Force -NoWait
Stop-AzVM -ResourceGroupName $config.dc.rg -Name $config.dcb.vmName -Force -NoWait


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
