param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/GenerateSasToken.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Create VNet resource group if it does not exist
# -----------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.network.vnet.rg -Location $config.sre.location


# Create VNet and subnets
# -----------------------
$sreVnet = Deploy-VirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -AddressPrefix $config.sre.network.vnet.cidr -Location $config.sre.location -DnsServer $config.shm.dc.ip, $config.shm.dcb.ip
$null = Deploy-Subnet -Name $config.sre.network.vnet.subnets.data.name -VirtualNetwork $sreVnet -AddressPrefix $config.sre.network.vnet.subnets.data.cidr
$null = Deploy-Subnet -Name $config.sre.network.vnet.subnets.databases.name -VirtualNetwork $sreVnet -AddressPrefix $config.sre.network.vnet.subnets.databases.cidr
$null = Deploy-Subnet -Name $config.sre.network.vnet.subnets.identity.name -VirtualNetwork $sreVnet -AddressPrefix $config.sre.network.vnet.subnets.identity.cidr
$null = Deploy-Subnet -Name $config.sre.network.vnet.subnets.rds.name -VirtualNetwork $sreVnet -AddressPrefix $config.sre.network.vnet.subnets.rds.cidr


# Remove existing peerings
# ------------------------
$shmPeeringName = "PEER_$($config.sre.network.vnet.name)"
$srePeeringName = "PEER_$($config.shm.network.vnet.name)"
try {
    # From SHM VNet
    $null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
    $shmVnet = Get-AzVirtualNetwork -Name $config.shm.network.vnet.name -ResourceGroupName $config.shm.network.vnet.rg -ErrorAction Stop
    if (Get-AzVirtualNetworkPeering -VirtualNetworkName $config.shm.network.vnet.name -ResourceGroupName $config.shm.network.vnet.rg -ErrorAction Stop) {
        Add-LogMessage -Level Info "[ ] Removing existing peering from '$($config.sre.network.vnet.name)' to '$($config.shm.network.vnet.name)'..."
        Remove-AzVirtualNetworkPeering -Name $shmPeeringName -VirtualNetworkName $config.shm.network.vnet.name -ResourceGroupName $config.shm.network.vnet.rg -Force -ErrorAction Stop
    }
    # From SRE VNet
    $null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop
    if (Get-AzVirtualNetworkPeering -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop) {
        Add-LogMessage -Level Info "[ ] Removing existing peering from '$($config.shm.network.vnet.name)' to '$($config.sre.network.vnet.name)'..."
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
    $null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
    Add-LogMessage -Level Info "[ ] Adding peering '$shmPeeringName' from '$($config.sre.network.vnet.name)' to '$($config.shm.network.vnet.name)'..."
    $null = Add-AzVirtualNetworkPeering -Name $shmPeeringName -VirtualNetwork $shmVnet -RemoteVirtualNetworkId $sreVnet.Id -AllowGatewayTransit -ErrorAction Stop
    # Add peering to SRE VNet
    # -----------------------
    $null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop
    Add-LogMessage -Level Info "[ ] Adding peering '$srePeeringName' from '$($config.shm.network.vnet.name)' to '$($config.sre.network.vnet.name)'..."
    $null = Add-AzVirtualNetworkPeering -Name $srePeeringName -VirtualNetwork $sreVnet -RemoteVirtualNetworkId $shmVnet.Id -UseRemoteGateways -ErrorAction Stop
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
                 ("RDS Session Host (Remote desktop server)", $config.sre.rds.sessionHost2.vmName))


# Set variables used in template expansion, retrieving from the key vault where appropriate
# -----------------------------------------------------------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$domainAdminUsername = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.domainAdminUsername
$domainJoinGatewayPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.users.computerManagers.rdsGatewayServers.passwordSecretName -DefaultLength 20
$domainJoinSessionHostPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.users.computerManagers.rdsSessionServers.passwordSecretName -DefaultLength 20
$dsvmInitialIpAddress = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.data.cidr -Offset 160
$rdsGatewayAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.rds.gateway.adminPasswordSecretName -DefaultLength 20
$rdsGatewayVmFqdn = $config.sre.rds.gateway.fqdn
$rdsGatewayVmName = $config.sre.rds.gateway.vmName
$rdsSh1AdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.rds.sessionHost1.adminPasswordSecretName -DefaultLength 20
$rdsSh1VmFqdn = $config.sre.rds.sessionHost1.fqdn
$rdsSh1VmName = $config.sre.rds.sessionHost1.vmName
$rdsSh2AdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.rds.sessionHost2.adminPasswordSecretName -DefaultLength 20
$rdsSh2VmFqdn = $config.sre.rds.sessionHost2.fqdn
$researchUserSgName = $config.sre.domain.securityGroups.researchUsers.name
$reviewUserSgName = $config.sre.domain.securityGroups.reviewUsers.name
$shmNetbiosName = $config.shm.domain.netbiosName
$sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$sreDomain = $config.sre.domain.fqdn


# Ensure that boot diagnostics resource group and storage account exist
# ---------------------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$null = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location


# Ensure that SRE resource group and storage accounts exist
# ---------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.storage.artifacts.rg -Location $config.sre.location
$sreStorageAccount = Deploy-StorageAccount -Name $config.sre.storage.artifacts.accountName -ResourceGroupName $config.sre.storage.artifacts.rg -Location $config.sre.location


# Get SHM storage account
# -----------------------
$null = Set-AzContext -Subscription $config.shm.subscriptionName
$shmStorageAccount = Deploy-StorageAccount -Name $config.shm.storage.artifacts.accountName -ResourceGroupName $config.shm.storage.artifacts.rg -Location $config.shm.location
$null = Set-AzContext -Subscription $config.sre.subscriptionName


# Set up the NSGs for the gateway and session hosts
# -------------------------------------------------
$nsgGateway = Deploy-NetworkSecurityGroup -Name $config.sre.rds.gateway.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgGateway `
                             -Name "HttpsIn" `
                             -Description "Allow HTTPS inbound to RDS server" `
                             -Priority 100 `
                             -Direction Inbound `
                             -Access Allow `
                             -Protocol TCP `
                             -SourceAddressPrefix Internet `
                             -SourcePortRange * `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange 443
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgGateway `
                             -Name "RadiusAuthenticationRdsToNps" `
                             -Description "Authenticate to SHM RADIUS server" `
                             -Priority 300 `
                             -Direction Outbound `
                             -Access Allow `
                             -Protocol * `
                             -SourceAddressPrefix * `
                             -SourcePortRange * `
                             -DestinationAddressPrefix $config.shm.nps.ip `
                             -DestinationPortRange 1645, 1646, 1812, 1813
$nsgSessionHosts = Deploy-NetworkSecurityGroup -Name $config.sre.rds.sessionHost1.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgSessionHosts `
                             -Name "Deny_Internet" `
                             -Description "Deny Outbound Internet Access" `
                             -Priority 4000 `
                             -Direction Outbound `
                             -Access Deny `
                             -Protocol * `
                             -SourceAddressPrefix VirtualNetwork `
                             -SourcePortRange * `
                             -DestinationAddressPrefix Internet `
                             -DestinationPortRange *


# Create RDS resource group if it does not exist
# ----------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.rds.rg -Location $config.sre.location


# Deploy RDS from template
# ------------------------
Add-LogMessage -Level Info "Deploying RDS from template..."
$null = Set-AzContext -Subscription $config.sre.subscriptionName
$params = @{
    Administrator_User                       = $sreAdminUsername
    BootDiagnostics_Account_Name             = $config.sre.storage.bootdiagnostics.accountName
    Domain_Join_Password_Gateway             = (ConvertTo-SecureString $domainJoinGatewayPassword -AsPlainText -Force)
    Domain_Join_Password_Session_Hosts       = (ConvertTo-SecureString $domainJoinSessionHostPassword -AsPlainText -Force)
    Domain_Join_User_Gateway                 = $config.shm.users.computerManagers.rdsGatewayServers.samAccountName
    Domain_Join_User_Session_Hosts           = $config.shm.users.computerManagers.rdsSessionServers.samAccountName
    Domain_Name                              = $config.shm.domain.fqdn
    NSG_Gateway_Name                         = $config.sre.rds.gateway.nsg
    OU_Path_Gateway                          = $config.shm.domain.ous.rdsGatewayServers.path
    OU_Path_Session_Hosts                    = $config.shm.domain.ous.rdsSessionServers.path
    RDS_Gateway_Admin_Password               = (ConvertTo-SecureString $rdsGatewayAdminPassword -AsPlainText -Force)
    RDS_Gateway_Data1_Disk_Size_GB           = [int]$config.sre.rds.gateway.disks.data1.sizeGb
    RDS_Gateway_Data1_Disk_Type              = $config.sre.rds.gateway.disks.data1.type
    RDS_Gateway_Data2_Disk_Size_GB           = [int]$config.sre.rds.gateway.disks.data2.sizeGb
    RDS_Gateway_Data2_Disk_Type              = $config.sre.rds.gateway.disks.data2.type
    RDS_Gateway_IP_Address                   = $config.sre.rds.gateway.ip
    RDS_Gateway_Name                         = $config.sre.rds.gateway.vmName
    RDS_Gateway_Os_Disk_Size_GB              = [int]$config.sre.rds.gateway.disks.os.sizeGb
    RDS_Gateway_Os_Disk_Type                 = $config.sre.rds.gateway.disks.os.type
    RDS_Gateway_VM_Size                      = $config.sre.rds.gateway.vmSize
    RDS_Session_Host_Apps_Admin_Password     = (ConvertTo-SecureString $rdsSh1AdminPassword -AsPlainText -Force)
    RDS_Session_Host_Apps_IP_Address         = $config.sre.rds.sessionHost1.ip
    RDS_Session_Host_Apps_Name               = $config.sre.rds.sessionHost1.vmName
    RDS_Session_Host_Apps_Os_Disk_Size_GB    = [int]$config.sre.rds.sessionHost1.disks.os.sizeGb
    RDS_Session_Host_Apps_Os_Disk_Type       = $config.sre.rds.sessionHost1.disks.os.type
    RDS_Session_Host_Apps_VM_Size            = $config.sre.rds.sessionHost1.vmSize
    RDS_Session_Host_Desktop_Admin_Password  = (ConvertTo-SecureString $rdsSh2AdminPassword -AsPlainText -Force)
    RDS_Session_Host_Desktop_IP_Address      = $config.sre.rds.sessionHost2.ip
    RDS_Session_Host_Desktop_Name            = $config.sre.rds.sessionHost2.vmName
    RDS_Session_Host_Desktop_Os_Disk_Size_GB = [int]$config.sre.rds.sessionHost2.disks.os.sizeGb
    RDS_Session_Host_Desktop_Os_Disk_Type    = $config.sre.rds.sessionHost2.disks.os.type
    RDS_Session_Host_Desktop_VM_Size         = $config.sre.rds.sessionHost2.vmSize
    SRE_ID                                   = $config.sre.id
    Virtual_Network_Name                     = $config.sre.network.vnet.name
    Virtual_Network_Resource_Group           = $config.sre.network.vnet.rg
    Virtual_Network_Subnet                   = $config.sre.network.vnet.subnets.rds.name
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-rds-template.json") -Params $params -ResourceGroupName $config.sre.rds.rg


# Create blob containers in SRE storage account
# ---------------------------------------------
Add-LogMessage -Level Info "Creating blob storage containers in storage account '$($sreStorageAccount.StorageAccountName)'..."
foreach ($containerName in ($containerNameGateway, $containerNameSessionHosts)) {
    $null = Deploy-StorageContainer -Name $containerName -StorageAccount $sreStorageAccount
    $blobs = @(Get-AzStorageBlob -Container $containerName -Context $sreStorageAccount.Context)
    $numBlobs = $blobs.Length
    if ($numBlobs -gt 0) {
        Add-LogMessage -Level Info "[ ] deleting $numBlobs blobs aready in container '$containerName'..."
        $blobs | ForEach-Object { Remove-AzStorageBlob -Blob $_.Name -Container $containerName -Context $sreStorageAccount.Context -Force }
        while ($numBlobs -gt 0) {
            Start-Sleep -Seconds 5
            $numBlobs = (Get-AzStorageBlob -Container $containerName -Context $sreStorageAccount.Context).Length
        }
        if ($?) {
            Add-LogMessage -Level Success "Blob deletion succeeded"
        } else {
            Add-LogMessage -Level Fatal "Blob deletion failed!"
        }
    }
}


# Upload RDS deployment scripts and installers to SRE storage
# -----------------------------------------------------------
Add-LogMessage -Level Info "Upload RDS deployment scripts to storage..."

# Expand deploy script
$deployScriptLocalFilePath = (New-TemporaryFile).FullName
$template = Join-Path $PSScriptRoot ".." "remote" "create_rds" "templates" "Deploy_RDS_Environment.template.ps1" | Get-Item | Get-Content -Raw
$template.Replace("<domainAdminUsername>", $domainAdminUsername).
          Replace("<dsvmInitialIpAddress>", $dsvmInitialIpAddress).
          Replace("<gitlabIpAddress>", $config.sre.webapps.gitlab.ip).
          Replace("<hackmdIpAddress>", $config.sre.webapps.hackmd.ip).
          Replace("<rdsGatewayVmFqdn>", $rdsGatewayVmFqdn).
          Replace("<rdsGatewayVmName>", $rdsGatewayVmName).
          Replace("<rdsSh1VmFqdn>", $rdsSh1VmFqdn).
          Replace("<rdsSh1VmName>", $rdsSh1VmName).
          Replace("<rdsSh2VmFqdn>", $rdsSh2VmFqdn).
          Replace("<rdsSh2VmName>", $rdsSh2VmName).
          Replace("<remoteUploadDir>", $remoteUploadDir).
          Replace("<researchUserSgName>", $researchUserSgName).
          Replace("<shmNetbiosName>", $shmNetbiosName).
          Replace("<sreDomain>", $sreDomain) | Out-File $deployScriptLocalFilePath

# Expand server list XML
$serverListLocalFilePath = (New-TemporaryFile).FullName
$template = Join-Path $PSScriptRoot ".." "remote" "create_rds" "templates" "ServerList.template.xml" | Get-Item | Get-Content -Raw
$template.Replace("<rdsGatewayVmFqdn>", $rdsGatewayVmFqdn).
          Replace("<rdsSh1VmFqdn>", $rdsSh1VmFqdn).
          Replace("<rdsSh2VmFqdn>", $rdsSh2VmFqdn) | Out-File $serverListLocalFilePath

# Copy installers from SHM storage
Add-LogMessage -Level Info "[ ] Copying RDS installers to storage account '$($sreStorageAccount.StorageAccountName)'"
$blobs = Get-AzStorageBlob -Context $shmStorageAccount.Context -Container $containerNameSessionHosts
$null = $blobs | Start-AzStorageBlobCopy -Context $shmStorageAccount.Context -DestContext $sreStorageAccount.Context -DestContainer $containerNameSessionHosts -Force
if ($?) {
    Add-LogMessage -Level Success "File copying succeeded"
} else {
    Add-LogMessage -Level Fatal "File copying failed!"
}

# Upload scripts
Add-LogMessage -Level Info "[ ] Uploading RDS gateway scripts to storage account '$($sreStorageAccount.StorageAccountName)'"
$success = $true
$null = Set-AzStorageBlobContent -Container $containerNameGateway -Context $sreStorageAccount.Context -File $deployScriptLocalFilePath -Blob "Deploy_RDS_Environment.ps1" -Force
$success = $success -and $?
$null = Set-AzStorageBlobContent -Container $containerNameGateway -Context $sreStorageAccount.Context -File $serverListLocalFilePath -Blob "ServerList.xml" -Force
$success = $success -and $?
$null = Set-AzStorageBlobContent -Container $containerNameGateway -Context $sreStorageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_rds" "templates" "Set-RDPublishedName.ps1") -Blob "Set-RDPublishedName.ps1" -Force
$success = $success -and $?
if ($success) {
    Add-LogMessage -Level Success "File uploading succeeded"
} else {
    Add-LogMessage -Level Fatal "File uploading failed!"
}


# Add DNS records for RDS Gateway
# -------------------------------
$null = Set-AzContext -Subscription $config.sre.subscriptionName
Add-LogMessage -Level Info "Adding DNS record for RDS Gateway"

# Get public IP address of RDS gateway
$rdsGatewayVM = Get-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.gateway.vmName
$rdsGatewayPrimaryNicId = ($rdsGateWayVM.NetworkProfile.NetworkInterfaces | Where-Object { $_.Primary })[0].Id
$rdsRgPublicIps = (Get-AzPublicIpAddress -ResourceGroupName $config.sre.rds.rg)
$rdsGatewayPublicIp = ($rdsRgPublicIps | Where-Object { $_.IpConfiguration.Id -like "$rdsGatewayPrimaryNicId*" }).IpAddress

# Add DNS records to SRE DNS Zone
$null = Set-AzContext -SubscriptionId $config.shm.dns.subscriptionName
$baseDnsRecordname = "@"
$gatewayDnsRecordname = "$($config.sre.rds.gateway.hostname)".ToLower()
$dnsResourceGroup = $config.shm.dns.rg
$dnsTtlSeconds = 30
$sreDomain = $config.sre.domain.fqdn

# Set the A record
Add-LogMessage -Level Info "[ ] Setting 'A' record for gateway host to '$rdsGatewayPublicIp' in SRE $($config.sre.id) DNS zone ($sreDomain)"
Remove-AzDnsRecordSet -Name $baseDnsRecordname -RecordType A -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
$result = New-AzDnsRecordSet -Name $baseDnsRecordname -RecordType A -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Ipv4Address $rdsGatewayPublicIp)
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'A' record for gateway host"
} else {
    Add-LogMessage -Level Info "Failed to set 'A' record for gateway host!"
}

# Set the CNAME record
Add-LogMessage -Level Info "[ ] Setting CNAME record for gateway host to point to the 'A' record in SRE $($config.sre.id) DNS zone ($sreDomain)"
Remove-AzDnsRecordSet -Name $gatewayDnsRecordname -RecordType CNAME -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
$result = New-AzDnsRecordSet -Name $gatewayDnsRecordname -RecordType CNAME -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Cname $sreDomain)
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'CNAME' record for gateway host"
} else {
    Add-LogMessage -Level Info "Failed to set 'CNAME' record for gateway host!"
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Set locale, install updates and reboot
# --------------------------------------
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    Add-LogMessage -Level Info "Updating ${name}: '$vmName'..."
    Invoke-WindowsConfigureAndUpdate -VMName $vmName -ResourceGroupName $config.sre.rds.rg
}


# Import files to RDS VMs
# -----------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
Add-LogMessage -Level Info "Importing files from storage to RDS VMs..."

# Get list of packages for each session host
Add-LogMessage -Level Info "[ ] Getting list of packages for each VM"
$filePathsSh1 = New-Object System.Collections.ArrayList ($null)
$filePathsSh2 = New-Object System.Collections.ArrayList ($null)
foreach ($blob in Get-AzStorageBlob -Container $containerNameSessionHosts -Context $sreStorageAccount.Context) {
    if (($blob.Name -like "*GoogleChrome_x64.msi") -or ($blob.Name -like "*PuTTY_x64.msi")) {
        $null = $filePathsSh1.Add($blob.Name)
        $null = $filePathsSh2.Add($blob.Name)
    } elseif ($blob.Name -like "*LibreOffice_x64.msi") {
        $null = $filePathsSh2.Add($blob.Name)
    }
}
# ... and for the gateway
$filePathsGateway = New-Object System.Collections.ArrayList ($null)
foreach ($blob in Get-AzStorageBlob -Container $containerNameGateway -Context $sreStorageAccount.Context) {
    $null = $filePathsGateway.Add($blob.Name)
}
Add-LogMessage -Level Success "Found $($filePathsSh1.Count + $filePathsSh2.Count) packages in total"

# Get SAS token to download files from storage account
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$sasToken = New-ReadOnlyAccountSasToken -SubscriptionName $config.sre.subscriptionName -ResourceGroup $config.sre.storage.artifacts.rg -AccountName $sreStorageAccount.StorageAccountName
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Import_Artifacts.ps1"

# Copy software and/or scripts to RDS Gateway
Add-LogMessage -Level Info "[ ] Copying $($filePathsGateway.Count) files to RDS Gateway"
$params = @{
    storageAccountName           = "`"$($sreStorageAccount.StorageAccountName)`""
    storageService               = "blob"
    shareOrContainerName         = "`"$containerNameGateway`""
    sasToken                     = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$($filePathsGateway -join "|")`""
    downloadDir                  = "$remoteUploadDir"
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
Write-Output $result.Value

# Copy software and/or scripts to RDS SH1 (App server)
Add-LogMessage -Level Info "[ ] Copying $($filePathsSh1.Count) files to RDS Session Host (App server)"
$params = @{
    storageAccountName           = "`"$($sreStorageAccount.StorageAccountName)`""
    storageService               = "blob"
    shareOrContainerName         = "`"$containerNameSessionHosts`""
    sasToken                     = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$($filePathsSh1 -join "|")`""
    downloadDir                  = "$remoteUploadDir"
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.rds.sessionHost1.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
Write-Output $result.Value

# Copy software and/or scripts to RDS SH2 (Remote desktop server)
Add-LogMessage -Level Info "[ ] Copying $($filePathsSh2.Count) files to RDS Session Host (Remote desktop server)"
$params = @{
    storageAccountName           = "`"$($sreStorageAccount.StorageAccountName)`""
    storageService               = "blob"
    shareOrContainerName         = "`"$containerNameSessionHosts`""
    sasToken                     = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$($filePathsSh2 -join "|")`""
    downloadDir                  = "$remoteUploadDir"
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.rds.sessionHost2.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
Write-Output $result.Value
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Install packages on RDS VMs
# ---------------------------
Add-LogMessage -Level Info "Installing packages on RDS VMs..."
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    if ($name -ne "RDS Gateway") {
        Add-LogMessage -Level Info "[ ] Installing packages on ${name}: '$vmName'"
        $scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Install_Packages.ps1"
        $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.rds.rg
        Write-Output $result.Value
    }
}


# Install required Powershell modules on RDS Gateway
# --------------------------------------------------
Add-LogMessage -Level Info "[ ] Installing required Powershell modules on RDS Gateway..."
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Install_Additional_Powershell_Modules.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg
Write-Output $result.Value


# Add VMs to correct NSG
# ----------------------
Add-VmToNSG -VMName $config.sre.rds.gateway.vmName -VmResourceGroupName $config.sre.rds.rg -NSGName $config.sre.rds.gateway.nsg -NsgResourceGroupName $config.sre.network.vnet.rg
Add-VmToNSG -VMName $config.sre.rds.sessionHost1.vmName -VmResourceGroupName $config.sre.rds.rg -NSGName $config.sre.rds.sessionHost1.nsg -NsgResourceGroupName $config.sre.network.vnet.rg
Add-VmToNSG -VMName $config.sre.rds.sessionHost2.vmName -VmResourceGroupName $config.sre.rds.rg -NSGName $config.sre.rds.sessionHost2.nsg -NsgResourceGroupName $config.sre.network.vnet.rg


# Reboot all the RDS VMs
# ----------------------
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    Add-LogMessage -Level Info "Rebooting the ${name} VM: '$vmName'"
    Enable-AzVM -Name $vmName -ResourceGroupName $config.sre.rds.rg
    if ($?) {
        Add-LogMessage -Level Success "Rebooting the ${name} succeeded"
    } else {
        Add-LogMessage -Level Fatal "Rebooting the ${name} failed!"
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext;
