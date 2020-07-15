param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter action (Start, Shutdown or Restart)")]
    [ValidateSet("EnsureStarted","EnsureStopped")]
    [string]$Action
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

$vmsByRg = Get-ShmOrSreVMsByResourceGroup -ResourceGroupPrefix $config.sre.rgPrefix

switch($Action) {
    "EnsureStarted" {
        # Take RDS VMs to process at the end
        $rdsVms = $vmsByRg[$config.sre.rds.rg]
        $vmsByRg.Remove($config.sre.rds.rg)
        foreach($key in $vmsByRg.Keys) {
            $rgVms = $vmsByRg[$key]
            $rgName = $rgVms[0].ResourceGroupName
            Add-LogMessage -Level Info "Ensuring VMs in resource group '$rgName' are started..."
            foreach ($vm in $rgVms) {
                Enable-AzVMWithoutRestart -VM $vm
            }
        }
        # Ensure RDS VMs are started
        Add-LogMessage -Level Info "Ensuring VMs in resource group '$($config.sre.rds.rg)' are started..."
        # RDS gateway must be started before RDS session hosts
        $gatewayAlreadyRunning = Confirm-AzVmRunning -Name $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg
        if($gatewayAlreadyRunning) {
            Add-LogMessage -Level InfoSuccess "VM '$($config.sre.rds.gateway.vmName)' already running."
            # Ensure session hosts started
            foreach ($vm in $rdsVms | Where-Object { $_.Name -ne $config.sre.rds.gateway.vmName }) {
                Enable-AzVMWithoutRestart -VM $vm
            }
        } else {
            # Stop session hosts as they must start after gateway
            Add-LogMessage -Level Info "Stopping RDS session hosts as gateway is not running."
            foreach ($vm in $rdsVms | Where-Object { $_.Name -ne $config.sre.rds.gateway.vmName }) {
                $result = Stop-AzVm -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Force
                if($result.status -eq "Succeeded") {
                    Add-LogMessage -Level InfoSuccess "Stopped VM '$($vm.Name)'.'"
                } else {
                    Add-LogMessage -Level Fatal "Unexpected status '$($result.status)' encountered when stopping VM '$($vm.Name)').'"
                }
            }
            # Start gateway
            Enable-AzVm -Name $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg
            # Start session hosts
            foreach ($vm in $rdsVms | Where-Object { $_.Name -ne $config.sre.rds.gateway.vmName }) {
                Enable-AzVm -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName
            }
        }
    }
    "EnsureStopped" {
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
