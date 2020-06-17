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
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Create VNet resource group if it does not exist
# -----------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.network.vnet.rg -Location $config.sre.location


# Create VNet and subnets
# -----------------------
$sreVnet = Deploy-VirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -AddressPrefix $config.sre.network.vnet.cidr -Location $config.sre.location -DnsServer $config.shm.dc.ip, $config.shm.dcb.ip
$null = Deploy-Subnet -Name $config.sre.network.subnets.data.name -VirtualNetwork $sreVnet -AddressPrefix $config.sre.network.subnets.data.cidr
$null = Deploy-Subnet -Name $config.sre.network.subnets.identity.name -VirtualNetwork $sreVnet -AddressPrefix $config.sre.network.subnets.identity.cidr
$null = Deploy-Subnet -Name $config.sre.network.subnets.rds.name -VirtualNetwork $sreVnet -AddressPrefix $config.sre.network.subnets.rds.cidr


# Remove existing SRE <-> SHM VNet peerings
# -----------------------------------------
$shmPeeringName = "PEER_$($config.sre.network.vnet.name)"
$srePeeringName = "PEER_$($config.shm.network.vnet.name)"
# From SHM VNet
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$shmVnet = Get-AzVirtualNetwork -Name $config.shm.network.vnet.name -ResourceGroupName $config.shm.network.vnet.rg
if (Get-AzVirtualNetworkPeering -VirtualNetworkName $config.shm.network.vnet.name -ResourceGroupName $config.shm.network.vnet.rg) {
    Add-LogMessage -Level Info "[ ] Removing existing peering '$shmPeeringName' from '$($config.sre.network.vnet.name)' to '$($config.shm.network.vnet.name)'..."
    Remove-AzVirtualNetworkPeering -Name $shmPeeringName -VirtualNetworkName $config.shm.network.vnet.name -ResourceGroupName $config.shm.network.vnet.rg -Force
    if ($?) {
        Add-LogMessage -Level Success "Peering removal succeeded"
    } else {
        Add-LogMessage -Level Fatal "Peering removal failed!"
    }
}
# From SRE VNet
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
if (Get-AzVirtualNetworkPeering -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg) {
    Add-LogMessage -Level Info "[ ] Removing existing peering '$srePeeringName' from '$($config.shm.network.vnet.name)' to '$($config.sre.network.vnet.name)'..."
    Remove-AzVirtualNetworkPeering -Name $srePeeringName -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -Force
    if ($?) {
        Add-LogMessage -Level Success "Peering removal succeeded"
    } else {
        Add-LogMessage -Level Fatal "Peering removal failed!"
    }
}

# Add SRE <-> SHM VNet peerings
# -----------------------------
# To SHM VNet
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
Add-LogMessage -Level Info "[ ] Adding peering '$shmPeeringName' from '$($config.sre.network.vnet.name)' to '$($config.shm.network.vnet.name)'..."
$_ = Add-AzVirtualNetworkPeering -Name $shmPeeringName -VirtualNetwork $shmVnet -RemoteVirtualNetworkId $sreVnet.Id -AllowGatewayTransit
if ($?) {
    Add-LogMessage -Level Success "Peering '$($config.sre.network.vnet.name)' to '$($config.shm.network.vnet.name)' succeeded"
} else {
    Add-LogMessage -Level Fatal "Peering '$($config.sre.network.vnet.name)' to '$($config.shm.network.vnet.name)' failed!"
}
# To SRE VNet
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
Add-LogMessage -Level Info "[ ] Adding peering '$srePeeringName' from '$($config.shm.network.vnet.name)' to '$($config.sre.network.vnet.name)'..."
$_ = Add-AzVirtualNetworkPeering -Name $srePeeringName -VirtualNetwork $sreVnet -RemoteVirtualNetworkId $shmVnet.Id -UseRemoteGateways
if ($?) {
    Add-LogMessage -Level Success "Peering '$($config.shm.network.vnet.name)' to '$($config.sre.network.vnet.name)' succeeded"
} else {
    Add-LogMessage -Level Fatal "Peering '$($config.shm.network.vnet.name)' to '$($config.sre.network.vnet.name)' failed!"
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
# $dataSubnetIpPrefix = $config.sre.network.subnets.data.prefix
$dsvmInitialIpAddress = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.subnets.data.cidr -Offset 160
$gitlabIpAddress = $config.sre.webapps.gitlab.ip
$hackmdIpAddress = $config.sre.webapps.hackmd.ip
$npsSecret = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.npsSecret -DefaultLength 12
$rdsGatewayVmFqdn = $config.sre.rds.gateway.fqdn
$rdsGatewayVmName = $config.sre.rds.gateway.vmName
$rdsSh1VmFqdn = $config.sre.rds.sessionHost1.fqdn
$rdsSh1VmName = $config.sre.rds.sessionHost1.vmName
$rdsSh2VmFqdn = $config.sre.rds.sessionHost2.fqdn
$rdsSh2VmName = $config.sre.rds.sessionHost2.vmName
$shmDcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.domainAdminPassword -DefaultLength 20
$shmDcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.shm.id)admin".ToLower()
$shmNetbiosName = $config.shm.domain.netbiosName
$sreAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.rdsAdminPassword -DefaultLength 20
$sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$sreFqdn = $config.sre.domain.fqdn
$sreNetbiosName = $config.sre.domain.netbiosName


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
    SRE_ID = $config.sre.Id
    Virtual_Network_Name = $config.sre.network.vnet.name
    Virtual_Network_Resource_Group = $config.sre.network.vnet.rg
    Virtual_Network_Subnet = $config.sre.network.subnets.rds.name
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-rds-template.json") -Params $params -ResourceGroupName $config.sre.rds.rg


# Create blob containers in SRE storage account
# ---------------------------------------------
Add-LogMessage -Level Info "Creating blob storage containers in storage account '$($sreStorageAccount.StorageAccountName)'..."
foreach ($containerName in ($containerNameGateway, $containerNameSessionHosts)) {
    $_ = Deploy-StorageContainer -Name $containerName -StorageAccount $sreStorageAccount
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
$template = Get-Content (Join-Path $PSScriptRoot ".." "remote" "create_rds" "templates" "Deploy_RDS_Environment.template.ps1") -Raw
$ExecutionContext.InvokeCommand.ExpandString($template) | Out-File $deployScriptLocalFilePath

# Expand server list XML
$serverListLocalFilePath = (New-TemporaryFile).FullName
$template = Get-Content (Join-Path $PSScriptRoot ".." "remote" "create_rds" "templates" "ServerList.template.xml") -Raw
$ExecutionContext.InvokeCommand.ExpandString($template) | Out-File $serverListLocalFilePath

# Copy existing files
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
Set-AzStorageBlobContent -Container $containerNameGateway -Context $sreStorageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_rds" "templates" "Set-RDPublishedName.ps1") -Blob "Set-RDPublishedName.ps1" -Force
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
$sreDomain = $config.sre.domain.fqdn

# Set the A record
Add-LogMessage -Level Info "[ ] Setting 'A' record for gateway host to '$rdsGatewayPublicIp' in SRE $($config.sre.id) DNS zone ($sreDomain)"
Remove-AzDnsRecordSet -Name $baseDnsRecordname -RecordType A -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
$result = New-AzDnsRecordSet -Name $baseDnsRecordname -RecordType A -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup `
                             -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -IPv4Address $rdsGatewayPublicIp)
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'A' record for gateway host"
} else {
    Add-LogMessage -Level Info "Failed to set 'A' record for gateway host!"
}

# Set the CNAME record
Add-LogMessage -Level Info "[ ] Setting CNAME record for gateway host to point to the 'A' record in SRE $($config.sre.id) DNS zone ($sreDomain)"
Remove-AzDnsRecordSet -Name $gatewayDnsRecordname -RecordType CNAME -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
$result = New-AzDnsRecordSet -Name $gatewayDnsRecordname -RecordType CNAME -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup `
                             -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Cname $sreDomain)
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
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName

# Get list of packages for each session host
Add-LogMessage -Level Info "[ ] Getting list of packages for each VM"
$filePathsSh1 = New-Object System.Collections.ArrayList ($null)
$filePathsSh2 = New-Object System.Collections.ArrayList ($null)
foreach ($blob in Get-AzStorageBlob -Container $containerNameSessionHosts -Context $sreStorageAccount.Context) {
    if (($blob.Name -like "*GoogleChrome_x64.msi") -or ($blob.Name -like "*PuTTY_x64.msi")) {
        $_ = $filePathsSh1.Add($blob.Name)
        $_ = $filePathsSh2.Add($blob.Name)
    } elseif ($blob.Name -like "*LibreOffice_x64.msi") {
        $_ = $filePathsSh2.Add($blob.Name)
    }
}
# ... and for the gateway
$filePathsGateway = New-Object System.Collections.ArrayList ($null)
foreach ($blob in Get-AzStorageBlob -Container $containerNameGateway -Context $sreStorageAccount.Context) {
    $_ = $filePathsGateway.Add($blob.Name)
}
Add-LogMessage -Level Success "Found $($filePathsSh1.Count + $filePathsSh2.Count) packages in total"

# Get SAS token to download files from storage account
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$sasToken = New-ReadOnlyAccountSasToken -SubscriptionName $config.sre.subscriptionName -ResourceGroup $config.sre.storage.artifacts.rg -AccountName $sreStorageAccount.StorageAccountName
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Import_Artifacts.ps1"

# Copy software and/or scripts to RDS Gateway
Add-LogMessage -Level Info "[ ] Copying $($filePathsGateway.Count) files to RDS Gateway"
$params = @{
    storageAccountName = "`"$($sreStorageAccount.StorageAccountName)`""
    storageService = "blob"
    shareOrContainerName = "`"$containerNameGateway`""
    sasToken = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$($filePathsGateway -join "|")`""
    downloadDir = "$remoteUploadDir"
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
Write-Output $result.Value

# Copy software and/or scripts to RDS SH1 (App server)
Add-LogMessage -Level Info "[ ] Copying $($filePathsSh1.Count) files to RDS Session Host (App server)"
$params = @{
    storageAccountName = "`"$($sreStorageAccount.StorageAccountName)`""
    storageService = "blob"
    shareOrContainerName = "`"$containerNameSessionHosts`""
    sasToken = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$($filePathsSh1 -join "|")`""
    downloadDir = "$remoteUploadDir"
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.rds.sessionHost1.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
Write-Output $result.Value

# Copy software and/or scripts to RDS SH2 (Remote desktop server)
Add-LogMessage -Level Info "[ ] Copying $($filePathsSh2.Count) files to RDS Session Host (Remote desktop server)"
$params = @{
    storageAccountName = "`"$($sreStorageAccount.StorageAccountName)`""
    storageService = "blob"
    shareOrContainerName = "`"$containerNameSessionHosts`""
    sasToken = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$($filePathsSh2 -join "|")`""
    downloadDir = "$remoteUploadDir"
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.rds.sessionHost2.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
Write-Output $result.Value


# Install packages on RDS VMs
# ---------------------------
Add-LogMessage -Level Info "Installing packages on RDS VMs..."
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
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
Add-VmToNSG -VMName $config.sre.rds.gateway.vmName -NSGName $config.sre.rds.gateway.nsg
Add-VmToNSG -VMName $config.sre.rds.sessionHost1.vmName -NSGName $config.sre.rds.sessionHost1.nsg
Add-VmToNSG -VMName $config.sre.rds.sessionHost2.vmName -NSGName $config.sre.rds.sessionHost2.nsg


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
$_ = Set-AzContext -Context $originalContext;
