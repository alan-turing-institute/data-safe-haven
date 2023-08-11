param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter action (EnsureStarted, EnsureStopped)")]
    [ValidateSet("EnsureStarted", "EnsureStopped")]
    [string]$Action,
    [Parameter(Mandatory = $false, HelpMessage = "Enter VM group (Identity, Mirrors or All)")]
    [ValidateSet("Identity", "Mirrors", "All")]
    [string]$Group = "All",
    [Parameter(Mandatory = $false, HelpMessage = "Exclude Firewall (only has an effect if Action is 'EnsureStopped'")]
    [switch]$ExcludeFirewall
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureNetwork -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop

# Get all VMs in matching resource groups
$vmsByRg = Get-VMsByResourceGroupPrefix -ResourceGroupPrefix $config.rgPrefix

# Remove some VMs from consideration
if ($Group -eq "Identity") {
    # Remove Mirror VMs from list
    $vmsByRg.Remove($config.mirrors.rg)
} elseif ($Group -eq "Mirrors") {
    # Remove Identity VMs from list
    $vmsByRg.Remove($config.dc.rg)
}

switch ($Action) {
    "EnsureStarted" {
        if (($Group -eq "Identity") -or ($Group -eq "All")) {
            # Ensure Firewall is started
            $null = Start-Firewall -Name $config.firewall.name -ResourceGroupName $config.network.vnet.rg -VirtualNetworkName $config.network.vnet.name
            # Ensure Identity VMs are started before any other VMs
            Add-LogMessage -Level Info "Ensuring VMs in resource group '$($config.dc.rg)' are started..."
            # Primary DC must be started before Secondary DC
            $primaryDCAlreadyRunning = Confirm-VmRunning -Name $config.dc.vmName -ResourceGroupName $config.dc.rg
            if ($primaryDCAlreadyRunning) {
                Add-LogMessage -Level InfoSuccess "VM '$($config.dc.vmName)' already running."
                # Start Secondary DC
                Start-VM -Name $config.dcb.vmName -ResourceGroupName $config.dc.rg
            } else {
                # Stop Secondary DC as it must start after Primary DC
                Add-LogMessage -Level Info "Stopping Secondary DC and NPS as Primary DC is not running."
                Stop-Vm -Name $config.dcb.vmName -ResourceGroupName $config.dc.rg
                # Start Primary DC
                Start-VM -Name $config.dc.vmName -ResourceGroupName $config.dc.rg
                # Start Secondary DC
                Start-VM -Name $config.dcb.vmName -ResourceGroupName $config.dc.rg
            }
            # Remove Identity VMs from general VM list so they are not processed twice
            $vmsByRg.Remove($config.dc.rg)
        }
        # Process remaining SHM VMs covered by the specified group
        foreach ($key in $vmsByRg.Keys) {
            $rgVms = $vmsByRg[$key]
            $rgName = $rgVms[0].ResourceGroupName
            Add-LogMessage -Level Info "Ensuring VMs in resource group '$rgName' are started..."
            foreach ($vm in $rgVms) {
                Start-VM -VM $vm
            }
        }
    }
    "EnsureStopped" {
        # Stop VMs
        foreach ($key in $vmsByRg.Keys) {
            $rgVms = $vmsByRg[$key]
            $rgName = $rgVms[0].ResourceGroupName
            Add-LogMessage -Level Info "Ensuring VMs in resource group '$rgName' are stopped..."
            foreach ($vm in $rgVms) {
                Stop-VM -VM $vm -NoWait
            }
        }
        if (-not $ExcludeFirewall) {
            $null = Stop-Firewall -Name $config.firewall.name -ResourceGroupName $config.network.vnet.rg -NoWait
        }
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
