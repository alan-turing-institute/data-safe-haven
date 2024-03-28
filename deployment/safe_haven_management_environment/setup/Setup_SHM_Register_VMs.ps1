param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. 'project')")]
    [string]$shmId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.OperationalInsights -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureOperationalInsights -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Create resource group if it does not exist
# ------------------------------------------
$null = Deploy-ResourceGroup -Name $config.monitoring.rg -Location $config.location


# Deploy log analytics workspace
# ------------------------------
$workspace = Deploy-LogAnalyticsWorkspace -Name $config.monitoring.loggingWorkspace.name -ResourceGroupName $config.monitoring.rg -Location $config.location
$workspaceKey = Get-AzOperationalInsightsWorkspaceSharedKey -Name $workspace.Name -ResourceGroup $workspace.ResourceGroupName


# Ensure all SHM VMs are registered with the logging workspace
# ---------------------------------------------------------------
Add-LogMessage -Level Info "[ ] Ensuring logging agent is installed on all SHM VMs..."
$shmResourceGroups = Get-ShmResourceGroups -shmConfig $config
try {
    $null = $shmResourceGroups | ForEach-Object { Get-AzVM -ResourceGroup $_.ResourceGroupName } | ForEach-Object {
        Deploy-VirtualMachineMonitoringExtension -VM $_ -WorkspaceId $workspace.CustomerId -WorkspaceKey $workspaceKey.PrimarySharedKey
    }
    Add-LogMessage -Level Success "Ensured that logging agent is installed on all SHM VMs."
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that logging agent is installed on all SHM VMs!" -Exception $_.Exception
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
