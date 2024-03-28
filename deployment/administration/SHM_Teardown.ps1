param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. 'project')")]
    [string]$shmId,
    [Parameter(Mandatory = $false, HelpMessage = "No-op mode which will not remove anything")]
    [Switch]$dryRun
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureDns -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Cryptography -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Make user confirm before beginning deletion
# -------------------------------------------
$ResourceGroups = Get-ShmResourceGroups -shmConfig $config
if ($dryRun.IsPresent) {
    Add-LogMessage -Level Warning "This would remove $($ResourceGroups.Count) resource group(s) belonging to SHM '$($config.id)' from '$($config.subscriptionName)'!"
} else {
    Add-LogMessage -Level Warning "This will remove $($ResourceGroups.Count) resource group(s) belonging to SHM '$($config.id)' from '$($config.subscriptionName)'!"
    $ResourceGroups | ForEach-Object { Add-LogMessage -Level Warning "... $($_.ResourceGroupName)" }
    $confirmation = Read-Host "Are you sure you want to proceed? [y/n]"
    while ($confirmation -ne "y") {
        if ($confirmation -eq "n") { exit 0 }
        $confirmation = Read-Host "Are you sure you want to proceed? [y/n]"
    }
}


# Remove SHM resource groups and the resources they contain
# ---------------------------------------------------------
if ($ResourceGroups.Count) {
    $ResourceGroupNames = $ResourceGroups | ForEach-Object { $_.ResourceGroupName }
    if ($dryRun.IsPresent) {
        $ResourceGroupNames | ForEach-Object {
            Add-LogMessage -Level Info "Skipping removal of resource group '$_' with its contents."
        }
    } else {
        Remove-AllResourceGroups -ResourceGroupNames $ResourceGroupNames -MaxAttempts 60
    }
}


# Warn if any resources or groups remain
# --------------------------------------
$ResourceGroups = $dryRun.IsPresent ? $null : (Get-ShmResourceGroups -shmConfig $config)
if ($ResourceGroups) {
    Add-LogMessage -Level Error "There are still $($ResourceGroups.Length) undeleted resource group(s) remaining!"
    foreach ($ResourceGroup in $ResourceGroups) {
        Add-LogMessage -Level Error "$($ResourceGroup.ResourceGroupName)"
        Get-ResourcesInGroup -ResourceGroupName $ResourceGroup.ResourceGroupName | ForEach-Object {
            Add-LogMessage -Level Error "... $($_.Name) [$($_.ResourceType)]"
        }
    }
    Add-LogMessage -Level Fatal "Failed to teardown SHM '$($config.id)'!"
}


# Remove DNS data from the DNS subscription
# -----------------------------------------
if ($dryRun.IsPresent) {
    Add-LogMessage -Level Info "Would remove '@' TXT record from SHM '$($config.id)' DNS zone $($config.domain.fqdn)"
} else {
    Remove-DnsRecord -RecordName "@" `
                     -RecordType "TXT" `
                     -ResourceGroupName $config.dns.rg `
                     -SubscriptionName $config.dns.subscriptionName `
                     -ZoneName $config.domain.fqdn
}

# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
