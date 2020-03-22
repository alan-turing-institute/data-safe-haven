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
$_ = Set-AzContext -SubscriptionId $config.subscriptionName


# Make user confirm before beginning deletion
# -------------------------------------------
Add-LogMessage -Level Warning "This will remove all resources (except the webapp) from '$($config.subscriptionName)'!"
$confirmation = Read-Host "Are you sure you want to proceed? [y/n]"
while ($confirmation -ne "y") {
    if ($confirmation -eq "n") { exit 0 }
    $confirmation = Read-Host "Are you sure you want to proceed? [y/n]"
}


# Remove resources
# ----------------
$sreResources = @(Get-AzResource) | Where-Object { $_.ResourceGroupName -NotLike "*WEBAPP*" }
while ($sreResources.Length) {
    Add-LogMessage -Level Info "Found $($sreResources.Length) resource(s) to remove..."
    foreach ($resource in $sreResources) {
        Add-LogMessage -Level Info "Attempting to remove $($resource.Name)..."
        $_ = Remove-AzResource -ResourceId $resource.ResourceId -Force -Confirm:$False -ErrorAction SilentlyContinue
        if ($?) {
            Add-LogMessage -Level Success "Resource removal succeeded"
        } else {
            Add-LogMessage -Level Info "Resource removal failed - rescheduling."
        }
    }
    $sreResources = @(Get-AzResource) | Where-Object { $_.ResourceGroupName -NotLike "*WEBAPP*" }
}


# Remove resource groups
# ----------------------
$sreResourceGroups = @(Get-AzResourceGroup) | Where-Object { $_.ResourceGroupName -NotLike "*WEBAPP*" }
while ($sreResourceGroups.Length) {
    Add-LogMessage -Level Info "Found $($sreResourceGroups.Length) resource group(s) to remove..."
    foreach ($resourceGroup in $sreResourceGroups) {
        Add-LogMessage -Level Info "Attempting to remove $($resourceGroup.ResourceGroupName)..."
        $_ = Remove-AzResourceGroup -ResourceId $resourceGroup.ResourceId -Force -Confirm:$False -ErrorAction SilentlyContinue
        if ($?) {
            Add-LogMessage -Level Success "Resource group removal succeeded"
        } else {
            Add-LogMessage -Level Info "Resource group removal failed - rescheduling."
        }
    }
    $sreResourceGroups = @(Get-AzResourceGroup) | Where-Object { $_.ResourceGroupName -NotLike "*WEBAPP*" }
}


# Remove DNS data from the DNS subscription
# -----------------------------------------
$_ = Set-AzContext -SubscriptionId $config.dns.subscriptionName
$dnsResourceGroup = $config.dns.rg
$shmDomain = $config.domain.fqdn
# AD DNS record
$adDnsRecordname = "@"
Add-LogMessage -Level Info "[ ] Removing '$adDnsRecordname' TXT record from SHM $shmId DNS zone ($shmDomain)"
Remove-AzDnsRecordSet -Name $adDnsRecordname -RecordType TXT -ZoneName $shmDomain -ResourceGroupName $dnsResourceGroup
$success = $?
# # RDS ACME record
# $rdsAcmeDnsRecordname = "_acme-challenge"
# Add-LogMessage -Level Info "[ ] Removing '$rdsAcmeDnsRecordname' TXT record from SRE $sreId DNS zone ($shmDomain)"
# Remove-AzDnsRecordSet -Name $rdsAcmeDnsRecordname -RecordType TXT -ZoneName $shmDomain -ResourceGroupName $dnsResourceGroup
# $success = $success -and $?
# Print success/failure message
if ($success) {
    Add-LogMessage -Level Success "Record removal succeeded"
} else {
    Add-LogMessage -Level Fatal "Record removal failed!"
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
