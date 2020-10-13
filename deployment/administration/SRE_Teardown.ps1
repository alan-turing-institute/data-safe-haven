param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Make user confirm before beginning deletion
# -------------------------------------------
Add-LogMessage -Level Warning "This will remove all resources belonging to SRE '$($config.sre.id)' from '$($config.sre.subscriptionName)'!"
$confirmation = Read-Host "Are you sure you want to proceed? [y/n]"
while ($confirmation -ne "y") {
    if ($confirmation -eq "n") { exit 0 }
    $confirmation = Read-Host "Are you sure you want to proceed? [y/n]"
}


# Remove resource groups and the resources they contain
# If there are still resources remaining after 10 loops then throw an exception
# -----------------------------------------------------------------------------
$configResourceGroups = Find-AllMatchingKeys -Hashtable $config -Key "rg"
for ($i = 0; $i -lt 10; $i++) {
    $sreResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -in $configResourceGroups })
    if (-not $sreResourceGroups.Length) { break }
    Add-LogMessage -Level Info "Found $($sreResourceGroups.Length) resource group(s) to remove..."
    foreach ($resourceGroup in $sreResourceGroups) {
        Add-LogMessage -Level Info "Attempting to remove $($resourceGroup.ResourceGroupName)..."
        $null = Remove-AzResourceGroup -ResourceId $resourceGroup.ResourceId -Force -Confirm:$False -ErrorAction SilentlyContinue
        if ($?) {
            Add-LogMessage -Level Success "Resource group removal succeeded"
        } else {
            Add-LogMessage -Level Info "Resource group removal failed - rescheduling."
        }
    }
}
if ($sreResourceGroups) {
    Add-LogMessage -Level Fatal "There are still $($sreResourceGroups.Length) resource(s) remaining!`n$sreResourceGroups"
}


# Warn if any suspicious resource groups remain
# ---------------------------------------------
$suspiciousResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "RG_SRE_$($config.sre.id)*" }
if ($suspiciousResourceGroups) {
    Add-LogMessage -Level Warning "Found $($suspiciousResourceGroups.Length) undeleted resource group(s) which were possibly associated with this SRE`n$suspiciousResourceGroups"
}


# Remove residual SRE data from the SHM
# -------------------------------------
if (@(2, 3, 4).Contains([int]$config.sre.tier)) {
    $scriptPath = Join-Path $PSScriptRoot ".." "secure_research_environment" "setup" "Remove_SRE_Data_From_SHM.ps1"
    Invoke-Expression -Command "$scriptPath -configId $configId"
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
