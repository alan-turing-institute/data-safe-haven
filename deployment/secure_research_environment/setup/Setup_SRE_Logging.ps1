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


# Get Log Analytics Workspace details
# -----------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$workspace = Get-AzOperationalInsightsWorkspace -Name $config.shm.logging.workspaceName -ResourceGroup $config.shm.logging.rg
$key = Get-AzOperationalInsightsWorkspaceSharedKey -Name $config.shm.logging.workspaceName -ResourceGroup $config.shm.logging.rg


# Ensure logging agent is installed on all SRE VMs
# ------------------------------------------------
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$rgFilter = "RG_SRE_$($config.sre.id)*"
$sreResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like $rgFilter })
foreach ($sreResourceGroup in $sreResourceGroups) {
    foreach ($vm in $(Get-AzVM -ResourceGroup $sreResourceGroup.ResourceGroupName)) {
        $null = Deploy-VirtualMachineMonitoringExtension -vm $vm -workspaceId $workspace.CustomerId -WorkspaceKey $key.PrimarySharedKey
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
