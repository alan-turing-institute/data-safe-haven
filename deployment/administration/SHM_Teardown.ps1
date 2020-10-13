param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/DataStructures.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../common/Security.psm1 -Force

# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName


# Make user confirm before beginning deletion
# -------------------------------------------
Add-LogMessage -Level Warning "This will remove all resources (except the webapp) from '$($config.subscriptionName)'!"
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
    $shmResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -in $configResourceGroups })
    if (-not $shmResourceGroups.Length) { break }
    Add-LogMessage -Level Info "Found $($shmResourceGroups.Length) resource group(s) to remove..."
    foreach ($resourceGroup in $shmResourceGroups) {
        Add-LogMessage -Level Info "Attempting to remove $($resourceGroup.ResourceGroupName)..."
        $null = Remove-AzResourceGroup -ResourceId $resourceGroup.ResourceId -Force -Confirm:$False -ErrorAction SilentlyContinue
        if ($?) {
            Add-LogMessage -Level Success "Resource group removal succeeded"
        } else {
            Add-LogMessage -Level Info "Resource group removal failed - rescheduling."
        }
    }
}
if ($shmResourceGroups) {
    Add-LogMessage -Level Fatal "There are still $($shmResourceGroups.Length) resource(s) remaining!`n$shmResourceGroups"
}


# Warn if any suspicious resource groups remain
# ---------------------------------------------
$suspiciousResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "RG_SHM_$($config.shm.id)*" } | Where-Object { $_.ResourceGroupName -notlike "*WEBAPP*" })
if ($suspiciousResourceGroups) {
    Add-LogMessage -Level Warning "Found $($suspiciousResourceGroups.Length) undeleted resource group(s) which were possibly associated with this SHM`n$suspiciousResourceGroups"
}


# Remove DNS data from the DNS subscription
# -----------------------------------------
$null = Set-AzContext -SubscriptionId $config.dns.subscriptionName
$adDnsRecordname = "@"
$shmDomain = $config.domain.fqdn
Add-LogMessage -Level Info "[ ] Removing '$adDnsRecordname' TXT record from SHM $shmId DNS zone ($shmDomain)"
Remove-AzDnsRecordSet -Name $adDnsRecordname -RecordType TXT -ZoneName $shmDomain -ResourceGroupName $config.dns.rg
if ($?) {
    Add-LogMessage -Level Success "Record removal succeeded"
} else {
    Add-LogMessage -Level Fatal "Record removal failed!"
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
