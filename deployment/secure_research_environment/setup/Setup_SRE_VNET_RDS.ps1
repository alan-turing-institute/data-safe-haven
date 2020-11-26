param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Set constants used in this script
# ---------------------------------
$remoteUploadDir = "C:\Installation"
$containerNameGateway = "sre-rds-gateway-scripts"
$containerNameSessionHosts = "sre-rds-sh-packages"
$vmNamePairs = @(("RDS Gateway", $config.sre.rds.gateway.vmName),
                 ("RDS Session Host (App server)", $config.sre.rds.appSessionHost.vmName))


# Retrieve variables from SHM key vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.shm.keyVault.name)'..."
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$domainAdminUsername = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.domainAdminUsername -AsPlaintext
$domainJoinGatewayPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.users.computerManagers.rdsGatewayServers.passwordSecretName -DefaultLength 20 -AsPlaintext
$domainJoinSessionHostPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.users.computerManagers.rdsSessionServers.passwordSecretName -DefaultLength 20 -AsPlaintext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Retrieve variables from SRE key vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$dsvmInitialIpAddress = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.compute.cidr -Offset 160
$rdsGatewayAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.rds.gateway.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
$rdsAppSessionHostAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.rds.appSessionHost.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
$sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower() -AsPlaintext


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
    RDS_Session_Host_Apps_Admin_Password     = (ConvertTo-SecureString $rdsAppSessionHostAdminPassword -AsPlainText -Force)
    RDS_Session_Host_Apps_IP_Address         = $config.sre.rds.appSessionHost.ip
    RDS_Session_Host_Apps_Name               = $config.sre.rds.appSessionHost.vmName
    RDS_Session_Host_Apps_Os_Disk_Size_GB    = [int]$config.sre.rds.appSessionHost.disks.os.sizeGb
    RDS_Session_Host_Apps_Os_Disk_Type       = $config.sre.rds.appSessionHost.disks.os.type
    RDS_Session_Host_Apps_VM_Size            = $config.sre.rds.appSessionHost.vmSize
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
          Replace("<rdsGatewayVmFqdn>", $config.sre.rds.gateway.fqdn).
          Replace("<rdsGatewayVmName>", $config.sre.rds.gateway.vmName).
          Replace("<rdsAppSessionHostFqdn>", $config.sre.rds.appSessionHost.fqdn).
          Replace("<remoteUploadDir>", $remoteUploadDir).
          Replace("<researchUserSgName>", $config.sre.domain.securityGroups.researchUsers.name).
          Replace("<shmNetbiosName>", $config.shm.domain.netbiosName).
          Replace("<sreDomain>", $config.sre.domain.fqdn) | Out-File $deployScriptLocalFilePath

# Expand server list XML
$serverListLocalFilePath = (New-TemporaryFile).FullName
$template = Join-Path $PSScriptRoot ".." "remote" "create_rds" "templates" "ServerList.template.xml" | Get-Item | Get-Content -Raw
$template.Replace("<rdsGatewayVmFqdn>", $config.sre.rds.gateway.fqdn).
          Replace("<rdsAppSessionHostFqdn>", $config.sre.rds.appSessionHost.fqdn) | Out-File $serverListLocalFilePath

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
$dnsTtlSeconds = 30

# Set the A record
$recordName = "@"
Add-LogMessage -Level Info "[ ] Setting 'A' record for gateway host to '$rdsGatewayPublicIp' in SRE $($config.sre.id) DNS zone ($($config.sre.domain.fqdn))"
Remove-AzDnsRecordSet -Name $recordName -RecordType A -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
$result = New-AzDnsRecordSet -Name $recordName -RecordType A -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Ipv4Address $rdsGatewayPublicIp)
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'A' record for gateway host"
} else {
    Add-LogMessage -Level Info "Failed to set 'A' record for gateway host!"
}

# Set the CNAME record
$recordName = "$($config.sre.rds.gateway.hostname)".ToLower()
Add-LogMessage -Level Info "[ ] Setting CNAME record for gateway host to point to the 'A' record in SRE $($config.sre.id) DNS zone ($($config.sre.domain.fqdn))"
Remove-AzDnsRecordSet -Name $recordName -RecordType CNAME -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
$result = New-AzDnsRecordSet -Name $recordName -RecordType CNAME -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Cname $config.sre.domain.fqdn)
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
    Invoke-WindowsConfigureAndUpdate -VMName $vmName -ResourceGroupName $config.sre.rds.rg -TimeZone $config.sre.time.timezone.windows -NtpServer $config.shm.time.ntp.poolFqdn
}


# Import files to RDS VMs
# -----------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
Add-LogMessage -Level Info "Importing files from storage to RDS VMs..."
# Set correct list of packages from blob storage for each session host
$blobfiles = @{}
$vmNamePairs | ForEach-Object { $blobfiles[$_[1]] = @() }
foreach ($blob in Get-AzStorageBlob -Container $containerNameSessionHosts -Context $sreStorageAccount.Context) {
    if (($blob.Name -like "*GoogleChrome_x64.msi") -or ($blob.Name -like "*PuTTY_x64.msi")) {
        $blobfiles[$config.sre.rds.appSessionHost.vmName] += @{$containerNameSessionHosts = $blob.Name}
    }
}
# ... and for the gateway
foreach ($blob in Get-AzStorageBlob -Container $containerNameGateway -Context $sreStorageAccount.Context) {
    $blobfiles[$config.sre.rds.gateway.vmName] += @{$containerNameGateway = $blob.Name}
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName

# Copy software and/or scripts to RDS VMs
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Import_And_Install_Blobs.ps1"
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    $containerName = $blobfiles[$vmName] | ForEach-Object { $_.Keys } | Select-Object -First 1
    $fileNames = $blobfiles[$vmName] | ForEach-Object { $_.Values }
    $sasToken = New-ReadOnlyStorageAccountSasToken -SubscriptionName $config.sre.subscriptionName -ResourceGroup $config.sre.storage.artifacts.rg -AccountName $sreStorageAccount.StorageAccountName
    Add-LogMessage -Level Info "[ ] Copying $($fileNames.Count) files to $name"
    $params = @{
        storageAccountName = "`"$($sreStorageAccount.StorageAccountName)`""
        storageService = "blob"
        shareOrContainerName = "`"$containerName`""
        sasToken = "`"$sasToken`""
        pipeSeparatedRemoteFilePaths = "`"$($fileNames -join "|")`""
        downloadDir = "$remoteUploadDir"
    }
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
}

# Set locale, install updates and reboot
# --------------------------------------
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    Add-LogMessage -Level Info "Updating ${name}: '$vmName'..."
    $params = @{}
    # The RDS Gateway needs the RDWebClientManagement Powershell module
    if ($name -eq "RDS Gateway") { $params["AdditionalPowershellModules"] = @("RDWebClientManagement") }
    Invoke-WindowsConfigureAndUpdate -VMName $vmName -ResourceGroupName $config.sre.rds.rg -TimeZone $config.sre.time.timezone.windows -NtpServer $config.shm.time.ntp.poolFqdn @params
}


# Add VMs to correct NSG
# ----------------------
Add-VmToNSG -VMName $config.sre.rds.gateway.vmName -VmResourceGroupName $config.sre.rds.rg -NSGName $config.sre.rds.gateway.nsg -NsgResourceGroupName $config.sre.network.vnet.rg
Add-VmToNSG -VMName $config.sre.rds.appSessionHost.vmName -VmResourceGroupName $config.sre.rds.rg -NSGName $config.sre.rds.appSessionHost.nsg -NsgResourceGroupName $config.sre.network.vnet.rg


# Reboot all the RDS VMs
# ----------------------
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    Enable-AzVM -Name $vmName -ResourceGroupName $config.sre.rds.rg
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext;
