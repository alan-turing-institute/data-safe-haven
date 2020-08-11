param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID.")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter action (EnsureStarted, EnsureStopped)")]
    [ValidateSet("EnsureStarted", "EnsureStopped")]
    [string]$Action,
    [Parameter(Mandatory = $true, HelpMessage = "Enter VM group (Identity, Mirrors or All)")]
    [ValidateSet("Identity", "Mirrors", "All")]
    [string]$Group
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

# Get all VMs in matching resource groups
$vmsByRg = Get-VMsByResourceGroupPrefix -ResourceGroupPrefix $config.rgPrefix

# Remove some VMs from consideration
if ($Group -eq "Identity") {
    # Remove Mirror VMs from list
    $vmsByRg.Remove($config.mirrors.rg)
} elseif ($Group -eq "Mirrors") {
    # Remove Identity VMs from list
    $vmsByRg.Remove($config.dc.rg)
    $vmsByRg.Remove($config.nps.rg)
}

switch ($Action) {
    "EnsureStarted" {
        if (($Group -eq "Identity") -or ($Group -eq "All")) {
            # Ensure Identity VMs are started before anything else
            Add-LogMessage -Level Info "Ensuring VMs in resource group '$($config.dc.rg)' are started..."
            # Primary DC must be started before Secondary DC
            $primaryDCAlreadyRunning = Confirm-AzVmRunning -Name $config.dc.vmName -ResourceGroupName $config.dc.rg
            if ($primaryDCAlreadyRunning) {
                Add-LogMessage -Level InfoSuccess "VM '$($config.dc.vmName)' already running."
                # Start Secondary DC and NPS
                Start-VM -Name $config.dcb.vmName -ResourceGroupName $config.dc.rg
                Start-VM -Name $config.nps.vmName -ResourceGroupName $config.nps.rg
            } else {
                # Stop Secondary DC and NPS as these must start after Primary DC
                Add-LogMessage -Level Info "Stopping Secondary DC and NPS as Primary DC is not running."
                Stop-Vm -Name $config.dcb.vmName -ResourceGroupName $config.dc.rg
                Stop-Vm -Name $config.nps.vmName -ResourceGroupName $config.nps.rg
                # Start Primary DC
                Start-VM -Name $config.dc.vmName -ResourceGroupName $config.dc.rg
                # Start Secondary DC and NPS
                Start-VM -Name $config.dcb.vmName -ResourceGroupName $config.dc.rg
                Start-VM -Name $config.nps.vmName -ResourceGroupName $config.nps.rg
            }
            # Remove Identity VMs from general VM list so they are not processed twice
            $vmsByRg.Remove($config.dc.rg)
            $vmsByRg.Remove($config.nps.rg)
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
        foreach ($key in $vmsByRg.Keys) {
            $rgVms = $vmsByRg[$key]
            $rgName = $rgVms[0].ResourceGroupName
            Add-LogMessage -Level Info "Ensuring VMs in resource group '$rgName' are stopped..."
            foreach ($vm in $rgVms) {
                Stop-VM -VM $vm -NoWait
            }
        }
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
