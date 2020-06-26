param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../common/Security.psm1 -Force

# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig($shmId)
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


# Remove resources - if there are still resources remaining after 10 loops then throw an exception
# ------------------------------------------------------------------------------------------------
for ($i = 0; $i -le 10; $i++) {
    $shmResources = @(Get-AzResource | Where-Object { $_.ResourceGroupName -like "RG_SHM_$($config.sre.id)*" }) | Where-Object { $_.ResourceGroupName -notlike "*WEBAPP*" }
    if (-not $shmResources.Length) { break }
    Add-LogMessage -Level Info "Found $($shmResources.Length) resource(s) to remove..."
    foreach ($resource in $shmResources) {
        Add-LogMessage -Level Info "Attempting to remove $($resource.Name)..."
        $null = Remove-AzResource -ResourceId $resource.ResourceId -Force -Confirm:$False -ErrorAction SilentlyContinue
        if ($?) {
            Add-LogMessage -Level Success "Resource removal succeeded"
        } else {
            Add-LogMessage -Level Info "Resource removal failed - rescheduling."
        }
    }
}
if ($shmResources) {
    Add-LogMessage -Level Fatal "There are still $($shmResources.Length) resource(s) remaining!`n$shmResources"
}


# Remove resource groups
# ----------------------
for ($i = 0; $i -le 10; $i++) {
    $shmResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "RG_SHM_$($config.sre.id)*" }) | Where-Object { $_.ResourceGroupName -notlike "*WEBAPP*" }
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
