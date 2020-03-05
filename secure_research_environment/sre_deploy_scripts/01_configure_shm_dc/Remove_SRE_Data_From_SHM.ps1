param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Look for resources in this subscription
# ---------------------------------------
$sreResourceGroups = @(Get-AzResourceGroup)
$sreResources = @(Get-AzResource)


# If resources are found then print a warning message
if ($sreResources -or $sreResourceGroups) {
    Add-LogMessage -Level Warning "********************************************************************************"
    Add-LogMessage -Level Warning "*** SRE $sreId subscription '$($config.sre.subscriptionName)' is not empty!! ***"
    Add-LogMessage -Level Warning "********************************************************************************"
    Add-LogMessage -Level Warning "SRE data should not be deleted from the SHM unless all SRE resources have been deleted from the subscription."
    Add-LogMessage -Level Warning " "
    Add-LogMessage -Level Warning "Resource Groups present in SRE subscription:"
    Add-LogMessage -Level Warning "--------------------------------------------"
    $sreResourceGroups
    Add-LogMessage -Level Warning "Resources present in SRE subscription:"
    Add-LogMessage -Level Warning "--------------------------------------"
    $sreResources

# ... otherwise continuing removing artifacts in the SHM subscription
} else {
    # Remove SHM side of peerings involving this SRE
    # ----------------------------------------------
    Add-LogMessage -Level Info "Removing peerings for SRE VNet from SHM VNets..."
    $_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName

    # Remove main SRE <-> SHM VNet peering
    $peeringName = "PEER_$($config.sre.network.vnet.name)"
    Add-LogMessage -Level Info "[ ] Removing peering '$peeringName' from SHM VNet '$($config.shm.network.vnet.name)'"
    $_ = Remove-AzVirtualNetworkPeering -Name "$peeringName" -VirtualNetworkName $config.shm.network.vnet.Name -ResourceGroupName $config.shm.network.vnet.rg -Force
    if ($?) {
        Add-LogMessage -Level Success "Peering removal succeeded"
    } else {
        Add-LogMessage -Level Fatal "Peering removal failed!"
    }

    # Remove any SRE <-> Mirror VNet peerings
    $mirrorVnets = Get-AzVirtualNetwork -Name "*" -ResourceGroupName $config.shm.mirrors.rg
    foreach ($mirrorVNet in $mirrorVnets) {
        $peeringName = "PEER_$($config.sre.network.vnet.name)"
        Add-LogMessage -Level Info "[ ] Removing peering '$peeringName' from $($mirrorVNet.Name)..."
        $_ = Remove-AzVirtualNetworkPeering -Name "$peeringName" -VirtualNetworkName $mirrorVNet.Name -ResourceGroupName $config.sre.mirrors.rg -Force
        if ($?) {
            Add-LogMessage -Level Success "Peering removal succeeded"
        } else {
            Add-LogMessage -Level Fatal "Peering removal failed!"
        }
    }


    # Remove SRE users and groups from SHM DC
    # ---------------------------------------
    Add-LogMessage -Level Info "Removing SRE users and groups from SHM DC..."
    $scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Remove_SRE_Data_From_SHM" "Remove_Users_And_Groups_Remote.ps1" -Resolve
    $params = @{
        testResearcherSamAccountName = "`"$($config.sre.users.researchers.test.samAccountName)`""
        dsvmLdapSamAccountName = "`"$($config.sre.users.ldap.dsvm.samAccountName)`""
        gitlabLdapSamAccountName = "`"$($config.sre.users.ldap.gitlab.samAccountName)`""
        hackmdLdapSamAccountName = "`"$($config.sre.users.ldap.hackmd.samAccountName)`""
        sreResearchUserSG = "`"$($config.sre.domain.securityGroups.researchUsers.name)`""
    }
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
    Write-Output $result.Value


    # Remove SRE DNS records from SHM DC
    # ----------------------------------
    Add-LogMessage -Level Info "Removing SRE DNS records from SHM DC..."
    $scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Remove_SRE_Data_From_SHM" "Remove_DNS_Entries_Remote.ps1" -Resolve
    $params = @{
        sreFqdn = "`"$($config.sre.domain.fqdn)`""
        identitySubnetPrefix = "`"$($config.sre.network.subnets.identity.prefix)`""
        rdsSubnetPrefix = "`"$($config.sre.network.subnets.rds.prefix)`""
        dataSubnetPrefix = "`"$($config.sre.network.subnets.data.prefix)`""
    }
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
    Write-Output $result.Value


    # Remove SRE AD Trust from SHM DC
    # -------------------------------
    Add-LogMessage -Level Info "Removing SRE AD Trust from SHM DC..."
    $scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Remove_SRE_Data_From_SHM" "Remove_AD_Trust_Remote.ps1" -Resolve
    $params = @{
        shmFqdn = "`"$($config.shm.domain.fqdn)`""
        sreFqdn = "`"$($config.sre.domain.fqdn)`""
    }
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
    Write-Output $result.Value


    # Remove RDS Gateway RADIUS Client from SHM NPS
    # ---------------------------------------------
    Add-LogMessage -Level Info "Removing RDS Gateway RADIUS Client from SHM NPS..."
    $scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Remove_SRE_Data_From_SHM" "Remove_RDS_Gateway_RADIUS_Client_Remote.ps1" -Resolve
    $params = @{
        rdsGatewayFqdn = "`"$($config.sre.rds.gateway.fqdn)`""
    }
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.nps.vmName -ResourceGroupName $config.shm.nps.rg -Parameter $params
    Write-Output $result.Value


    # Remove RDS entries from SRE DNS Zone
    # ------------------------------------
    $_ = Set-AzContext -SubscriptionId $config.shm.dns.subscriptionName;
    $dnsResourceGroup = $config.shm.dns.rg
    $sreDomain = $config.sre.domain.fqdn
    # RDS @ record
    Add-LogMessage -Level Info "[ ] Removing '@' A record from SRE $sreId DNS zone ($sreDomain)"
    Remove-AzDnsRecordSet -Name "@" -RecordType A -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
    # RDS DNS record
    $rdsDnsRecordname = "$($config.sre.rds.gateway.hostname)".ToLower()
    Add-LogMessage -Level Info "[ ] Removing '$rdsDnsRecordname' CNAME record from SRE $sreId DNS zone ($sreDomain)"
    Remove-AzDnsRecordSet -Name $rdsDnsRecordname -RecordType CNAME -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
    $success = $?
    # RDS ACME records
    foreach ($rdsAcmeDnsRecordname in ("_acme-challenge.$($config.sre.rds.gateway.hostname)".ToLower(), "_acme-challenge")) {
        Add-LogMessage -Level Info "[ ] Removing '$rdsAcmeDnsRecordname' TXT record from SRE $sreId DNS zone ($sreDomain)"
        Remove-AzDnsRecordSet -Name $rdsAcmeDnsRecordname -RecordType TXT -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
        $success = $success -and $?
    }
    # Print success/failure message
    if ($success) {
        Add-LogMessage -Level Success "Record removal succeeded"
    } else {
        Add-LogMessage -Level Fatal "Record removal failed!"
    }
}

# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
