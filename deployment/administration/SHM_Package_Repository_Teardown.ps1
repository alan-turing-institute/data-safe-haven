param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. 'project')")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Which tier of mirrors should be torn down")]
    [ValidateSet("2", "3")]
    [string]$tier
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureNetwork -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop

# Check if Resource Group exists
$null = Get-AzResourceGroup -Name $config.repositories.rg -Location $config.location -ErrorVariable notExists -ErrorAction SilentlyContinue
if ($notExists) {
    Add-LogMessage -Level InfoSuccess "Resource group '$($config.repositories.rg)' does not exist"
} else {
    # Tear down repository VMs and associated disks/network cards
    Get-AzVM -ResourceGroupName $config.repositories.rg | Where-Object { $_.Name -like "*-TIER-${tier}" } | ForEach-Object {
        Remove-VirtualMachine -Name $_.Name -ResourceGroupName $_.ResourceGroupName -Force
        Remove-ManagedDisk -Name "$($_.Name)-OS-DISK" -ResourceGroupName $config.repositories.rg
        Remove-ManagedDisk -Name "$($_.Name)-DATA-DISK" -ResourceGroupName $config.repositories.rg
        Remove-NetworkInterface -Name "$($_.Name)-NIC" -ResourceGroupName $config.repositories.rg
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
