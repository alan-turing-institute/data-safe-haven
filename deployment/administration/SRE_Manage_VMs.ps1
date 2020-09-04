param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter action (Start, Shutdown or Restart)")]
    [ValidateSet("EnsureStarted", "EnsureStopped")]
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

# Get all VMs in matching resource groups
$vmsByRg = Get-VMsByResourceGroupPrefix -ResourceGroupPrefix $config.sre.rgPrefix

switch ($Action) {
    "EnsureStarted" {
        # Remove RDS VMs to process last
        $rdsVms = $vmsByRg[$config.sre.rds.rg]
        $vmsByRg.Remove($config.sre.rds.rg)
        # Start all other VMs before RDS VMs so all services will be available when users can login via RDS
        foreach ($key in $vmsByRg.Keys) {
            $rgVms = $vmsByRg[$key]
            $rgName = $rgVms[0].ResourceGroupName
            Add-LogMessage -Level Info "Ensuring VMs in resource group '$rgName' are started..."
            foreach ($vm in $rgVms) {
                Start-VM -VM $vm
            }
        }
        # Ensure RDS VMs are started
        Add-LogMessage -Level Info "Ensuring VMs in resource group '$($config.sre.rds.rg)' are started..."
        # RDS gateway must be started before RDS session hosts
        $gatewayAlreadyRunning = Confirm-AzVmRunning -Name $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg
        if ($gatewayAlreadyRunning) {
            Add-LogMessage -Level InfoSuccess "VM '$($config.sre.rds.gateway.vmName)' already running."
            # Ensure session hosts started
            foreach ($vm in $rdsVms | Where-Object { $_.Name -ne $config.sre.rds.gateway.vmName }) {
                Start-VM -VM $vm
            }
        } else {
            # Stop session hosts as they must start after gateway
            Add-LogMessage -Level Info "Stopping RDS session hosts as gateway is not running."
            foreach ($vm in $rdsVms | Where-Object { $_.Name -ne $config.sre.rds.gateway.vmName }) {
                Stop-VM -VM $vm
            }
            # Start gateway
            Start-VM -Name $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg
            # Start session hosts
            foreach ($vm in $rdsVms | Where-Object { $_.Name -ne $config.sre.rds.gateway.vmName }) {
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
