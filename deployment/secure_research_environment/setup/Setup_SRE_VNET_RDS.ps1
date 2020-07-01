param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/GenerateSasToken.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Create VNet resource group if it does not exist
# -----------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.network.vnet.rg -Location $config.sre.location


# Create VNet from template
# -------------------------
Add-LogMessage -Level Info "Creating virtual network '$($config.sre.network.vnet.name)' from template..."
$params = @{
    "Virtual Network Name" = $config.sre.network.vnet.Name
    "Virtual Network Address Space" = $config.sre.network.vnet.cidr
    "Subnet-Identity Address Prefix" = $config.sre.network.subnets.identity.cidr
    "Subnet-RDS Address Prefix" = $config.sre.network.subnets.rds.cidr
    "Subnet-Data Address Prefix" = $config.sre.network.subnets.data.cidr
    "Subnet-Databases Address Prefix" = $config.sre.network.subnets.databases.cidr
    "Subnet-Identity Name" = $config.sre.network.subnets.identity.Name
    "Subnet-RDS Name" = $config.sre.network.subnets.rds.Name
    "Subnet-Data Name" = $config.sre.network.subnets.data.Name
    "Subnet-Databases Name" = $config.sre.network.subnets.databases.Name
    "VNET_DNS_DC1" = $config.shm.dc.ip
    "VNET_DNS_DC2" = $config.shm.dcb.ip
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-vnet-gateway-template.json") -Params $params -ResourceGroupName $config.sre.network.vnet.rg


# Fetch VNet information
# ----------------------
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$sreVnet = Get-AzVirtualNetwork -Name $config.sre.network.vnet.Name -ResourceGroupName $config.sre.network.vnet.rg
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$shmVnet = Get-AzVirtualNetwork -Name $config.shm.network.vnet.Name -ResourceGroupName $config.shm.network.vnet.rg


# Remove existing peerings
# ------------------------
$shmPeeringName = "PEER_$($config.sre.network.vnet.Name)"
$srePeeringName = "PEER_$($config.shm.network.vnet.Name)"
try {
    # From SHM VNet
    $_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
    if (Get-AzVirtualNetworkPeering -VirtualNetworkName $config.shm.network.vnet.name -ResourceGroupName $config.shm.network.vnet.rg -ErrorAction Stop) {
        Add-LogMessage -Level Info "[ ] Removing existing peering '$shmPeeringName' from '$($config.sre.network.vnet.name)' to '$($config.shm.network.vnet.name)'..."
        Remove-AzVirtualNetworkPeering -Name $shmPeeringName -VirtualNetworkName $config.shm.network.vnet.name -ResourceGroupName $config.shm.network.vnet.rg -Force -ErrorAction Stop
    }
    # From SRE VNet
    $_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop
    if (Get-AzVirtualNetworkPeering -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop) {
        Add-LogMessage -Level Info "[ ] Removing existing peering '$srePeeringName' from '$($config.shm.network.vnet.name)' to '$($config.sre.network.vnet.name)'..."
        Remove-AzVirtualNetworkPeering -Name $srePeeringName -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -Force -ErrorAction Stop
    }
    # Success log message
    Add-LogMessage -Level Success "Peering removal succeeded"
} catch {
    Add-LogMessage -Level Fatal "Peering removal failed!"
}


# Add new peerings between SHM and SRE VNets
# ------------------------------------------
try {
    $_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
    Add-LogMessage -Level Info "[ ] Adding peering '$shmPeeringName' from '$($config.sre.network.vnet.name)' to '$($config.shm.network.vnet.name)'..."
    $_ = Add-AzVirtualNetworkPeering -Name $shmPeeringName -VirtualNetwork $shmVnet -RemoteVirtualNetworkId $sreVnet.Id -AllowGatewayTransit -ErrorAction Stop
    # Add peering to SRE VNet
    # -----------------------
    $_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop
    Add-LogMessage -Level Info "[ ] Adding peering '$srePeeringName' from '$($config.shm.network.vnet.name)' to '$($config.sre.network.vnet.name)'..."
    $_ = Add-AzVirtualNetworkPeering -Name $srePeeringName -VirtualNetwork $sreVnet -RemoteVirtualNetworkId $shmVnet.Id -UseRemoteGateways -ErrorAction Stop
    # Success log message
    Add-LogMessage -Level Success "Peering '$($config.shm.network.vnet.name)' and '$($config.sre.network.vnet.name)' succeeded"
} catch {
    Add-LogMessage -Level Fatal "Peering '$($config.shm.network.vnet.name)' and '$($config.sre.network.vnet.name)' failed!"
}


# Set constants used in this script
# ---------------------------------
$remoteUploadDir = "C:\Installation"
$containerNameGateway = "sre-rds-gateway-scripts"
$containerNameSessionHosts = "sre-rds-sh-packages"
$vmNamePairs = @(("RDS Gateway", $config.sre.rds.gateway.vmName),
                 ("RDS Session Host (App server)", $config.sre.rds.sessionHost1.vmName),
                 ("RDS Session Host (Remote desktop server)", $config.sre.rds.sessionHost2.vmName),
                 ("RDS Session Host (Review server)", $config.sre.rds.sessionHost3.vmName))


# Set variables used in template expansion, retrieving from the key vault where appropriate
# -----------------------------------------------------------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$dataSubnetIpPrefix = $config.sre.network.subnets.data.prefix
$airlockSubnetIpPrefix = $config.sre.network.subnets.airlock.prefix
$rdsGatewayVmFqdn = $config.sre.rds.gateway.fqdn
$rdsGatewayVmName = $config.sre.rds.gateway.vmName
$rdsSh1VmFqdn = $config.sre.rds.sessionHost1.fqdn
$rdsSh1VmName = $config.sre.rds.sessionHost1.vmName
$rdsSh2VmFqdn = $config.sre.rds.sessionHost2.fqdn
$rdsSh2VmName = $config.sre.rds.sessionHost2.vmName
$rdsSh3VmFqdn = $config.sre.rds.sessionHost3.fqdn
$rdsSh3VmName = $config.sre.rds.sessionHost3.vmName
$researchUserSgName = $config.sre.domain.securityGroups.researchUsers.name
$reviewUserSgName = $config.sre.domain.securityGroups.reviewUsers.name
$shmDcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.domainAdminPassword
$shmDcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.shm.id)admin".ToLower()
$shmNetbiosName = $config.shm.domain.netbiosName
$sreAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.rdsAdminPassword
$sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$sreFqdn = $config.sre.domain.fqdn


# Ensure that boot diagnostics resource group and storage account exist
# ---------------------------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$_ = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location


# Ensure that SRE resource group and storage accounts exist
# ---------------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.storage.artifacts.rg -Location $config.sre.location
$sreStorageAccount = Deploy-StorageAccount -Name $config.sre.storage.artifacts.accountName -ResourceGroupName $config.sre.storage.artifacts.rg -Location $config.sre.location


# Get SHM storage account
# -----------------------
$_ = Set-AzContext -Subscription $config.shm.subscriptionName
$shmStorageAccount = Deploy-StorageAccount -Name $config.shm.storage.artifacts.accountName -ResourceGroupName $config.shm.storage.artifacts.rg -Location $config.shm.location
$_ = Set-AzContext -Subscription $config.sre.subscriptionName


# Set up the NSGs for the gateway and session hosts
# -------------------------------------------------
$nsgGateway = Deploy-NetworkSecurityGroup -Name $config.sre.rds.gateway.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgGateway `
                             -Name "HttpsIn" `
                             -Description "Allow HTTPS inbound to RDS server" `
                             -Priority 100 `
                             -Direction Inbound -Access Allow -Protocol TCP `
                             -SourceAddressPrefix Internet -SourcePortRange * `
                             -DestinationAddressPrefix * -DestinationPortRange 443
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgGateway `
                             -Name "RadiusAuthenticationRdsToNps" `
                             -Description "Authenticate to SHM RADIUS server" `
                             -Priority 300 `
                             -Direction Outbound -Access Allow -Protocol * `
                             -SourceAddressPrefix * -SourcePortRange * `
                             -DestinationAddressPrefix $config.shm.nps.ip -DestinationPortRange 1645,1646,1812,1813
$nsgSessionHosts = Deploy-NetworkSecurityGroup -Name $config.sre.rds.sessionHost1.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgSessionHosts `
                             -Name "Deny_Internet" `
                             -Description "Deny Outbound Internet Access" `
                             -Priority 4000 `
                             -Direction Outbound -Access Deny -Protocol * `
                             -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
                             -DestinationAddressPrefix Internet -DestinationPortRange *


# Create RDS resource group if it does not exist
# ----------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.rds.rg -Location $config.sre.location


# Deploy RDS from template
# ------------------------
Add-LogMessage -Level Info "Deploying RDS from template..."
$_ = Set-AzContext -Subscription $config.sre.subscriptionName
$params = @{
    Administrator_Password = (ConvertTo-SecureString $sreAdminPassword -AsPlainText -Force)
    Administrator_User = $sreAdminUsername
    BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName
    DC_Administrator_Password = (ConvertTo-SecureString $shmDcAdminPassword -AsPlainText -Force)
    DC_Administrator_User = $shmDcAdminUsername
    Domain_Name = $config.shm.domain.fqdn
    NSG_Gateway_Name = $config.sre.rds.gateway.nsg
    RDS_Gateway_IP_Address = $config.sre.rds.gateway.ip
    RDS_Gateway_Name = $config.sre.rds.gateway.vmName
    RDS_Gateway_VM_Size = $config.sre.rds.gateway.vmSize
    RDS_Session_Host_Apps_IP_Address = $config.sre.rds.sessionHost1.ip
    RDS_Session_Host_Apps_Name = $config.sre.rds.sessionHost1.vmName
    RDS_Session_Host_Apps_VM_Size = $config.sre.rds.sessionHost1.vmSize
    RDS_Session_Host_Desktop_IP_Address = $config.sre.rds.sessionHost2.ip
    RDS_Session_Host_Desktop_Name = $config.sre.rds.sessionHost2.vmName
    RDS_Session_Host_Desktop_VM_Size = $config.sre.rds.sessionHost2.vmSize
    RDS_Session_Host_Review_IP_Address = $config.sre.rds.sessionHost3.ip
    RDS_Session_Host_Review_Name = $config.sre.rds.sessionHost3.vmName
    RDS_Session_Host_Review_VM_Size = $config.sre.rds.sessionHost3.vmSize
    SRE_ID = $config.sre.Id
    Virtual_Network_Name = $config.sre.network.vnet.Name
    Virtual_Network_Resource_Group = $config.sre.network.vnet.rg
    Virtual_Network_Subnet = $config.sre.network.subnets.rds.Name
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-rds-template.json") -Params $params -ResourceGroupName $config.sre.rds.rg


# Create blob containers in SRE storage account
# ---------------------------------------------
Add-LogMessage -Level Info "Creating blob storage containers in storage account '$($sreStorageAccount.StorageAccountName)'..."
foreach ($containerName in ($containerNameGateway, $containerNameSessionHosts)) {
    Deploy-StorageContainer -Name $containerName -StorageAccount $sreStorageAccount
    Clear-StorageContainer -Name $containerName -StorageAccount $sreStorageAccount
}


# Upload RDS deployment scripts and installers to SRE storage
# -----------------------------------------------------------
Add-LogMessage -Level Info "Upload RDS deployment scripts to storage..."

# Expand deploy script
$deployScriptLocalFilePath = (New-TemporaryFile).FullName
$template = Join-Path $PSScriptRoot ".." "remote" "create_rds" "templates" "Deploy_RDS_Environment.template.ps1" | Get-Item | Get-Content -Raw
$template.Replace('<airlockSubnetIpPrefix>',$airlockSubnetIpPrefix).
          Replace('<dataSubnetIpPrefix>',$dataSubnetIpPrefix).
          Replace('<rdsGatewayVmFqdn>',$rdsGatewayVmFqdn).
          Replace('<rdsGatewayVmName>', $rdsGatewayVmName).
          Replace('<rdsSh1VmFqdn>',$rdsSh1VmFqdn).
          Replace('<rdsSh1VmName>',$rdsSh1VmName).
          Replace('<rdsSh2VmFqdn>',$rdsSh2VmFqdn).
          Replace('<rdsSh2VmName>',$rdsSh2VmName).
          Replace('<rdsSh3VmFqdn>',$rdsSh3VmFqdn).
          Replace('<rdsSh3VmName>',$rdsSh3VmName).
          Replace('<remoteUploadDir>',$remoteUploadDir).
          Replace('<researchUserSgName>',$researchUserSgName).
          Replace('<reviewUserSgName>',$reviewUserSgName).
          Replace('<shmDcAdminUsername>',$shmDcAdminUsername).
          Replace('<shmNetbiosName>', $shmNetbiosName).
          Replace('<sreFqdn>',$sreFqdn) | Out-File $deployScriptLocalFilePath

# Expand server list XML
$serverListLocalFilePath = (New-TemporaryFile).FullName
$template = Join-Path $PSScriptRoot ".." "remote" "create_rds" "templates" "ServerList.template.xml" | Get-Item | Get-Content -Raw
$template.Replace('<rdsGatewayVmFqdn>',$rdsGatewayVmFqdn).
          Replace('<rdsGatewayVmName>', $rdsGatewayVmName).
          Replace('<rdsSh1VmFqdn>',$rdsSh1VmFqdn).
          Replace('<rdsSh2VmFqdn>',$rdsSh2VmFqdn).
          Replace('<rdsSh3VmFqdn>',$rdsSh3VmFqdn).
          Replace('<sreFqdn>',$sreFqdn) | Out-File $serverListLocalFilePath

# Copy installers from SHM storage
Add-LogMessage -Level Info "[ ] Copying RDS installers to storage account '$($sreStorageAccount.StorageAccountName)'"
$blobs = Get-AzStorageBlob -Context $shmStorageAccount.Context -Container $containerNameSessionHosts
$blobs | Start-AzStorageBlobCopy -Context $shmStorageAccount.Context -DestContext $sreStorageAccount.Context -DestContainer $containerNameSessionHosts -Force
if ($?) {
    Add-LogMessage -Level Success "File copying succeeded"
} else {
    Add-LogMessage -Level Fatal "File copying failed!"
}

# Upload scripts
Add-LogMessage -Level Info "[ ] Uploading RDS gateway scripts to storage account '$($sreStorageAccount.StorageAccountName)'"
Set-AzStorageBlobContent -Container $containerNameGateway -Context $sreStorageAccount.Context -File $deployScriptLocalFilePath -Blob "Deploy_RDS_Environment.ps1" -Force
Set-AzStorageBlobContent -Container $containerNameGateway -Context $sreStorageAccount.Context -File $serverListLocalFilePath -Blob "ServerList.xml" -Force
if ($?) {
    Add-LogMessage -Level Success "File uploading succeeded"
} else {
    Add-LogMessage -Level Fatal "File uploading failed!"
}


# Add DNS records for RDS Gateway
# -------------------------------
Add-LogMessage -Level Info "Adding DNS record for RDS Gateway"
$_ = Set-AzContext -Subscription $config.sre.subscriptionName

# Get public IP address of RDS gateway
$rdsGatewayVM = Get-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.gateway.vmName
$rdsGatewayPrimaryNicId = ($rdsGateWayVM.NetworkProfile.NetworkInterfaces | Where-Object { $_.Primary })[0].Id
$rdsRgPublicIps = (Get-AzPublicIpAddress -ResourceGroupName $config.sre.rds.rg)
$rdsGatewayPublicIp = ($rdsRgPublicIps | Where-Object { $_.IpConfiguration.Id -like "$rdsGatewayPrimaryNicId*" }).IpAddress

# Add DNS records to SRE DNS Zone
$_ = Set-AzContext -SubscriptionId $config.shm.dns.subscriptionName
$baseDnsRecordname = "@"
$gatewayDnsRecordname = "$($config.sre.rds.gateway.hostname)".ToLower()
$dnsResourceGroup = $config.shm.dns.rg
$dnsTtlSeconds = 30

# Set the A record
Add-LogMessage -Level Info "[ ] Setting 'A' record for gateway host to '$rdsGatewayPublicIp' in SRE $($config.sre.id) DNS zone ($sreFqdn)"
Remove-AzDnsRecordSet -Name $baseDnsRecordname -RecordType A -ZoneName $sreFqdn -ResourceGroupName $dnsResourceGroup
$result = New-AzDnsRecordSet -Name $baseDnsRecordname -RecordType A -ZoneName $sreFqdn -ResourceGroupName $dnsResourceGroup `
                             -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -IPv4Address $rdsGatewayPublicIp)
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'A' record for gateway host"
} else {
    Add-LogMessage -Level Info "Failed to set 'A' record for gateway host!"
}

# Set the CNAME record
Add-LogMessage -Level Info "[ ] Setting CNAME record for gateway host to point to the 'A' record in SRE $($config.sre.id) DNS zone ($sreFqdn)"
Remove-AzDnsRecordSet -Name $gatewayDnsRecordname -RecordType CNAME -ZoneName $sreFqdn -ResourceGroupName $dnsResourceGroup
$result = New-AzDnsRecordSet -Name $gatewayDnsRecordname -RecordType CNAME -ZoneName $sreFqdn -ResourceGroupName $dnsResourceGroup `
                             -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Cname $sreFqdn)
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'CNAME' record for gateway host"
} else {
    Add-LogMessage -Level Info "Failed to set 'CNAME' record for gateway host!"
}


# Add RDS VMs to correct OUs
# --------------------------
$_ = Set-AzContext -Subscription $config.shm.subscriptionName
Add-LogMessage -Level Info "Adding RDS VMs to correct OUs on SHM DC..."
# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Move_RDS_VMs_Into_OUs.ps1"
$params = @{
    shmDn = "`"$($config.shm.domain.dn)`""
    gatewayHostname = "`"$($config.sre.rds.gateway.hostname)`""
    sh1Hostname = "`"$($config.sre.rds.sessionHost1.hostname)`""
    sh2Hostname = "`"$($config.sre.rds.sessionHost2.hostname)`""
    sh3Hostname = "`"$($config.sre.rds.sessionHost3.hostname)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Set locale, install updates and reboot
# --------------------------------------
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    Add-LogMessage -Level Info "Updating ${name}: '$vmName'..."
    Invoke-WindowsConfigureAndUpdate -VMName $vmName -ResourceGroupName $config.sre.rds.rg
}


# Import files to RDS VMs
# -----------------------

Add-LogMessage -Level Info "Importing files from storage to RDS VMs..."

# Set correct list of package from blob storage for each session host
$blobfiles = @{}
$vmNamePairs | ForEach-Object { $blobfiles[$_[1]] = @() }
foreach ($blob in Get-AzStorageBlob -Container $containerNameSessionHosts -Context $sreStorageAccount.Context) {
    if (($blob.Name -like "*GoogleChrome_x64.msi") -or ($blob.Name -like "*PuTTY_x64.msi")) {
        $blobfiles[$config.sre.rds.sessionHost1.vmName] += @{$containerNameSessionHosts = $blob.Name}
        $blobfiles[$config.sre.rds.sessionHost2.vmName] += @{$containerNameSessionHosts = $blob.Name}
        $blobfiles[$config.sre.rds.sessionHost3.vmName] += @{$containerNameSessionHosts = $blob.Name}
    } elseif ($blob.Name -like "*LibreOffice_x64.msi") {
        $blobfiles[$config.sre.rds.sessionHost2.vmName] += @{$containerNameSessionHosts = $blob.Name}
    }
}
# ... and for the gateway
foreach ($blob in Get-AzStorageBlob -Container $containerNameGateway -Context $sreStorageAccount.Context) {
    $blobfiles[$config.sre.rds.gateway.vmName] += @{$containerNameGateway = $blob.Name}
}

# Copy software and/or scripts to RDS VMs
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Import_And_Install_Blobs.ps1"
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    $containerName = $blobfiles[$vmName] | ForEach-Object { $_.Keys } | Select-Object -First 1
    $fileNames = $blobfiles[$vmName] | ForEach-Object { $_.Values }
    $sasToken = New-ReadOnlyAccountSasToken -SubscriptionName $config.sre.subscriptionName -ResourceGroup $config.sre.storage.artifacts.rg -AccountName $sreStorageAccount.StorageAccountName
    Add-LogMessage -Level Info "[ ] Copying $($fileNames.Count) files to $name"
    $params = @{
        storageAccountName = "`"$($sreStorageAccount.StorageAccountName)`""
        storageService = "blob"
        shareOrContainerName = "`"$containerName`""
        sasToken = "`"$sasToken`""
        pipeSeparatedRemoteFilePaths = "`"$($fileNames -join "|")`""
        downloadDir = "$remoteUploadDir"
    }
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
    Write-Output $result.Value
}


# Set locale, install updates and reboot
# --------------------------------------
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    Add-LogMessage -Level Info "Updating ${name}: '$vmName'..."
    $params = @{}
    # The RDS Gateway needs the RDWebClientManagement Powershell module
    if ($name -eq "RDS Gateway") { $params["AdditionalPowershellModules"] = @("RDWebClientManagement") }
    Invoke-WindowsConfigureAndUpdate -VMName $vmName -ResourceGroupName $config.sre.rds.rg @params
}

# Add VMs to correct NSG
# ----------------------
Add-VmToNSG -VMName $config.sre.rds.gateway.vmName -NSGName $config.sre.rds.gateway.nsg
Add-VmToNSG -VMName $config.sre.rds.sessionHost1.vmName -NSGName $config.sre.rds.sessionHost1.nsg
Add-VmToNSG -VMName $config.sre.rds.sessionHost2.vmName -NSGName $config.sre.rds.sessionHost2.nsg
Add-VmToNSG -VMName $config.sre.rds.sessionHost3.vmName -NSGName $config.sre.rds.sessionHost3.nsg


# Reboot all the RDS VMs
# ----------------------
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    Enable-AzVM -Name $vmName -ResourceGroupName $config.sre.rds.rg
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
