param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter action (Start, Shutdown or Restart)")]
    [ValidateSet("EnsureStarted", "EnsureStopped")]
    [string]$Action
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureNetwork -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop

# Get all VMs in matching resource groups
$vmsByRg = Get-VMsByResourceGroupPrefix -ResourceGroupPrefix $config.sre.rgPrefix

switch ($Action) {
    "EnsureStarted" {
        # Remove remote desktop VMs to process last
        # May be able to simplify this further now that MSRDS is removed
        $remoteDesktopVms = $vmsByRg[$config.sre.remoteDesktop.rg]
        $vmsByRg.Remove($config.sre.remoteDesktop.rg)
        # Start all other VMs before RDS VMs so all services will be available when users can login via RDS
        foreach ($key in $vmsByRg.Keys) {
            $rgVms = $vmsByRg[$key]
            $rgName = $rgVms[0].ResourceGroupName
            Add-LogMessage -Level Info "Ensuring VMs in resource group '$rgName' are started..."
            foreach ($vm in $rgVms) {
                Start-VM -VM $vm
            }
        }
        # Ensure remote desktop VMs are started
        Add-LogMessage -Level Info "Ensuring VMs in resource group '$($config.sre.remoteDesktop.rg)' are started..."        
        # Start Guacamole VMs
        $remoteDesktopVms | ForEach-Object { Start-VM -VM $_ }
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
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
