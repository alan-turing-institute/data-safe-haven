param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/GenerateSasToken.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force


# Get SRE config
# --------------
$config = Get-DsgConfig($sreId);
$originalContext = Get-AzContext


# Set constants used in this script
# ---------------------------------
$remoteUploadDir = "C:\Installation"
$containerNameGateway = "sre-rds-gateway-scripts"
$containerNameSessionHosts = "sre-rds-sh-packages"


# Set variables used in template expansion
# ----------------------------------------
$sreFqdn = $config.dsg.domain.fqdn
$sreNetbiosName = $config.dsg.domain.netbiosName
$shmNetbiosName = $config.shm.domain.netbiosName
$dataSubnetIpPrefix = $config.dsg.network.subnets.data.prefix
$rdsGatewayVmName = $config.dsg.rds.gateway.vmName


# Retrieve passwords from the keyvault
# ------------------------------------
Write-Host -ForegroundColor DarkCyan "Creating/retrieving secrets from '$($config.dsg.keyVault.name)' KeyVault..."
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName;
$dcAdminUsername = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dcAdminUsername -defaultValue "sre$($config.dsg.id)admin".ToLower()
$dcAdminPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dcAdminPassword
$npsSecret = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.rds.gateway.npsSecretName -length 12


# Get SHM storage account
# -----------------------
$_ = Set-AzContext -Subscription $config.shm.subscriptionName;
$shmStorageAccountRg = $config.shm.storage.artifacts.rg
$shmStorageAccountName = $config.shm.storage.artifacts.accountName
$shmStorageAccount = Get-AzStorageAccount -Name $shmStorageAccountName -ResourceGroupName $shmStorageAccountRg


# Get SRE storage account
# -----------------------
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName;
$sreStorageAccountRg = $config.dsg.storage.artifacts.rg
$sreStorageAccountName = $config.dsg.storage.artifacts.accountName
$sreStorageAccount = Get-AzStorageAccount -Name $sreStorageAccountName -ResourceGroupName $sreStorageAccountRg


# Deploy RDS from template
# ------------------------
$templateName = "sre-rds-template"
Write-Host -ForegroundColor DarkCyan "Deploying RDS from template $templateName..."
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName;
$params = @{
    "SRE ID" = $config.dsg.id
    "RDS Gateway Name" = $config.dsg.rds.gateway.vmName
    "RDS Gateway VM Size" = $config.dsg.rds.gateway.vmSize
    "RDS Gateway IP Address" = $config.dsg.rds.gateway.ip
    "RDS Session Host 1 Name" = $config.dsg.rds.sessionHost1.vmName
    "RDS Session Host 1 VM Size" = $config.dsg.rds.sessionHost1.vmSize
    "RDS Session Host 1 IP Address" = $config.dsg.rds.sessionHost1.ip
    "RDS Session Host 2 Name" = $config.dsg.rds.sessionHost2.vmName
    "RDS Session Host 2 VM Size" = $config.dsg.rds.sessionHost2.vmSize
    "RDS Session Host 2 IP Address" = $config.dsg.rds.sessionHost2.ip
    "Administrator User" = $dcAdminUsername
    "Administrator Password" = (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force)
    "Virtual Network Name" = $config.dsg.network.vnet.name
    "Virtual Network Resource Group" = $config.dsg.network.vnet.rg
    "Virtual Network Subnet" = $config.dsg.network.subnets.rds.name
    "Domain Name" = $config.dsg.domain.fqdn
}
$_ = New-AzResourceGroup -Name  $config.dsg.rds.rg -Location $config.dsg.location -Force
New-AzResourceGroupDeployment -ResourceGroupName $config.dsg.rds.rg -TemplateFile $(Join-Path $PSScriptRoot "$($templateName).json") @params -Verbose -DeploymentDebugLogLevel ResponseContent
$result = $?
LogTemplateOutput -ResourceGroupName $config.dsg.rds.rg -DeploymentName $templateName
if ($result) {
    Write-Host -ForegroundColor DarkGreen " [o] Template deployment succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Template deployment failed!"
    throw "Template deployment has failed. Please check the error message above before re-running this script."
}


# Create blob containers in SRE storage account
# ---------------------------------------------
Write-Host -ForegroundColor DarkCyan "Creating blob storage containers in storage account '$sreStorageAccountName'..."
ForEach ($containerName in ($containerNameGateway, $containerNameSessionHosts)) {
    if(-not (Get-AzStorageContainer -Context $sreStorageAccount.Context | Where-Object { $_.Name -eq "$containerName" })){
        Write-Host -ForegroundColor DarkCyan " [ ] creating container '$containerName'..."
        $_ = New-AzStorageContainer -Name $containerName -Context $sreStorageAccount.Context;
        if ($?) {
            Write-Host -ForegroundColor DarkGreen " [o] Container creation succeeded"
        } else {
            Write-Host -ForegroundColor DarkRed " [x] Container creation failed!"
        }
    }
    $blobs = @(Get-AzStorageBlob -Container $containerName -Context $sreStorageAccount.Context)
    $numBlobs = $blobs.Length
    if($numBlobs -gt 0){
        Write-Host -ForegroundColor DarkCyan " [ ] deleting $numBlobs blobs aready in container '$containerName'..."
        $blobs | ForEach-Object {Remove-AzStorageBlob -Blob $_.Name -Container $containerName -Context $sreStorageAccount.Context -Force}
        while($numBlobs -gt 0){
            Start-Sleep -Seconds 5
            $numBlobs = (Get-AzStorageBlob -Container $containerName -Context $sreStorageAccount.Context).Length
        }
        if ($?) {
            Write-Host -ForegroundColor DarkGreen " [o] Blob deletion succeeded"
        } else {
            Write-Host -ForegroundColor DarkRed " [x] Blob deletion failed!"
        }
    }
}


# Upload RDS deployment scripts and installers to SRE storage
# -----------------------------------------------------------
Write-Host -ForegroundColor DarkCyan "Upload RDS deployment scripts to storage..."

# Expand deploy script
$deployScriptLocalFilePath = (New-TemporaryFile).FullName
$template = Get-Content (Join-Path $PSScriptRoot "templates" "rds_configuration.template.ps1") -Raw
$ExecutionContext.InvokeCommand.ExpandString($template) | Out-File $deployScriptLocalFilePath

# Expand server list XML
$serverListLocalFilePath = (New-TemporaryFile).FullName
$template = Get-Content (Join-Path $PSScriptRoot "templates" "ServerList.template.xml") -Raw
$ExecutionContext.InvokeCommand.ExpandString($template) | Out-File $serverListLocalFilePath

# Copy existing files
Write-Host -ForegroundColor DarkCyan " [ ] Copying RDS installers to storage account '$sreStorageAccountName'"
$blobs = Get-AzStorageBlob -Context $shmStorageAccount.Context -Container $containerNameSessionHosts
$blobs | Start-AzStorageBlobCopy -Context $shmStorageAccount.Context -DestContext $sreStorageAccount.Context -DestContainer $containerNameSessionHosts -Force
if ($?) {
    Write-Host -ForegroundColor DarkGreen " [o] File copying succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] File copying failed!"
}

# Upload scripts
Write-Host -ForegroundColor DarkCyan " [ ] Uploading RDS gateway scripts to storage account '$sreStorageAccountName'"
Set-AzStorageBlobContent -Container $containerNameGateway -Context $sreStorageAccount.Context -File $deployScriptLocalFilePath -Blob "Deploy_RDS_Environment.ps1" -Force
Set-AzStorageBlobContent -Container $containerNameGateway -Context $sreStorageAccount.Context -File $serverListLocalFilePath -Blob "ServerList.xml" -Force
if ($?) {
    Write-Host -ForegroundColor DarkGreen " [o] File uploading succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] File uploading failed!"
}


# Add DNS record for RDS Gateway
# ------------------------------
Write-Host -ForegroundColor DarkCyan "Adding DNS record for RDS Gateway"
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName;

# Get public IP address of RDS gateway
$rdsGatewayVM = Get-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.gateway.vmName
$rdsGatewayPrimaryNicId = ($rdsGateWayVM.NetworkProfile.NetworkInterfaces | Where-Object { $_.Primary })[0].Id
$rdsRgPublicIps = (Get-AzPublicIpAddress -ResourceGroupName $config.dsg.rds.rg)
$rdsGatewayPublicIp = ($rdsRgPublicIps | Where-Object {$_.IpConfiguration.Id -like "$rdsGatewayPrimaryNicId*"}).IpAddress

# Switch to DNS subscription
$_ = Set-AzContext -SubscriptionId $config.shm.dns.subscriptionName

# Add DNS record to DSG DNS Zone
$dnsRecordname = "$($config.dsg.rds.gateway.hostname)".ToLower()
# $dnsRecordname = "sre"
$dnsResourceGroup = $config.shm.dns.rg
$dnsTtlSeconds = 30
$dsgDomain = $config.dsg.domain.fqdn
Write-Host -ForegroundColor DarkCyan " [ ] Setting 'A' record for 'rds' host to '$rdsGatewayPublicIp' in SRE $sreId DNS zone ($dsgDomain)"
Remove-AzDnsRecordSet -Name $dnsRecordname -RecordType A -ZoneName $dsgDomain -ResourceGroupName $dnsResourceGroup
$result = New-AzDnsRecordSet -Name $dnsRecordname -RecordType A -ZoneName $dsgDomain -ResourceGroupName $dnsResourceGroup `
                             -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -IPv4Address $rdsGatewayPublicIp)
$success = $?
Write-Output $result.Value;
if ($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Successfully set 'A' record for 'rds' host"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed to set 'A' record for 'rds' host!"
}


# Configure SHM NPS for DSG RDS RADIUS client
# -------------------------------------------
Write-Host -ForegroundColor DarkCyan "Adding RDS Gateway as RADIUS client on SHM NPS"
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
# Run remote script
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Add_RDS_Gateway_RADIUS_Client_Remote.ps1"
$params = @{
    rdsGatewayIp = "`"$($config.dsg.rds.gateway.ip)`""
    rdsGatewayFqdn = "`"$($config.dsg.rds.gateway.fqdn)`""
    npsSecret = "`"$($npsSecret)`""
    dsgId = "`"$($config.dsg.id)`""
}
$result = Invoke-AzVMRunCommand -Name $config.shm.nps.vmName -ResourceGroupName $config.shm.nps.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
$success = $?
Write-Output $result.Value;
if ($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Successfully added RADIUS client"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed to add RADIUS client!"
}


# Add RDS VMs to correct OUs
# --------------------------
Write-Host -ForegroundColor DarkCyan "Adding RDS VMs to correct OUs"
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName
# Run remote script
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Move_RDS_VMs_Into_OUs.ps1"
$params = @{
    dsgDn = "`"$($config.dsg.domain.dn)`""
    dsgNetbiosName = "`"$($config.dsg.domain.netbiosName)`""
    gatewayHostname = "`"$($config.dsg.rds.gateway.hostname)`""
    sh1Hostname = "`"$($config.dsg.rds.sessionHost1.hostname)`""
    sh2Hostname = "`"$($config.dsg.rds.sessionHost2.hostname)`""
}
$result = Invoke-AzVMRunCommand -Name "$($config.dsg.dc.vmName)" -ResourceGroupName "$($config.dsg.dc.rg)" `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
$success = $?
Write-Output $result.Value;
if ($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Successfully added RDS VMs to correct OUs"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed to add RDS VMs to correct OUs!"
}


# Set OS locale and DNS on RDS servers
# ------------------------------------
Write-Host -ForegroundColor DarkCyan "Setting OS locale and DNS on RDS servers..."
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Set_OS_Locale_and_DNS.ps1"
$params = @{
    dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
    shmFqdn = "`"$($config.shm.domain.fqdn)`""
}

# RDS gateway
Write-Host -ForegroundColor DarkCyan " [ ] Setting OS locale and DNS on RDS Gateway ($($config.dsg.rds.gateway.vmName))"
$result = Invoke-AzVMRunCommand -Name $config.dsg.rds.gateway.vmName -ResourceGroupName $config.dsg.rds.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
$success = $?
Write-Output $result.Value;
if ($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed!"
}

# RDS session host 1
Write-Host -ForegroundColor DarkCyan " [ ] Setting OS locale and DNS on RDS Session Host 1 (App server)"
$result = Invoke-AzVMRunCommand -Name $config.dsg.rds.sessionHost1.vmName -ResourceGroupName $config.dsg.rds.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
$success = $?
Write-Output $result.Value;
if ($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed!"
}

# RDS session host 2
Write-Host -ForegroundColor DarkCyan " [ ] Setting OS locale and DNS on RDS Session Host 2 (Remote desktop server)"
$result = Invoke-AzVMRunCommand -Name $config.dsg.rds.sessionHost2.vmName -ResourceGroupName $config.dsg.rds.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
$success = $?
Write-Output $result.Value;
if ($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed!"
}


# Import files to RDS VMs
# -----------------------
Write-Host -ForegroundColor DarkCyan "Importing files from storage to RDS VMs..."

# Switch to SHM subscription
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName

# Get list of packages for each session host
Write-Host -ForegroundColor DarkCyan " [ ] Getting list of packages for each VM"
$filePathsSh1 = New-Object System.Collections.ArrayList($null)
$filePathsSh2 = New-Object System.Collections.ArrayList($null)
ForEach ($blob in Get-AzStorageBlob -Container $containerNameSessionHosts -Context $sreStorageAccount.Context) {
    if (($blob.Name -like "GoogleChromeStandaloneEnterprise64*") -or ($blob.Name -like "putty-64bit*") -or ($blob.Name -like "WinSCP-*")) {
        $_ = $filePathsSh1.Add($blob.Name)
        $_ = $filePathsSh2.Add($blob.Name)
    # } elseif (($blob.Name -like "install-tl-windows*") -or ($blob.Name -like "LibreOffice_*")) {
    } elseif ($blob.Name -like "LibreOffice_*") {
        $_ = $filePathsSh2.Add($blob.Name)
    }
}
# ... and for the gateway
$filePathsGateway = New-Object System.Collections.ArrayList($null)
ForEach ($blob in Get-AzStorageBlob -Container $containerNameGateway -Context $sreStorageAccount.Context) {
    $_ = $filePathsGateway.Add($blob.Name)
}
Write-Host -ForegroundColor DarkGreen " [o] Found $($filePathsSh1.Count + $filePathsSh2.Count) packages in total"

# Switch to SRE subscription
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName

# Get SAS token to download files from storage account
$sasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.dsg.subscriptionName -resourceGroup $sreStorageAccountRg -accountName $sreStorageAccountName
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Import_Artifacts.ps1"

# Copy software and/or scripts to RDS SH1 (App server)
Write-Host -ForegroundColor DarkCyan " [ ] Copying $($filePathsSh1.Count) files to RDS Session Host 1 (App server)"
$params = @{
    storageAccountName = "`"$sreStorageAccountName`""
    storageService = "blob"
    shareOrContainerName = "`"$containerNameSessionHosts`""
    sasToken = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$($filePathsSh1 -join "|")`""
    downloadDir = "$remoteUploadDir"
}
$result = Invoke-AzVMRunCommand -Name "$($config.dsg.rds.sessionHost1.vmName)" -ResourceGroupName $config.dsg.rds.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
$success = $?
Write-Output $result.Value;
if ($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed!"
}

# Copy software and/or scripts to RDS SH2 (Remote desktop server)
Write-Host -ForegroundColor DarkCyan " [ ] Copying $($filePathsSh2.Count) files to RDS Session Host 2 (Remote desktop server)"
$params = @{
    storageAccountName = "`"$sreStorageAccountName`""
    storageService = "blob"
    shareOrContainerName = "`"$containerNameSessionHosts`""
    sasToken = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$($filePathsSh2 -join "|")`""
    downloadDir = "$remoteUploadDir"
}
$result = Invoke-AzVMRunCommand -Name "$($config.dsg.rds.sessionHost2.vmName)" -ResourceGroupName $config.dsg.rds.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
$success = $?
Write-Output $result.Value;
if ($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed!"
}

# Copy software and/or scripts to RDS Gateway
Write-Host -ForegroundColor DarkCyan " [ ] Copying $($filePathsGateway.Count) files to RDS Gateway"
$params = @{
    storageAccountName = "`"$sreStorageAccountName`""
    storageService = "blob"
    shareOrContainerName = "`"$containerNameGateway`""
    sasToken = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$($filePathsGateway -join "|")`""
    downloadDir = "$remoteUploadDir"
}
$result = Invoke-AzVMRunCommand -Name "$($config.dsg.rds.gateway.vmName)" -ResourceGroupName $config.dsg.rds.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
$success = $?
Write-Output $result.Value;
if ($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed!"
}


# Install packages on RDS VMs
# ---------------------------
Write-Host -ForegroundColor DarkCyan "Installing packages on RDS VMs..."
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName

# Install software packages on RDS SH1 (App server)
Write-Host -ForegroundColor DarkCyan " [ ] Installing packages on RDS Session Host 1 (App server)"
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Install_Packages.ps1"
$result = Invoke-AzVMRunCommand -Name $config.dsg.rds.sessionHost1.vmName -ResourceGroupName $config.dsg.rds.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath;
$success = $?
Write-Output $result.Value;
if ($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Successfully installed packages"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed to install packages!"
}

# Install software packages on RDS SH2 (Remote desktop server)
Write-Host -ForegroundColor DarkCyan " [ ] Installing packages on RDS Session Host 2 (Remote desktop server)"
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Install_Packages.ps1"
$result = Invoke-AzVMRunCommand -Name $config.dsg.rds.sessionHost2.vmName -ResourceGroupName $config.dsg.rds.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath;
$success = $?
Write-Output $result.Value;
if ($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Successfully installed packages"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed to install packages!"
}


# Install required Powershell modules on RDS Gateway
# --------------------------------------------------
Write-Host -ForegroundColor DarkCyan "Installing required Powershell modules on RDS Gateway..."
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName
$params01 = @{
    dcAdminUsername = "`"$dcAdminUsername`""
    sreNetbiosName = "`"$sreNetbiosName`""
}
ForEach ($scriptNameParamsPair in (("Install_Powershell_Modules_01.ps1", $params01),
                                   ("Install_Powershell_Modules_02.ps1", $null))) {
    $scriptName, $params = $scriptNameParamsPair
    $scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" $scriptName
    if ($params -eq $null) {
        $result = Invoke-AzVMRunCommand -Name $config.dsg.rds.gateway.vmName -ResourceGroupName $config.dsg.rds.rg `
                                        -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath;
    } else {
        $result = Invoke-AzVMRunCommand -Name $config.dsg.rds.gateway.vmName -ResourceGroupName $config.dsg.rds.rg `
                                        -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
    }
    $success = $?
    Write-Output $result.Value;
    if ($success) {
        Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
    } else {
        Write-Host -ForegroundColor DarkRed " [x] Failed!"
    }
}


# Reboot the gateway VM
# ---------------------
Write-Host -ForegroundColor DarkCyan "Rebooting the RDS Gateway..."
Restart-AzVM -Name $config.dsg.rds.gateway.vmName -ResourceGroupName $config.dsg.rds.rg
# The following syntax is preferred in future, but does not yet work
# $vmID = (Get-AzVM -ResourceGroupName $config.dsg.rds.gateway.vmName -Name $config.dsg.rds.rg).Id
# Restart-AzVM -Id$vmID
if ($?) {
    Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed!"
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
