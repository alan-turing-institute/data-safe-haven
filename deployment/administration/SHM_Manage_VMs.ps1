param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID.")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter action (EnsureStarted, EnsureStopped)")]
    [ValidateSet("EnsureStarted","EnsureStopped")]
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

function Enable-AzVMWithoutRestart {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM object")]
        $VM
    )    
    if(Confirm-AzVmRunning -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName) {
        Add-LogMessage -Level InfoSuccess "VM '$($VM.Name)' already running."
    } elseif(Confirm-AzVmDeallocated -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName) {
        Enable-AzVm -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName
    } elseif(Confirm-AzVmStopped -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName) {
        Enable-AzVm -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName
    } else {
        $vmStatus = (Get-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Status).Statuses.Code
        Add-LogMessage -Level Warning "VM '$($VM.Name)' not in supported status: $vmStatus. No action taken."
    }
}


$vmsByRg = Get-ShmOrSreVMsByResourceGroup -ResourceGroupPrefix $config.rgPrefix
if($Group -eq "Identity") {
    # Remove Mirror VMs from list   
    $vmsByRg.Remove($config.mirrors.rg)
} elseif($Group -eq "Mirrors") {
    # Remove Identity VMs from list   
    $vmsByRg.Remove($config.dc.rg)
    $vmsByRg.Remove($config.nps.rg)
}

switch($Action) {
    "EnsureStarted" {
        if(($Group -eq "Identity") -or ($Group -eq "All")) {
            # Ensure DC VMs are started
            Add-LogMessage -Level Info "Ensuring VMs in resource group '$($config.dc.rg)' are started..."
            # Primary DC must be started before DCB
            $primaryDCAlreadyRunning = Confirm-AzVmRunning -Name $config.dc.vmName -ResourceGroupName $config.dc.rg
            if($primaryDCAlreadyRunning) {
                Add-LogMessage -Level InfoSuccess "VM '$($config.dc.vmName)' already running."
                # Ensure Secondary DC started
                foreach ($vm in $rdsVms | Where-Object { $_.Name -ne $config.sre.rds.gateway.vmName }) {
                    Enable-AzVMWithoutRestart -VM $vm
                }
            } else {
                # Stop Secondary DC as it must start after Primary DC
                Add-LogMessage -Level Info "Stopping Secondary DC as Primary DC is not running."
                $result = Stop-AzVm -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Force
                if($result.status -eq "Succeeded") {
                    Add-LogMessage -Level InfoSuccess "Stopped VM '$($vm.Name)'.'"
                } else {
                    Add-LogMessage -Level Fatal "Unexpected status '$($result.status)' encountered when stopping VM '$($vm.Name)').'"
                }
                # Start Primary DC
                Enable-AzVm -Name $config.dc.vmName -ResourceGroupName $config.dc.rg
                # Start Secondary DC
                Enable-AzVm -Name $config.dcb.vmName -ResourceGroupName $config.dc.rg
            }
            # Remove DC VMs from general VM list so they are not processed twice   
            $vmsByRg.Remove($config.dc.rg)
        }
        # Process remaining SHM VMs covered by the specified group
        foreach($key in $vmsByRg.Keys) {
            $rgVms = $vmsByRg[$key]
            $rgName = $rgVms[0].ResourceGroupName
            Add-LogMessage -Level Info "Ensuring VMs in resource group '$rgName' are started..."
            foreach ($vm in $rgVms) {
                Enable-AzVMWithoutRestart -VM $vm
            }
        }
    }
    "EnsureStopped" {
        # Process SHM VMs covered by the specified group
        foreach($key in $vmsByRg.Keys) {
            $rgVms = $vmsByRg[$key]
            $rgName = $rgVms[0].ResourceGroupName
            Add-LogMessage -Level Info "Ensuring VMs in resource group '$rgName' are stopped..."
            foreach($vm in $rgVms) {
                if(Confirm-AzVmDeallocated -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName) {
                    Add-LogMessage -Level InfoSuccess "VM '$($VM.Name)' already stopped."
                } else {
                    $result = Stop-AzVM -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Force -NoWait
                    if($result.IsSuccessStatusCode) {
                        Add-LogMessage -Level Success "Shutdown request accepted for VM '$($vm.Name)'.'"
                    } else {
                        Add-LogMessage -Level Fatal "Unexpected status '$($result.StatusCode) ($($result.ReasonPhrase))' encountered when requesting shutdown of VM '$($vm.Name)').'"
                    }
                }
            }
        }
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
