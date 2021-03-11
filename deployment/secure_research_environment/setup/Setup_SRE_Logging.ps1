param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context
# -------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Get Log Analytics Workspace details
# -----------------------------------
Add-LogMessage -Level Info "[ ] Getting Log Analytics Workspace details..."
try {
    $null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
    $workspace = Get-AzOperationalInsightsWorkspace -Name $config.shm.logging.workspaceName -ResourceGroup $config.shm.logging.rg
    $key = Get-AzOperationalInsightsWorkspaceSharedKey -Name $config.shm.logging.workspaceName -ResourceGroup $config.shm.logging.rg
    $null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop
    Add-LogMessage -Level Success "Retrieved Log Analytics Workspace '$($workspace.Name)."
} catch {
    Add-LogMessage -Level Fatal "Failed to retrieve Log Analytics Workspace!" -Exception $_.Exception
}


# Ensure logging agent is installed on all SRE VMs
# ------------------------------------------------
Add-LogMessage -Level Info "[ ] Ensuring logging agent is installed on all SRE VMs..."
try {
    $sreResourceGroups = Get-SreResourceGroups -shmId $config.shm.id -sreId $config.sre.id
    foreach ($sreResourceGroup in $sreResourceGroups) {
        foreach ($vm in $(Get-AzVM -ResourceGroup $sreResourceGroup.ResourceGroupName)) {
            $null = Deploy-VirtualMachineMonitoringExtension -vm $vm -workspaceId $workspace.CustomerId -WorkspaceKey $key.PrimarySharedKey
        }
    }
    Add-LogMessage -Level Success "Ensured that logging agent is installed on all SRE VMs."
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that logging agent is installed on all SRE VMs!" -Exception $_.Exception
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
