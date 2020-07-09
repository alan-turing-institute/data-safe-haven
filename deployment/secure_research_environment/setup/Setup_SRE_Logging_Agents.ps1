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
$workspace = Get-AzOperationalInsightsWorkspace -Name $config.logging.workspaceName -ResourceGroup $config.logging.rg
$key = Get-AzOperationalInsightsWorkspaceSharedKey -Name $config.logging.workspaceName -ResourceGroup $config.logging.rg

# Ensure logging agent is installed on all SRE VMs
# ------------------------------------------------
if($skipAgentInstall) {
    Add-LogMessage -Level Warning "Skipping check and installation of Log Analytics agent on SRE VMs as '-skipAgentInstall' flag was passed."
} else {
    Add-LogMessage -Level Info "Ensuring Log Analytics agent is installed on all SRE VMs...'"
    $shmResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like $rgFilter } | Where-Object { $_.ResourceGroupName -notlike "*WEBAPP*" })
    foreach ($resourceGroup in $shmResourceGroups) {
        Add-LogMessage -Level Info "Ensuring Log Analytics agent is installed on all VMs in resource group '$($resourceGroup.ResourceGroupName)'...'"
        & "$PSScriptRoot/../../common/InstallVMInsights.ps1" -WorkspaceId $workspace.CustomerId -WorkspaceKey $key.PrimarySharedKey `
            -ResourceGroup $resourceGroup.ResourceGroupName -SubscriptionId $context.Subscription.Id -WorkspaceRegion $workspace.Location `
            -ReInstall -Approve
        Add-LogMessage -Level Info "Finished ensuring Log Analytics agent is installed on all VMs in resource group '$($resourceGroup.ResourceGroupName)'.'"
    }
    Add-LogMessage -Level Info "Finished ensuring Log Analytics agent is installed on all SRE VMs."
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
