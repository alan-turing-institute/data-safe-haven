param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/GenerateSasToken.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force


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


# Set variables used in template expansion, retrieving from the key vault where appropriate
# -----------------------------------------------------------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$dataSubnetIpPrefix = $config.sre.network.subnets.data.prefix
$dcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dcAdminPassword
$dcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dcAdminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$npsSecret = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.rds.gateway.npsSecretName -DefaultLength 12
$rdsGatewayVmFqdn = $config.sre.rds.gateway.fqdn
$rdsGatewayVmName = $config.sre.rds.gateway.vmName
$rdsSh1VmFqdn = $config.sre.rds.sessionHost1.fqdn
$rdsSh1VmName = $config.sre.rds.sessionHost1.vmName
$rdsSh2VmFqdn = $config.sre.rds.sessionHost2.fqdn
$rdsSh2VmName = $config.sre.rds.sessionHost2.vmName
$shmNetbiosName = $config.shm.domain.netbiosName
$sreFqdn = $config.sre.domain.fqdn
$sreNetbiosName = $config.sre.domain.netbiosName


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
$nsgGateway = Deploy-NetworkSecurityGroup -Name $config.sre.rds.nsg.gateway.name -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgGateway `
                             -Name "HTTPS_In" `
                             -Description "Allow HTTPS inbound to RDS server" `
                             -Priority 100 `
                             -Direction Inbound -Access Allow -Protocol TCP `
                             -SourceAddressPrefix Internet -SourcePortRange * `
                             -DestinationAddressPrefix * -DestinationPortRange 443
$nsgSessionHosts = Deploy-NetworkSecurityGroup -Name $config.sre.rds.nsg.session_hosts.name -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
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
    Administrator_Password = (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force)
    Administrator_User = $dcAdminUsername
    BootDiagnostics_Account_Name = $config.sre.bootdiagnostics.accountName
    Domain_Name = $config.sre.domain.fqdn
    NSG_Gateway_Name = $config.sre.rds.nsg.gateway.name
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
Deploy-ArmTemplate -TemplatePath "$PSScriptRoot/sre-rds-template.json" -Params $params -ResourceGroupName $config.sre.rds.rg


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
$template = Get-Content (Join-Path $PSScriptRoot "templates" "rds_configuration.template.ps1") -Raw
$ExecutionContext.InvokeCommand.ExpandString($template) | Out-File $deployScriptLocalFilePath

# Expand server list XML
$serverListLocalFilePath = (New-TemporaryFile).FullName
$template = Get-Content (Join-Path $PSScriptRoot "templates" "ServerList.template.xml") -Raw
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
Set-AzStorageBlobContent -Container $containerNameGateway -Context $sreStorageAccount.Context -File (Join-Path $PSScriptRoot "templates" "Set-RDPublishedName.ps1") -Blob "Set-RDPublishedName.ps1" -Force
if ($?) {
    Add-LogMessage -Level Success "File uploading succeeded"
} else {
    Add-LogMessage -Level Fatal "File uploading failed!"
}


# Add DNS record for RDS Gateway
# ------------------------------
Add-LogMessage -Level Info "Adding DNS record for RDS Gateway"
$_ = Set-AzContext -Subscription $config.sre.subscriptionName;

# Get public IP address of RDS gateway
$rdsGatewayVM = Get-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.gateway.vmName
$rdsGatewayPrimaryNicId = ($rdsGateWayVM.NetworkProfile.NetworkInterfaces | Where-Object { $_.Primary })[0].Id
$rdsRgPublicIps = (Get-AzPublicIpAddress -ResourceGroupName $config.sre.rds.rg)
$rdsGatewayPublicIp = ($rdsRgPublicIps | Where-Object { $_.IpConfiguration.Id -like "$rdsGatewayPrimaryNicId*" }).IpAddress

# Add DNS record to SRE DNS Zone
$_ = Set-AzContext -SubscriptionId $config.shm.dns.subscriptionName
$dnsRecordname = "$($config.sre.rds.gateway.hostname)".ToLower()
# $dnsRecordname = "@"
$dnsResourceGroup = $config.shm.dns.rg
$dnsTtlSeconds = 30
$sreDomain = $config.sre.domain.fqdn
Add-LogMessage -Level Info "[ ] Setting 'A' record for 'rds' host to '$rdsGatewayPublicIp' in SRE $sreId DNS zone ($sreDomain)"
Remove-AzDnsRecordSet -Name $dnsRecordname -RecordType A -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
$result = New-AzDnsRecordSet -Name $dnsRecordname -RecordType A -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup `
                             -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -IPv4Address $rdsGatewayPublicIp)
$success = $?
Write-Output $result.Value;
if ($success) {
    Add-LogMessage -Level Success "Successfully set 'A' record for 'rds' host"
} else {
    Add-LogMessage -Level Info "Failed to set 'A' record for 'rds' host!"
}


# Configure SHM NPS for SRE RDS RADIUS client
# -------------------------------------------
Add-LogMessage -Level Info "Adding RDS Gateway as RADIUS client on SHM NPS"
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
# Run remote script
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Add_RDS_Gateway_RADIUS_Client_Remote.ps1"
$params = @{
    rdsGatewayIp = "`"$($config.sre.rds.gateway.ip)`""
    rdsGatewayFqdn = "`"$($config.sre.rds.gateway.fqdn)`""
    npsSecret = "`"$($npsSecret)`""
    sreId = "`"$($config.sre.id)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.nps.vmName -ResourceGroupName $config.shm.nps.rg -Parameter $params
Write-Output $result.Value


# Add RDS VMs to correct OUs
# --------------------------
Add-LogMessage -Level Info "Adding RDS VMs to correct OUs"
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
# Run remote script
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Move_RDS_VMs_Into_OUs.ps1"
$params = @{
    sreDn = "`"$($config.sre.domain.dn)`""
    sreNetbiosName = "`"$($config.sre.domain.netbiosName)`""
    gatewayHostname = "`"$($config.sre.rds.gateway.hostname)`""
    sh1Hostname = "`"$($config.sre.rds.sessionHost1.hostname)`""
    sh2Hostname = "`"$($config.sre.rds.sessionHost2.hostname)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.dc.vmName -ResourceGroupName $config.sre.dc.rg -Parameter $params
Write-Output $result.Value


# Set OS locale and DNS on RDS servers
# ------------------------------------
Add-LogMessage -Level Info "Setting OS locale and DNS on RDS servers..."
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$templateScript = Get-Content -Path (Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Set_OS_Locale_and_DNS.ps1") -Raw
$configurationScript = Get-Content -Path (Join-Path $PSScriptRoot ".." ".." ".." "common_powershell" "remote" "Configure_Windows.ps1") -Raw
$setLocaleDnsAndUpdate = $templateScript.Replace("# LOCALE CODE IS PROGRAMATICALLY INSERTED HERE", $configurationScript)
$params = @{
    sreFqdn = "`"$($config.sre.domain.fqdn)`""
    shmFqdn = "`"$($config.shm.domain.fqdn)`""
}
$moduleScript = Join-Path $PSScriptRoot ".." ".." ".." "common_powershell" "remote" "Install_Powershell_Modules.ps1"


# RDS gateway
Add-LogMessage -Level Info "[ ] Setting OS locale and DNS on RDS Gateway ($($config.sre.rds.gateway.vmName))"
$result = Invoke-RemoteScript -Shell "PowerShell" -Script $setLocaleDnsAndUpdate -VMName $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
Write-Output $result.Value

# RDS_Session_Host_Apps
Add-LogMessage -Level Info "[ ] Setting OS locale and DNS on RDS Session Host App server"
$result = Invoke-RemoteScript -Shell "PowerShell" -Script $setLocaleDnsAndUpdate -VMName $config.sre.rds.sessionHost1.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
Write-Output $result.Value

# RDS_Session_Host_Desktop
Add-LogMessage -Level Info "[ ] Setting OS locale and DNS on RDS Session Host Desktop (Remote desktop server)"
$result = Invoke-RemoteScript -Shell "PowerShell" -Script $setLocaleDnsAndUpdate -VMName $config.sre.rds.sessionHost2.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
Write-Output $result.Value


# Import files to RDS VMs
# -----------------------
Add-LogMessage -Level Info "Importing files from storage to RDS VMs..."
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName

# Get list of packages for each session host
Add-LogMessage -Level Info " [ ] Getting list of packages for each VM"
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
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Import_Artifacts.ps1"

# Copy software and/or scripts to RDS SH1 (App server)
Add-LogMessage -Level Info " [ ] Copying $($filePathsSh1.Count) files to RDS_Session_Host_Apps (App server)"
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
Add-LogMessage -Level Info " [ ] Copying $($filePathsSh2.Count) files to RDS_Session_Host_Desktop (Remote desktop server)"
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


# Copy software and/or scripts to RDS Gateway
Add-LogMessage -Level Info " [ ] Copying $($filePathsGateway.Count) files to RDS Gateway"
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


# Install packages on RDS VMs
# ---------------------------
Add-LogMessage -Level Info "Installing packages on RDS VMs..."
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName

# Install software packages on RDS SH1 (App server)
Add-LogMessage -Level Info "[ ] Installing packages on RDS_Session_Host_Apps (App server)"
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Install_Packages.ps1"
$result = Invoke-AzVMRunCommand -Name $config.sre.rds.sessionHost1.vmName -ResourceGroupName $config.sre.rds.rg `
     -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath;
$success = $?
Write-Output $result.Value;
if ($success) {
    Add-LogMessage -Level Success "Successfully installed packages"
} else {
    Add-LogMessage -Level Fatal "Failed to install packages!"
}

# Install software packages on RDS SH2 (Remote desktop server)
Add-LogMessage -Level Info "[ ] Installing packages on RDS_Session_Host_Desktop (Remote desktop server)"
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Install_Packages.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.rds.sessionHost2.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
Write-Output $result.Value
# $result = Invoke-AzVMRunCommand -Name $config.sre.rds.sessionHost2.vmName -ResourceGroupName $config.sre.rds.rg `
#      -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath;
# $success = $?
# Write-Output $result.Value;
# if ($success) {
#     Add-LogMessage -Level Success "Successfully installed packages"
# } else {
#     Add-LogMessage -Level Fatal "Failed to install packages!"
# }


# Install required Powershell modules on RDS Gateway
# --------------------------------------------------
Add-LogMessage -Level Info "[ ] Installing required Powershell modules on RDS Gateway..."
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$params = @{
    dcAdminUsername = "`"$dcAdminUsername`""
    sreNetbiosName = "`"$sreNetbiosName`""
}
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Install_Additional_Powershell_Modules.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg
Write-Output $result.Value
# foreach ($scriptNameParamsPair in (("Install_Powershell_Modules_01.ps1", $params),
#                                    ("Install_Powershell_Modules_02.ps1", $null))) {
#     $scriptName, $params = $scriptNameParamsPair
#     $scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" $scriptName
#     $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
#     Write-Output $result.Value
# }



# Reboot the gateway VM
# ---------------------
Add-LogMessage -Level Info "Rebooting the RDS Gateway..."
Restart-AzVM -Name $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg
# The following syntax is preferred in future, but does not yet work
# $vmID = (Get-AzVM -ResourceGroupName $config.sre.rds.gateway.vmName -Name $config.sre.rds.rg).Id
# Restart-AzVM -Id$vmID
if ($?) {
    Add-LogMessage -Level Success "Rebooting the RDS Gateway succeeded"
} else {
    Add-LogMessage -Level Fatal "Rebooting the RDS Gateway failed!"
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
