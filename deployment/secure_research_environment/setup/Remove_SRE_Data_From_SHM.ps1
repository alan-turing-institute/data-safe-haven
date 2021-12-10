param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Look for resources in this subscription
# ---------------------------------------
$sreResourceGroups = Get-SreResourceGroups -sreConfig $config
$sreResourceGroupNames = $sreResourceGroups | ForEach-Object { $_.ResourceGroupName }
$sreResources = $sreResourceGroupNames ? (Get-AzResource | Where-Object { $sreResourceGroupNames.Contains($_.ResourceGroupName) }) : @()

# If resources are found then print a warning message
if ($sreResources -or $sreResourceGroups) {
    Add-LogMessage -Level Warning "SRE data should not be deleted from the SHM unless all SRE resources have been deleted from the subscription!"
    Add-LogMessage -Level Warning "There are still $($sreResourceGroups.Length) undeleted resource group(s) remaining!"
    $sreResourceGroups | ForEach-Object { Add-LogMessage -Level Warning "$($_.ResourceGroupName)" }
    Add-LogMessage -Level Warning "There are still $($sreResources.Length) undeleted resource(s) remaining!"
    $sreResources | ForEach-Object { Add-LogMessage -Level Warning "... $($_.Name) [$($_.ResourceType)]" }
    $confirmation = Read-Host "Do you want to proceed with unregistering SRE $($config.sre.id) from SHM $($config.shm.id) (unsafe)? [y/n]"
    while ($confirmation -ne "y") {
        if ($confirmation -eq "n") { exit 0 }
        $confirmation = Read-Host "Do you want to proceed with unregistering SRE $($config.sre.id) from SHM $($config.shm.id) (unsafe)? [y/n]"
    }

# ... otherwise continuing removing artifacts in the SHM subscription
} else {
    $null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop

    # Remove SHM side of peerings involving this SRE
    # ----------------------------------------------
    Add-LogMessage -Level Info "Removing peerings between SRE and SHM virtual networks..."
    $peeringName = "PEER_$($config.sre.network.vnet.name)"
    foreach ($shmVnet in $(Get-AzVirtualNetwork -Name * -ResourceGroupName $config.shm.network.vnet.rg)) {
        foreach ($peering in $(Get-AzVirtualNetworkPeering -VirtualNetworkName $shmVnet.Name -ResourceGroupName $config.shm.network.vnet.rg | Where-Object { $_.Name -eq $peeringName })) {
            $null = Remove-AzVirtualNetworkPeering -Name $peering.Name -VirtualNetworkName $shmVnet.Name -ResourceGroupName $config.shm.network.vnet.rg -Force
            if ($?) {
                Add-LogMessage -Level Success "Removal of peering '$($peering.Name)' succeeded"
            } else {
                Add-LogMessage -Level Fatal "Removal of peering '$($peering.Name)' failed!"
            }
        }
    }


    # Remove SRE users and groups from SHM DC
    # ---------------------------------------
    Add-LogMessage -Level Info "Removing SRE users and groups from SHM DC..."
    # Load data to remove
    $groupNames = $config.sre.domain.securityGroups.Values | ForEach-Object { $_.name }
    $userNames = $config.sre.users.computerManagers.Values | ForEach-Object { $_.samAccountName }
    $userNames += $config.sre.users.serviceAccounts.Values | ForEach-Object { $_.samAccountName }
    $computerNamePatterns = @("*-$($config.sre.id)".ToUpper(), "*-$($config.sre.id)-*".ToUpper())
    # Remove SRE users and groups from SHM DC
    $params = @{
        groupNamesB64           = $groupNames | ConvertTo-Json | ConvertTo-Base64
        userNamesB64            = $userNames | ConvertTo-Json | ConvertTo-Base64
        computerNamePatternsB64 = $computerNamePatterns | ConvertTo-Json | ConvertTo-Base64
    }
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_shm_dc" "scripts" "Remove_Users_And_Groups_Remote.ps1" -Resolve
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params


    # Remove SRE DNS records and private endpoint DNS Zones from SHM DC
    # ----------------------------------------------------------------
    Add-LogMessage -Level Info "Removing SRE private DNS records from SHM DC..."
    $privateEndpointNames = @($config.sre.storage.persistentdata.account.name, $config.sre.storage.userdata.account.name) |
        ForEach-Object { Get-AzStorageAccount -ResourceGroupName $config.shm.storage.persistentdata.rg -Name $_ -ErrorAction SilentlyContinue } |
        Where-Object { $_ } |
        ForEach-Object { $_.Context.Name }
    $params = @{
        ShmFqdn                     = $config.shm.domain.fqdn
        SreFqdn                     = $config.sre.domain.fqdn
        SreId                       = $config.sre.id
        PrivateEndpointFragmentsB64 = $privateEndpointNames | ConvertTo-Json | ConvertTo-Base64
    }
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_shm_dc" "scripts" "Remove_DNS_Entries_Remote.ps1" -Resolve
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params


    # Remove RDS Gateway RADIUS Client from SHM NPS
    # ---------------------------------------------
    if ($config.sre.remoteDesktop.provider -eq "MicrosoftRDS") {
        Add-LogMessage -Level Info "Removing RDS Gateway RADIUS Client from SHM NPS..."
        $scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_shm_dc" "scripts" "Remove_RDS_Gateway_RADIUS_Client_Remote.ps1" -Resolve
        $params = @{
            rdsGatewayFqdn = $config.sre.remoteDesktop.gateway.fqdn
        }
        $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.nps.vmName -ResourceGroupName $config.shm.nps.rg -Parameter $params
    }


    # Remove SRE DNS Zone
    # -------------------
    $null = Set-AzContext -SubscriptionId $config.shm.dns.subscriptionName -ErrorAction Stop
    # Check whether the SHM and/or SRE zones exist on Azure
    try {
        $shmZone = Get-AzDnsZone -Name $config.shm.domain.fqdn -ResourceGroupName $config.shm.dns.rg -ErrorAction Stop
    } catch [Microsoft.Rest.Azure.CloudException] {
        Add-LogMessage -Level Info "Could not find DNS zone for SHM $($config.shm.id) domain ($($config.shm.domain.fqdn))."
        $shmZone = $null
    }
    try {
        $sreZone = Get-AzDnsZone -Name $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg -ErrorAction Stop
    } catch [Microsoft.Rest.Azure.CloudException] {
        Add-LogMessage -Level Info "Could not find DNS zone for SRE $($config.sre.id) domain ($($config.sre.domain.fqdn))."
        $sreZone = $null
    }
    # If the parent SHM record exists on Azure then we can remove the SRE zone entirely
    if ($shmZone) {
        # Delete the SRE DNS zone
        if ($sreZone) {
            Add-LogMessage -Level Info "[ ] Removing $($config.sre.domain.fqdn) DNS Zone"
            Remove-AzDnsZone -Name $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg -Confirm:$false
            if ($?) {
                Add-LogMessage -Level Success "Zone removal succeeded"
            } else {
                Add-LogMessage -Level Fatal "Zone removal failed!"
            }
        }
        # Remove the SRE NS record
        $subdomain = $($config.sre.domain.fqdn).Split(".")[0]
        Add-LogMessage -Level Info "[ ] Removing '$subdomain' NS record from SHM $($config.shm.id) DNS zone ($($config.shm.domain.fqdn))"
        Remove-AzDnsRecordSet -Name $subdomain -RecordType NS -ZoneName $config.shm.domain.fqdn -ResourceGroupName $config.shm.dns.rg
        if ($?) {
            Add-LogMessage -Level Success "Record removal succeeded"
        } else {
            Add-LogMessage -Level Fatal "Record removal failed!"
        }
    # Otherwise we assume that the source of the SRE DNS record is outside Azure and only remove the SRE-specific records
    } else {
        if ($sreZone) {
            # Remove SRE FQDN A record
            Add-LogMessage -Level Info "[ ] Removing '@' A record from SRE $($config.sre.id) DNS zone ($($config.sre.domain.fqdn))"
            Remove-AzDnsRecordSet -Name "@" -RecordType A -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
            $success = $?
            # Remote desktop server CNAME record
            if ($config.sre.remoteDesktop.provider -eq "ApacheGuacamole") {
                $serverHostname = "$($config.sre.remoteDesktop.guacamole.hostname)".ToLower()
            } elseif ($config.sre.remoteDesktop.provider -eq "MicrosoftRDS") {
                $serverHostname = "$($config.sre.remoteDesktop.gateway.hostname)".ToLower()
            } else {
                Add-LogMessage -Level Fatal "Remote desktop type '$($config.sre.remoteDesktop.type)' was not recognised!"
            }
            if ($serverHostname) {
                Add-LogMessage -Level Info "[ ] Removing '$serverHostname' CNAME record from SRE $($config.sre.id) DNS zone ($($config.sre.domain.fqdn))"
                Remove-AzDnsRecordSet -Name $serverHostname -RecordType CNAME -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
                $success = $success -and $?
                # Let's Encrypt ACME records
                foreach ($letsEncryptAcmeDnsRecord in ("_acme-challenge.${serverHostname}".ToLower(), "_acme-challenge.$($config.sre.domain.fqdn)".ToLower(), "_acme-challenge")) {
                    Add-LogMessage -Level Info "[ ] Removing '$letsEncryptAcmeDnsRecord' TXT record from SRE $($config.sre.id) DNS zone ($($config.sre.domain.fqdn))"
                    Remove-AzDnsRecordSet -Name $letsEncryptAcmeDnsRecord -RecordType TXT -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
                    $success = $success -and $?
                }
                # Print success/failure message
                if ($success) {
                    Add-LogMessage -Level Success "Record removal succeeded"
                } else {
                    Add-LogMessage -Level Fatal "Record removal failed!"
                }
            }
        }
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
