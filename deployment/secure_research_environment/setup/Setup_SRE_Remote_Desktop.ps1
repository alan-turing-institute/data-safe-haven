param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
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
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Check that we are using the correct provider
# --------------------------------------------
if ($config.sre.remoteDesktop.provider -ne "MicrosoftRDS") {
    Add-LogMessage -Level Fatal "You should not be running this script when using remote desktop provider '$($config.sre.remoteDesktop.provider)'"
}


# Set constants used in this script
# ---------------------------------
$containerNameGateway = "sre-rds-gateway-scripts"
$containerNameSessionHosts = "sre-rds-sh-packages"
$vmNamePairs = @(("RDS Gateway", $config.sre.remoteDesktop.gateway.vmName),
                 ("RDS Session Host (App server)", $config.sre.remoteDesktop.appSessionHost.vmName))


# Retrieve variables from SHM Key Vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.shm.keyVault.name)'..."
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
$domainAdminUsername = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.domainAdminUsername -AsPlaintext
$domainJoinGatewayPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.users.computerManagers.rdsGatewayServers.passwordSecretName -DefaultLength 20 -AsPlaintext
$domainJoinSessionHostPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.users.computerManagers.rdsSessionServers.passwordSecretName -DefaultLength 20 -AsPlaintext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Retrieve variables from SRE Key Vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.sre.keyVault.name)'..."
$dsvmInitialIpAddress = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.compute.cidr -Offset 160
$rdsGatewayAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.remoteDesktop.gateway.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
$rdsAppSessionHostAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.remoteDesktop.appSessionHost.adminPasswordSecretName -DefaultLength 20 -AsPlaintext
$sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower() -AsPlaintext


# Ensure that boot diagnostics resource group and storage account exist
# ---------------------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$null = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location


# Ensure that SRE resource group and storage accounts exist
# ---------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.storage.artifacts.rg -Location $config.sre.location
$sreStorageAccount = Get-StorageAccount -Name $config.sre.storage.artifacts.account.name -ResourceGroupName $config.sre.storage.artifacts.rg -SubscriptionName $config.sre.subscriptionName -ErrorAction Stop

# Get SHM storage account
# -----------------------
$null = Set-AzContext -Subscription $config.shm.subscriptionName -ErrorAction Stop
$shmStorageAccount = Deploy-StorageAccount -Name $config.shm.storage.artifacts.accountName -ResourceGroupName $config.shm.storage.artifacts.rg -Location $config.shm.location
$null = Set-AzContext -Subscription $config.sre.subscriptionName -ErrorAction Stop


# Create RDS resource group if it does not exist
# ----------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.remoteDesktop.rg -Location $config.sre.location


# Deploy RDS from template
# ------------------------
Add-LogMessage -Level Info "Deploying RDS from template..."
$params = @{
    Administrator_User                    = $sreAdminUsername
    BootDiagnostics_Account_Name          = $config.sre.storage.bootdiagnostics.accountName
    Domain_Join_Password_Gateway          = (ConvertTo-SecureString $domainJoinGatewayPassword -AsPlainText -Force)
    Domain_Join_Password_Session_Hosts    = (ConvertTo-SecureString $domainJoinSessionHostPassword -AsPlainText -Force)
    Domain_Join_User_Gateway              = $config.shm.users.computerManagers.rdsGatewayServers.samAccountName
    Domain_Join_User_Session_Hosts        = $config.shm.users.computerManagers.rdsSessionServers.samAccountName
    Domain_Name                           = $config.shm.domain.fqdn
    OU_Path_Gateway                       = $config.shm.domain.ous.rdsGatewayServers.path
    OU_Path_Session_Hosts                 = $config.shm.domain.ous.rdsSessionServers.path
    RDS_Gateway_Admin_Password            = (ConvertTo-SecureString $rdsGatewayAdminPassword -AsPlainText -Force)
    RDS_Gateway_Data_Disk_Size_GB         = [int]$config.sre.remoteDesktop.gateway.disks.data.sizeGb
    RDS_Gateway_Data_Disk_Type            = $config.sre.remoteDesktop.gateway.disks.data.type
    RDS_Gateway_IP_Address                = $config.sre.remoteDesktop.gateway.ip
    RDS_Gateway_Name                      = $config.sre.remoteDesktop.gateway.vmName
    RDS_Gateway_NSG_Name                  = $config.sre.remoteDesktop.gateway.nsg.name
    RDS_Gateway_Os_Disk_Size_GB           = [int]$config.sre.remoteDesktop.gateway.disks.os.sizeGb
    RDS_Gateway_Os_Disk_Type              = $config.sre.remoteDesktop.gateway.disks.os.type
    RDS_Gateway_Subnet_Name               = $config.sre.network.vnet.subnets.remoteDesktop.name
    RDS_Gateway_VM_Size                   = $config.sre.remoteDesktop.gateway.vmSize
    RDS_Session_Host_Apps_Admin_Password  = (ConvertTo-SecureString $rdsAppSessionHostAdminPassword -AsPlainText -Force)
    RDS_Session_Host_Apps_IP_Address      = $config.sre.remoteDesktop.appSessionHost.ip
    RDS_Session_Host_Apps_Name            = $config.sre.remoteDesktop.appSessionHost.vmName
    RDS_Session_Host_Apps_Os_Disk_Size_GB = [int]$config.sre.remoteDesktop.appSessionHost.disks.os.sizeGb
    RDS_Session_Host_Apps_Os_Disk_Type    = $config.sre.remoteDesktop.appSessionHost.disks.os.type
    RDS_Session_Host_Apps_VM_Size         = $config.sre.remoteDesktop.appSessionHost.vmSize
    RDS_Session_Host_Subnet_Name          = $config.sre.network.vnet.subnets.remoteDesktop.name
    SRE_ID                                = $config.sre.id
    Virtual_Network_Name                  = $config.sre.network.vnet.name
    Virtual_Network_Resource_Group        = $config.sre.network.vnet.rg
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-rds-template.json") -Params $params -ResourceGroupName $config.sre.remoteDesktop.rg


# Create blob containers in SRE storage account
# ---------------------------------------------
Add-LogMessage -Level Info "Creating blob storage containers in storage account '$($sreStorageAccount.StorageAccountName)'..."
foreach ($containerName in ($containerNameGateway, $containerNameSessionHosts)) {
    $null = Deploy-StorageContainer -Name $containerName -StorageAccount $sreStorageAccount
    $blobs = @(Get-AzStorageBlob -Container $containerName -Context $sreStorageAccount.Context)
    $numBlobs = $blobs.Length
    if ($numBlobs -gt 0) {
        Add-LogMessage -Level Info "[ ] Deleting $numBlobs blobs aready in container '$containerName'..."
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
          Replace("<cocalcIpAddress>", $config.sre.webapps.cocalc.ip).
          Replace("<codimdIpAddress>", $config.sre.webapps.codimd.ip).
          Replace("<gitlabIpAddress>", $config.sre.webapps.gitlab.ip).
          Replace("<rdsGatewayVmFqdn>", $config.sre.remoteDesktop.gateway.fqdn).
          Replace("<rdsGatewayVmName>", $config.sre.remoteDesktop.gateway.vmName).
          Replace("<rdsAppSessionHostFqdn>", $config.sre.remoteDesktop.appSessionHost.fqdn).
          Replace("<remoteUploadDir>", $config.sre.remoteDesktop.gateway.installationDirectory).
          Replace("<researchUserSgName>", $config.sre.domain.securityGroups.researchUsers.name).
          Replace("<shmNetbiosName>", $config.shm.domain.netbiosName).
          Replace("<sreDomain>", $config.sre.domain.fqdn) | Out-File $deployScriptLocalFilePath

# Expand server list XML
$serverListLocalFilePath = (New-TemporaryFile).FullName
$template = Join-Path $PSScriptRoot ".." "remote" "create_rds" "templates" "ServerList.template.xml" | Get-Item | Get-Content -Raw
$template.Replace("<rdsGatewayVmFqdn>", $config.sre.remoteDesktop.gateway.fqdn).
          Replace("<rdsAppSessionHostFqdn>", $config.sre.remoteDesktop.appSessionHost.fqdn) | Out-File $serverListLocalFilePath

# Copy installers from SHM storage
try {
    Add-LogMessage -Level Info "[ ] Copying RDS installers to storage account '$($sreStorageAccount.StorageAccountName)'"
    $blobs = Get-AzStorageBlob -Context $shmStorageAccount.Context -Container $containerNameSessionHosts -ErrorAction Stop
    $null = $blobs | Start-AzStorageBlobCopy -Context $shmStorageAccount.Context -DestContext $sreStorageAccount.Context -DestContainer $containerNameSessionHosts -Force -ErrorAction Stop
    Add-LogMessage -Level Success "File copying succeeded"
} catch {
    Add-LogMessage -Level Fatal "File copying failed!" -Exception $_.Exception
}

# Upload scripts
try {
    Add-LogMessage -Level Info "[ ] Uploading RDS gateway scripts to storage account '$($sreStorageAccount.StorageAccountName)'"
    $null = Set-AzStorageBlobContent -Container $containerNameGateway -Context $sreStorageAccount.Context -File $deployScriptLocalFilePath -Blob "Deploy_RDS_Environment.ps1" -Force -ErrorAction Stop
    $null = Set-AzStorageBlobContent -Container $containerNameGateway -Context $sreStorageAccount.Context -File $serverListLocalFilePath -Blob "ServerList.xml" -Force -ErrorAction Stop
    Add-LogMessage -Level Success "File uploading succeeded"
} catch {
    Add-LogMessage -Level Fatal "File uploading failed!" -Exception $_.Exception
}


# Get public IP address of RDS gateway
# ------------------------------------
$rdsGatewayVM = Get-AzVM -ResourceGroupName $config.sre.remoteDesktop.rg -Name $config.sre.remoteDesktop.gateway.vmName
$rdsGatewayPrimaryNicId = ($rdsGateWayVM.NetworkProfile.NetworkInterfaces | Where-Object { $_.Primary })[0].Id
$rdsRgPublicIps = (Get-AzPublicIpAddress -ResourceGroupName $config.sre.remoteDesktop.rg)
$rdsGatewayPublicIp = ($rdsRgPublicIps | Where-Object { $_.IpConfiguration.Id -like "$rdsGatewayPrimaryNicId*" }).IpAddress


# Add DNS records for RDS Gateway
# -------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.dns.subscriptionName -ErrorAction Stop
# Add DNS records to SRE DNS Zone
Add-LogMessage -Level Info "Adding DNS record for RDS Gateway"
$dnsTtlSeconds = 30
# Set the A record for the SRE FQDN
$recordName = "@"
Add-LogMessage -Level Info "[ ] Setting 'A' record for gateway host to '$rdsGatewayPublicIp' in SRE $($config.sre.id) DNS zone ($($config.sre.domain.fqdn))"
Remove-AzDnsRecordSet -Name $recordName -RecordType A -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
$null = New-AzDnsRecordSet -Name $recordName -RecordType A -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Ipv4Address $rdsGatewayPublicIp)
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'A' record for gateway host"
} else {
    Add-LogMessage -Level Fatal "Failed to set 'A' record for gateway host!"
}
# Set the CNAME record for the remote desktop server
$serverHostname = "$($config.sre.remoteDesktop.gateway.hostname)".ToLower()
Add-LogMessage -Level Info "[ ] Setting CNAME record for gateway host to point to the 'A' record in SRE $($config.sre.id) DNS zone ($($config.sre.domain.fqdn))"
Remove-AzDnsRecordSet -Name $serverHostname -RecordType CNAME -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
$null = New-AzDnsRecordSet -Name $serverHostname -RecordType CNAME -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Cname $config.sre.domain.fqdn)
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'CNAME' record for gateway host"
} else {
    Add-LogMessage -Level Fatal "Failed to set 'CNAME' record for gateway host!"
}
# Set the CAA record for the SRE FQDN
Add-LogMessage -Level Info "[ ] Setting CAA record for $($config.sre.domain.fqdn) to state that certificates will be provided by Let's Encrypt"
Remove-AzDnsRecordSet -Name "CAA" -RecordType CAA -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
$null = New-AzDnsRecordSet -Name "CAA" -RecordType CAA -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg -Ttl $dnsTtl -DnsRecords (New-AzDnsRecordConfig -CaaFlags 0 -CaaTag "issue" -CaaValue "letsencrypt.org")
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'CAA' record for $($config.sre.domain.fqdn)"
} else {
    Add-LogMessage -Level Fatal "Failed to set 'CAA' record for $($config.sre.domain.fqdn)!"
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Import files to RDS VMs
# -----------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
Add-LogMessage -Level Info "Importing files from storage to RDS VMs..."
# Set correct list of packages from blob storage for each session host
$blobfiles = @{}
$vmNamePairs | ForEach-Object { $blobfiles[$_[1]] = @() }
foreach ($blob in Get-AzStorageBlob -Container $containerNameSessionHosts -Context $sreStorageAccount.Context) {
    if (($blob.Name -like "*GoogleChrome_x64.msi") -or ($blob.Name -like "*PuTTY_x64.msi")) {
        $blobfiles[$config.sre.remoteDesktop.appSessionHost.vmName] += @{$containerNameSessionHosts = $blob.Name }
    }
}
# ... and for the gateway
foreach ($blob in Get-AzStorageBlob -Container $containerNameGateway -Context $sreStorageAccount.Context) {
    $blobfiles[$config.sre.remoteDesktop.gateway.vmName] += @{$containerNameGateway = $blob.Name }
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop

# Copy software and/or scripts to RDS VMs
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Import_And_Install_Blobs.ps1"
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    $containerName = $blobfiles[$vmName] | ForEach-Object { $_.Keys } | Select-Object -First 1
    $fileNames = $blobfiles[$vmName] | ForEach-Object { $_.Values }
    $sasToken = New-ReadOnlyStorageAccountSasToken -SubscriptionName $config.sre.subscriptionName -ResourceGroup $config.sre.storage.artifacts.rg -AccountName $sreStorageAccount.StorageAccountName
    Add-LogMessage -Level Info "[ ] Copying $($fileNames.Count) files to $name"
    $params = @{
        blobNameArrayB64     = $fileNames | ConvertTo-Json | ConvertTo-Base64
        downloadDir          = $config.sre.remoteDesktop.gateway.installationDirectory
        sasTokenB64          = $sasToken | ConvertTo-Base64
        shareOrContainerName = $containerName
        storageAccountName   = $sreStorageAccount.StorageAccountName
        storageService       = "blob"
    }
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.remoteDesktop.rg -Parameter $params
}

# Set locale, install updates and reboot
# --------------------------------------
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    Add-LogMessage -Level Info "Updating ${name}: '$vmName'..."
    $params = @{}
    # The RDS Gateway needs the RDWebClientManagement Powershell module
    if ($name -eq "RDS Gateway") { $params["AdditionalPowershellModules"] = @("RDWebClientManagement") }
    Invoke-WindowsConfigureAndUpdate -VMName $vmName -ResourceGroupName $config.sre.remoteDesktop.rg -TimeZone $config.sre.time.timezone.windows -NtpServer $config.shm.time.ntp.poolFqdn @params
}


# Add VMs to correct NSG
# ----------------------
Add-VmToNSG -VMName $config.sre.remoteDesktop.gateway.vmName -VmResourceGroupName $config.sre.remoteDesktop.rg -NSGName $config.sre.remoteDesktop.gateway.nsg.name -NsgResourceGroupName $config.sre.network.vnet.rg
Add-VmToNSG -VMName $config.sre.remoteDesktop.appSessionHost.vmName -VmResourceGroupName $config.sre.remoteDesktop.rg -NSGName $config.sre.remoteDesktop.appSessionHost.nsg.name -NsgResourceGroupName $config.sre.network.vnet.rg


# Reboot all the RDS VMs
# ----------------------
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $null, $vmName = $nameVMNameParamsPair
    Start-VM -Name $vmName -ResourceGroupName $config.sre.remoteDesktop.rg -ForceRestart
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
