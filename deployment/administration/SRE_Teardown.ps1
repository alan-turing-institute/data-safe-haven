param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Make user confirm before beginning deletion
# -------------------------------------------
Add-LogMessage -Level Warning "This will remove all resources from '$($config.sre.subscriptionName)'!"
$confirmation = Read-Host "Are you sure you want to proceed? [y/n]"
while ($confirmation -ne "y") {
    if ($confirmation -eq "n") { exit 0 }
    $confirmation = Read-Host "Are you sure you want to proceed? [y/n]"
}


# Remove resources
# ----------------
$sreResources = @(Get-AzResource)
while ($sreResources.Length) {
    Add-LogMessage -Level Info "Found $($sreResources.Length) resource to remove..."
    foreach ($resource in $sreResources) {
        Add-LogMessage -Level Info "Attempting to remove $($resource.Name)..."
        $_ = Remove-AzResource -ResourceId $resource.ResourceId -Force -Confirm:$False -ErrorAction SilentlyContinue
        if ($?) {
            Add-LogMessage -Level Success "Resource removal succeeded"
        } else {
            Add-LogMessage -Level Info "Resource removal failed - rescheduling."
        }
    }
    $sreResources = @(Get-AzResource)
}


# Remove resource groups
# ----------------------
$sreResourceGroups = @(Get-AzResourceGroup)
while ($sreResourceGroups.Length) {
    Add-LogMessage -Level Info "Found $($sreResourceGroups.Length) resource groups to remove..."
    foreach ($resourceGroup in $sreResourceGroups) {
        Add-LogMessage -Level Info "Attempting to remove $($resourceGroup.ResourceGroupName)..."
        $_ = Remove-AzResourceGroup -ResourceId $resourceGroup.ResourceId -Force -Confirm:$False -ErrorAction SilentlyContinue
        if ($?) {
            Add-LogMessage -Level Success "Resource group removal succeeded"
        } else {
            Add-LogMessage -Level Info "Resource group removal failed - rescheduling."
        }
    }
    $sreResourceGroups = @(Get-AzResourceGroup)
}


# Remove residual SRE data from the SHM
# -------------------------------------
$scriptPath = Join-Path $PSScriptRoot ".." "secure_research_environment" "setup" "Remove_SRE_Data_From_SHM.ps1"
Invoke-Expression -Command "$scriptPath -sreId $sreId"


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
