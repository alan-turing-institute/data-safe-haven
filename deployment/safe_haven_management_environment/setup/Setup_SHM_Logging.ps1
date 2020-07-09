param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$context = Set-AzContext -SubscriptionId $config.subscriptionName

$rgFilter = "RG_SHM_$($config.id)*"

# Get Log Analytics Workspace details
# -----------------------------------
$workspace = Get-AzOperationalInsightsWorkspace -Name $config.logging.workspaceName -ResourceGroup $config.logging.rg
$key = Get-AzOperationalInsightsWorkspaceSharedKey -Name $config.logging.workspaceName -ResourceGroup $config.logging.rg

# Ensure logging agent is installed on all SHM VMs
# ------------------------------------------------
Add-LogMessage -Level Info "Ensuring Log Analytics agent is installed on all SHM VMs...'"
$shmResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like $rgFilter } | Where-Object { $_.ResourceGroupName -notlike "*WEBAPP*" })
foreach ($resourceGroup in $shmResourceGroups) {
    Add-LogMessage -Level Info "Ensuring Log Analytics agent is installed on all VMs in resource group '$($resourceGroup.ResourceGroupName)'...'"
    & "$PSScriptRoot/../../common/InstallVMInsights.ps1" -WorkspaceId $workspace.CustomerId -WorkspaceKey $key.PrimarySharedKey `
        -ResourceGroup $resourceGroup.ResourceGroupName -SubscriptionId $context.Subscription.Id -WorkspaceRegion $workspace.Location `
        -ReInstall -Approve
    Add-LogMessage -Level Info "Finished ensuring Log Analytics agent is installed on all VMs in resource group '$($resourceGroup.ResourceGroupName)'.'"
}
Add-LogMessage -Level Info "Finished ensuring Log Analytics agent is installed on all SHM VMs."


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
