param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $false, HelpMessage = "No-op mode which will not remove anything")]
    [Switch]$dryRun
)

Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Cryptography -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/DataStructures.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Dns -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Make user confirm before beginning deletion
# -------------------------------------------
$shmResourceGroups = Get-ShmResourceGroups -shmConfig $config
if ($dryRun.IsPresent) {
    Add-LogMessage -Level Warning "This would remove $($shmResourceGroups.Length) resource group(s) belonging to SHM '$($config.id)' from '$($config.subscriptionName)'!"
    $nIterations = 1
} else {
    Add-LogMessage -Level Warning "This will remove $($shmResourceGroups.Length) resource group(s) belonging to SHM '$($config.id)' from '$($config.subscriptionName)'!"
    $shmResourceGroups | ForEach-Object { Add-LogMessage -Level Warning "... $($_.ResourceGroupName)" }
    $confirmation = Read-Host "Are you sure you want to proceed? [y/n]"
    while ($confirmation -ne "y") {
        if ($confirmation -eq "n") { exit 0 }
        $confirmation = Read-Host "Are you sure you want to proceed? [y/n]"
    }
    $nIterations = 10
}


# Remove resource groups and the resources they contain
# If there are still resources remaining after 10 loops then throw an exception
# -----------------------------------------------------------------------------
for ($i = 0; $i -lt $nIterations; $i++) {
    $shmResourceGroups = Get-ShmResourceGroups -shmConfig $config
    if (-not $shmResourceGroups.Length) { break }
    Add-LogMessage -Level Info "Found $($shmResourceGroups.Length) resource group(s) to remove..."
    foreach ($resourceGroup in $shmResourceGroups) {
        if ($dryRun.IsPresent) {
            Add-LogMessage -Level Info "Would attempt to remove $($resourceGroup.ResourceGroupName)..."
        } else {
            Add-LogMessage -Level Info "Attempting to remove $($resourceGroup.ResourceGroupName)..."
            $null = Remove-AzResourceGroup -ResourceId $resourceGroup.ResourceId -Force -Confirm:$False -ErrorAction SilentlyContinue
            if ($?) {
                Add-LogMessage -Level Success "Resource group removal succeeded"
            } else {
                Add-LogMessage -Level Info "Resource group removal failed - rescheduling."
            }
        }
    }
}


# Warn if any resources or groups remain
# --------------------------------------
if (-not $dryRun.IsPresent) {
    $shmResourceGroups = Get-ShmResourceGroups -shmConfig $config
    if ($shmResourceGroups) {
        Add-LogMessage -Level Error "There are still $($shmResourceGroups.Length) undeleted resource group(s) remaining!"
        foreach ($resourceGroup in $shmResourceGroups) {
            Add-LogMessage -Level Error "$($resourceGroup.ResourceGroupName)"
            Get-AzResource | `
                Where-Object { $_.ResourceGroupName -eq $resourceGroup.ResourceGroupName } | `
                ForEach-Object { Add-LogMessage -Level Error "... $($_.Name) [$($_.ResourceType)]" }
        }
        Add-LogMessage -Level Fatal "Failed to teardown SHM '$($config.id)'!"
    }
}


# Remove DNS data from the DNS subscription
# -----------------------------------------
if ($dryRun.IsPresent) {
    Add-LogMessage -Level Info "Would remove '@' TXT record from SHM '$($config.id)' DNS zone $($config.domain.fqdn)"
} else {
    $null = Set-AzContext -SubscriptionId $config.dns.subscriptionName -ErrorAction Stop
    Add-LogMessage -Level Info "[ ] Removing '@' TXT record from SHM '$($config.id)' DNS zone $($config.domain.fqdn)"
    Remove-AzDnsRecordSet -Name "@" -RecordType TXT -ZoneName $config.domain.fqdn -ResourceGroupName $config.dns.rg
    if ($?) {
        Add-LogMessage -Level Success "Record removal succeeded"
    } else {
        Add-LogMessage -Level Fatal "Record removal failed!"
    }
    $null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop
}

# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
