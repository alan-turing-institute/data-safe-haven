param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
    [Parameter(Mandatory=$false, HelpMessage="No-op mode which will not remove anything")]
    [Switch]$dryRun
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop

if ($dryRun.IsPresent) {
    Add-LogMessage -Level Warning "THIS IS A DRY RUN - NO SERVICES WILL BE REMOVED"
}

# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Make user confirm before beginning deletion
# -------------------------------------------
if (-Not $dryRun.IsPresent) {
    Add-LogMessage -Level Warning "This will remove all resources belonging to SRE '$($config.sre.id)' from '$($config.sre.subscriptionName)'!"
    $confirmation = Read-Host "Are you sure you want to proceed? [y/n]"
    while ($confirmation -ne "y") {
        if ($confirmation -eq "n") { exit 0 }
        $confirmation = Read-Host "Are you sure you want to proceed? [y/n]"
    }
    $noAttemps = 10
} else {
    $noAttemps = 1
}


# Remove resource groups and the resources they contain
# If there are still resources remaining after 10 loops then throw an exception
# -----------------------------------------------------------------------------
$configResourceGroups = Find-AllMatchingKeys -Hashtable $config["sre"] -Key "rg"
for ($i = 0; $i -lt $noAttemps; $i++) {
    $sreResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -in $configResourceGroups })
    if (-not $sreResourceGroups.Length) { break }
    Add-LogMessage -Level Info "Found $($sreResourceGroups.Length) resource group(s) to remove..."
    foreach ($resourceGroup in $sreResourceGroups) {
        if (-Not $dryRun.IsPresent) {
            Add-LogMessage -Level Info "Attempting to remove $($resourceGroup.ResourceGroupName)..."
            $null = Remove-AzResourceGroup -ResourceId $resourceGroup.ResourceId -Force -Confirm:$False -ErrorAction SilentlyContinue
            if ($?) {
                Add-LogMessage -Level Success "Resource group removal succeeded"
            } else {
                Add-LogMessage -Level Info "Resource group removal failed - rescheduling."
            }
        } else {
            Add-LogMessage -Level Info "$($resourceGroup.ResourceGroupName)"
        }

    }
}


if (-Not $dryRun.IsPresent) {
    if ($sreResourceGroups) {
        Add-LogMessage -Level Fatal "There are still $($sreResourceGroups.Length) resource(s) remaining!`n$sreResourceGroups"
    }

    # Warn if any suspicious resource groups remain
    # ---------------------------------------------
    $suspiciousResourceGroups = Get-SreResourceGroups -shmId $config.shm.id -sreId $config.sre.id
    if ($suspiciousResourceGroups) {
        Add-LogMessage -Level Warning "Found $($suspiciousResourceGroups.Length) undeleted resource group(s) which were possibly associated with this SRE`n$suspiciousResourceGroups"
    }
}


# Remove residual SRE data from the SHM
# -------------------------------------
if ($config.sre.remoteDesktop.provider -ne "CoCalc") {
    $scriptPath = Join-Path $PSScriptRoot ".." "secure_research_environment" "setup" "Remove_SRE_Data_From_SHM.ps1"
    if (-Not $dryRun.IsPresent) {
        Invoke-Expression -Command "$scriptPath -shmId $shmId -sreId $sreId"
    } else {
        Add-LogMessage -Level Info "A script will be executed to remove SRE data from SHM: $($scriptPath)"
    }
}


# Tear down the AzureAD application
# ---------------------------------
if ($config.sre.remoteDesktop.provider -eq "ApacheGuacamole") {
    $azureAdApplicationName = "Guacamole SRE $($config.sre.id)"
    Add-LogMessage -Level Info "Ensuring that '$azureAdApplicationName' is removed from Azure Active Directory..."
    if (Get-MgContext) {
        Add-LogMessage -Level Info "Already authenticated against Microsoft Graph"
    } else {
        Connect-MgGraph -TenantId $tenantId -Scopes "Application.ReadWrite.All", "Policy.ReadWrite.ApplicationConfiguration" -ErrorAction Stop
    }
    try {
        Get-MgApplication -Filter "DisplayName eq '$azureAdApplicationName'" | ForEach-Object { Remove-MgApplication -ApplicationId $_.Id }
        Add-LogMessage -Level Success "'$azureAdApplicationName' has been removed from Azure Active Directory"
    } catch {
        Add-LogMessage -Level Fatal "Could not remove '$azureAdApplicationName' from Azure Active Directory!" -Exception $_.Exception
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
