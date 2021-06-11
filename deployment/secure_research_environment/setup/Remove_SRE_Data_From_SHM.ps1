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
$sreResources = Get-AzResource | Where-Object { $sreResourceGroupNames.Contains($_.ResourceGroupName) }


# If resources are found then print a warning message
if ($sreResources -or $sreResourceGroups) {
    Add-LogMessage -Level Warning "********************************************************************************"
    Add-LogMessage -Level Warning "*** SRE $shmId $sreId subscription '$($config.sre.subscriptionName)' is not empty!! ***"
    Add-LogMessage -Level Warning "********************************************************************************"
    Add-LogMessage -Level Warning "SRE data should not be deleted from the SHM unless all SRE resources have been deleted from the subscription."
    Add-LogMessage -Level Warning " "
    Add-LogMessage -Level Warning "Resource Groups present in SRE subscription:"
    Add-LogMessage -Level Warning "--------------------------------------------"
    foreach ($resourceGroup in $sreResourceGroups) {
        Add-LogMessage -Level Warning $resourceGroup.ResourceGroupName
    }
    Add-LogMessage -Level Warning "--------------------------------------"
    Add-LogMessage -Level Warning "Resources present in SRE subscription:"
    Add-LogMessage -Level Warning "--------------------------------------"
    foreach ($sreResource in $sreResources) {
        Add-LogMessage -Level Warning "$($sreResource.Name) - $($sreResource.ResourceType)"
    }

# ... otherwise continuing removing artifacts in the SHM subscription
} else {
    $null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop

    # Remove SHM side of peerings involving this SRE
    # ----------------------------------------------
    Add-LogMessage -Level Info "Removing peerings for SRE VNet from SHM VNets..."
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
    Add-LogMessage -Level Info "Removing SRE DNS records from SHM DC..."
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

    # Remove RDS entries from SRE DNS Zone
    # ------------------------------------
    $null = Set-AzContext -SubscriptionId $config.shm.dns.subscriptionName -ErrorAction Stop
    # Check parent SRE domain record exists (if it does not, the other record removals will fail)
    $null = Get-AzDnsZone -ResourceGroupName $config.shm.dns.rg -Name $config.sre.domain.fqdn -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "No DNS Zone for SRE $($config.sre.id) domain ($($config.sre.domain.fqdn)) found."
    } else {
        # SRE FQDN A record
        Add-LogMessage -Level Info "[ ] Removing '@' A record from SRE $($config.sre.id) DNS zone ($($config.sre.domain.fqdn))"
        Remove-AzDnsRecordSet -Name "@" -RecordType A -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
        $success = $?
        # Remote desktop server CNAME record
        if ($config.sre.remoteDesktop.provider -eq "ApacheGuacamole") {
            $serverHostname = "$($config.sre.remoteDesktop.guacamole.hostname)".ToLower()
        } elseif ($config.sre.remoteDesktop.provider -eq "MicrosoftRDS") {
            $serverHostname = "$($config.sre.remoteDesktop.gateway.hostname)".ToLower()
        } elseif ($config.sre.remoteDesktop.provider -eq "CoCalc") {
            $serverHostname = $null
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


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
