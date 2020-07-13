param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$context = Set-AzContext -SubscriptionId $config.sre.subscriptionName

$rgFilter = "RG_SRE_$($config.sre.id)*"

# Get Log Analytics Workspace details
# -----------------------------------
$workspace = Get-AzOperationalInsightsWorkspace -Name $config.shm.logging.workspaceName -ResourceGroup $config.shm.logging.rg
$key = Get-AzOperationalInsightsWorkspaceSharedKey -Name $config.shm.logging.workspaceName -ResourceGroup $config.shm.logging.rg

# Ensure logging agent is installed on all SRE VMs
# ------------------------------------------------
$shmResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like $rgFilter })
foreach($rg in $shmResourceGroups) {
$rgVms = Get-AzVM -ResourceGroup $rg.ResourceGroupName
    foreach($vm in $rgVms) {
        $null = Deploy-VirtualMachineMonitoringExtension -vm $vm -workspaceId $workspace.CustomerId -WorkspaceKey $key.PrimarySharedKey
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
