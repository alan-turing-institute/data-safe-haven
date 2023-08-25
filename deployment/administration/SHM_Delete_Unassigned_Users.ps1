param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop

# Get config
# -------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext

# Delete users not currently in a security group
# ----------------------------------------------
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop
Add-LogMessage -Level Info "Deleting users not assigned to any security group: $($config.shm.id) from $($config.dc.vmName)..."

$script = "remote/Delete_Unassigned_Users.ps1"

$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $script -VMName $config.dc.vmName -ResourceGroupName $config.dc.rg

$null = Set-AzContext -Context $originalContext -ErrorAction Stop