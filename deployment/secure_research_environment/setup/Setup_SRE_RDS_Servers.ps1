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
$dataSubnetIpPrefix = $config.sre.network.subnets.data.prefix
$shmDcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.dcNpsAdminUsername -DefaultValue "shm$($config.shm.id)admin".ToLower()
$shmDcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.dcNpsAdminPassword
$sreAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dcAdminPassword
$sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dcAdminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$npsSecret = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.rds.gateway.npsSecretName -DefaultLength 12
$rdsGatewayVmFqdn = $config.sre.rds.gateway.fqdn
$rdsGatewayVmName = $config.sre.rds.gateway.vmName
$rdsSh1VmFqdn = $config.sre.rds.sessionHost1.fqdn
$rdsSh1VmName = $config.sre.rds.sessionHost1.vmName
$rdsSh2VmFqdn = $config.sre.rds.sessionHost2.fqdn
$rdsSh2VmName = $config.sre.rds.sessionHost2.vmName
$shmNetbiosName = $config.shm.domain.netbiosName
$sreFqdn = $config.sre.domain.fqdn
$shmNetbiosName = $config.shm.domain.netbiosName


# Get SHM storage account
# -----------------------
$_ = Set-AzContext -Subscription $config.shm.subscriptionName;
$shmStorageAccountRg = $config.shm.storage.artifacts.rg
$shmStorageAccountName = $config.shm.storage.artifacts.accountName
$shmStorageAccount = Get-AzStorageAccount -Name $shmStorageAccountName -ResourceGroupName $shmStorageAccountRg


# Get SRE storage account
# -----------------------
$_ = Set-AzContext -Subscription $config.sre.subscriptionName;
$sreStorageAccountRg = $config.sre.storage.artifacts.rg
$sreStorageAccountName = $config.sre.storage.artifacts.accountName
$sreStorageAccount = Get-AzStorageAccount -Name $sreStorageAccountName -ResourceGroupName $sreStorageAccountRg


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
    Virtual_Network_Name = $config.sre.network.vnet.Name
    Virtual_Network_Resource_Group = $config.sre.network.vnet.rg
    Virtual_Network_Subnet = $config.sre.network.subnets.rds.Name
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-rds-template.json") -Params $params -ResourceGroupName $config.sre.rds.rg


# Create blob containers in SRE storage account
# ---------------------------------------------
Add-LogMessage -Level Info "Creating blob storage containers in storage account '$sreStorageAccountName'..."
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
Add-LogMessage -Level Info "[ ] Copying RDS installers to storage account '$sreStorageAccountName'"
$blobs = Get-AzStorageBlob -Context $shmStorageAccount.Context -Container $containerNameSessionHosts
$blobs | Start-AzStorageBlobCopy -Context $shmStorageAccount.Context -DestContext $sreStorageAccount.Context -DestContainer $containerNameSessionHosts -Force
if ($?) {
    Add-LogMessage -Level Success "File copying succeeded"
} else {
    Add-LogMessage -Level Fatal "File copying failed!"
}

# Upload scripts
Add-LogMessage -Level Info "[ ] Uploading RDS gateway scripts to storage account '$sreStorageAccountName'"
Set-AzStorageBlobContent -Container $containerNameGateway -Context $sreStorageAccount.Context -File $deployScriptLocalFilePath -Blob "Deploy_RDS_Environment.ps1" -Force
Set-AzStorageBlobContent -Container $containerNameGateway -Context $sreStorageAccount.Context -File $serverListLocalFilePath -Blob "ServerList.xml" -Force
Set-AzStorageBlobContent -Container $containerNameGateway -Context $sreStorageAccount.Context -File (Join-Path $PSScriptRoot ".." "remote" "create_rds" "templates" "Set-RDPublishedName.ps1") -Blob "Set-RDPublishedName.ps1" -Force
if ($?) {
    Add-LogMessage -Level Success "File uploading succeeded"
} else {
    Add-LogMessage -Level Fatal "File uploading failed!"
}


# Add DNS record for RDS Gateway
# ------------------------------
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

# Setting the A record
Add-LogMessage -Level Info "[ ] Setting 'A' record for gateway host to '$rdsGatewayPublicIp' in SRE $($config.sre.id) DNS zone ($sreDomain)"
Remove-AzDnsRecordSet -Name $baseDnsRecordname -RecordType A -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
$result = New-AzDnsRecordSet -Name $baseDnsRecordname -RecordType A -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup `
                             -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -IPv4Address $rdsGatewayPublicIp)
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'A' record for gateway host"
} else {
    Add-LogMessage -Level Info "Failed to set 'A' record for gateway host!"
}

# Setting the CNAME record
Add-LogMessage -Level Info "[ ] Setting CNAME record for gateway host to point to the 'A' record in SRE $($config.sre.id) DNS zone ($sreDomain)"
Remove-AzDnsRecordSet -Name $gatewayDnsRecordname -RecordType CNAME -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
$result = New-AzDnsRecordSet -Name $gatewayDnsRecordname -RecordType CNAME -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup `
                             -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Cname $sreDomain)
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'CNAME' record for gateway host"
} else {
    Add-LogMessage -Level Info "Failed to set 'CNAME' record for gateway host!"
}


# Configure SHM NPS for SRE RDS RADIUS client
# -------------------------------------------
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
Add-LogMessage -Level Info "Adding RDS Gateway as RADIUS client on SHM NPS"
# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Add_RDS_Gateway_RADIUS_Client_Remote.ps1"
$params = @{
    rdsGatewayIp = "`"$($config.sre.rds.gateway.ip)`""
    rdsGatewayFqdn = "`"$($config.sre.rds.gateway.fqdn)`""
    npsSecret = "`"$npsSecret`""
    sreId = "`"$($config.sre.id)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.nps.vmName -ResourceGroupName $config.shm.nps.rg -Parameter $params
Write-Output $result.Value
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


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


# # Configuring Windows and setting DNS on RDS servers
# # --------------------------------------------------
# Add-LogMessage -Level Info "Configuring Windows and setting DNS on RDS servers..."
# $_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
# $templateScript = Get-Content -Path (Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Set_OS_Locale_and_DNS.ps1") -Raw
# $configurationScript = Get-Content -Path (Join-Path $PSScriptRoot ".." ".." "common" "remote" "Configure_Windows.ps1") -Raw
# $setLocaleDnsAndUpdate = $templateScript.Replace("# LOCALE CODE IS PROGRAMATICALLY INSERTED HERE", $configurationScript)
# $params = @{
#     sreFqdn = "`"$($config.sre.domain.fqdn)`""
#     shmFqdn = "`"$($config.shm.domain.fqdn)`""
# }
# $moduleScript = Join-Path $PSScriptRoot ".." ".." "common" "remote" "Install_Powershell_Modules.ps1"

# # Run on each of the RDS VMs
# foreach ($nameVMNameParamsPair in $vmNamePairs) {
#     $name, $vmName = $nameVMNameParamsPair
#     # Powershell modules
#     Add-LogMessage -Level Info "[ ] Installing required Powershell modules on ${name}: '$vmName'"
#     $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $moduleScript -VMName $vmName -ResourceGroupName $config.sre.rds.rg
#     Write-Output $result.Value
#     # Configuration
#     Add-LogMessage -Level Info "[ ] Setting OS locale and DNS and installing updates on ${name}: '$vmName'"
#     $result = Invoke-RemoteScript -Shell "PowerShell" -Script $setLocaleDnsAndUpdate -VMName $vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
#     Write-Output $result.Value
# }

# Set locale, install updates and reboot
# --------------------------------------
foreach ($nameVMNameParamsPair in $vmNamePairs) {
    $name, $vmName = $nameVMNameParamsPair
    Add-LogMessage -Level Info "Updating ${name}: '$vmName'..."
    Invoke-WindowsConfigureAndUpdate -VMName $vmName -ResourceGroupName $config.sre.rds.rg -CommonPowershellPath (Join-Path $PSScriptRoot ".." ".." "common")
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
    if (($blob.Name -like "*GoogleChrome_x64.msi") -or ($blob.Name -like "*PuTTY_x64.msi") -or ($blob.Name -like "*WinSCP_x32.exe")) {
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
$sasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.sre.subscriptionName -resourceGroup $sreStorageAccountRg -accountName $sreStorageAccountName
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Import_Artifacts.ps1"

# Copy software and/or scripts to RDS Gateway
Add-LogMessage -Level Info "[ ] Copying $($filePathsGateway.Count) files to RDS Gateway"
$params = @{
    storageAccountName = "`"$sreStorageAccountName`""
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
    storageAccountName = "`"$sreStorageAccountName`""
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
    storageAccountName = "`"$sreStorageAccountName`""
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


# Add VMs to correct NSG
# ----------------------
Add-VmToNSG -VMName $config.sre.rds.gateway.vmName -NSGName $config.sre.rds.gateway.nsg
Add-VmToNSG -VMName $config.sre.rds.sessionHost1.vmName -NSGName $config.sre.rds.sessionHost1.nsg
Add-VmToNSG -VMName $config.sre.rds.sessionHost2.vmName -NSGName $config.sre.rds.sessionHost2.nsg


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
