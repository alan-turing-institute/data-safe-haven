param(
  [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName


# Start/restart all IAAM VMs
# --------------------------
Add-LogMessage -Level Info "Starting AD DCs..."
Add-LogMessage -Level Info "Starting Primary AD before other VMs..."
Enable-AzVM -Name $config.dc.vmName -ResourceGroupName $config.dc.rg
Add-LogMessage -Level Info "Starting Backup AD before other VMs..."
Enable-AzVM -Name $config.dcb.vmName -ResourceGroupName $config.dc.rg
Add-LogMessage -Level Info "Starting NPS Server..."
Enable-AzVM -Name $config.nps.vmName -ResourceGroupName $config.nps.rg


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
