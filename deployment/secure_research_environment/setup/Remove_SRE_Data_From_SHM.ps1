param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Look for resources in this subscription
# ---------------------------------------
$sreResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "RG_SRE_$($config.sre.id)*" })
$sreResources = @(Get-AzResource | Where-Object { $_.ResourceGroupName -like "RG_SRE_$($config.sre.id)*" })


# If resources are found then print a warning message
if ($sreResources -or $sreResourceGroups) {
    Add-LogMessage -Level Warning "********************************************************************************"
    Add-LogMessage -Level Warning "*** SRE $configId subscription '$($config.sre.subscriptionName)' is not empty!! ***"
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
    $null = Set-AzContext -SubscriptionId $config.shm.subscriptionName

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
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_shm_dc" "scripts" "Remove_Users_And_Groups_Remote.ps1" -Resolve
    $params = @{
        groupNamesJoined           = "`"$($groupNames -Join '|')`""
        userNamesJoined            = "`"$($userNames -Join '|')`""
        computerNamePatternsJoined = "`"$($computerNamePatterns -Join '|')`""
    }
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
    Write-Output $result.Value


    # Remove SRE DNS records from SHM DC
    # ----------------------------------
    Add-LogMessage -Level Info "Removing SRE DNS records from SHM DC..."
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_shm_dc" "scripts" "Remove_DNS_Entries_Remote.ps1" -Resolve
    $params = @{
        shmFqdn = "`"$($config.shm.domain.fqdn)`""
        sreId   = "`"$($config.sre.id)`""
    }
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
    Write-Output $result.Value


    # Remove RDS Gateway RADIUS Client from SHM NPS
    # ---------------------------------------------
    Add-LogMessage -Level Info "Removing RDS Gateway RADIUS Client from SHM NPS..."
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_shm_dc" "scripts" "Remove_RDS_Gateway_RADIUS_Client_Remote.ps1" -Resolve
    $params = @{
        rdsGatewayFqdn = "`"$($config.sre.rds.gateway.fqdn)`""
    }
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.nps.vmName -ResourceGroupName $config.shm.nps.rg -Parameter $params
    Write-Output $result.Value


    # Remove RDS entries from SRE DNS Zone
    # ------------------------------------
    $null = Set-AzContext -SubscriptionId $config.shm.dns.subscriptionName;
    $dnsResourceGroup = $config.shm.dns.rg
    $sreDomain = $config.sre.domain.fqdn
    # Check parent SRE domain record exists (if it does not, the other record removals will fail)
    Get-AzDnsZone -ResourceGroupName $dnsResourceGroup -Name $sreDomain -ErrorVariable notExists -ErrorAction SilentlyContinue 
    if($notExists) {
        Add-LogMessage -Level Info "No DNS Zone for SRE $($config.sre.id) domain ($sreDomain) found."
    } else {
        # RDS @ record
        Add-LogMessage -Level Info "[ ] Removing '@' A record from SRE $($config.sre.id) DNS zone ($sreDomain)"
        Remove-AzDnsRecordSet -Name "@" -RecordType A -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
        $success = $?
        # RDS DNS record
        $rdsDnsRecordname = "$($config.sre.rds.gateway.hostname)".ToLower()
        Add-LogMessage -Level Info "[ ] Removing '$rdsDnsRecordname' CNAME record from SRE $($config.sre.id) DNS zone ($sreDomain)"
        Remove-AzDnsRecordSet -Name $rdsDnsRecordname -RecordType CNAME -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
        $success = $success -and $?
        # RDS ACME records
        foreach ($rdsAcmeDnsRecordname in ("_acme-challenge.$($config.sre.rds.gateway.hostname)".ToLower(), "_acme-challenge")) {
            Add-LogMessage -Level Info "[ ] Removing '$rdsAcmeDnsRecordname' TXT record from SRE $($config.sre.id) DNS zone ($sreDomain)"
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
}

# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext;
