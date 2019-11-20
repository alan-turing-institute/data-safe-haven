param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force


# Get SRE config
# --------------
$config = Get-DsgConfig($sreId);
$originalContext = Get-AzContext


# Retrieve passwords from the keyvault
# ------------------------------------
Write-Host -ForegroundColor DarkCyan "Creating/retrieving user passwords..."
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName;
$dcAdminUsername = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dcAdminUsername -defaultValue "sre$($config.dsg.id)admin".ToLower()
$dcAdminPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dcAdminPassword
$npsSecret = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.rds.gateway.npsSecretName


# Set constants used in this script
# ---------------------------------
$rdsResourceGroup = $config.dsg.rds.rg
$remoteUploadDir = "C:\Installation"
$containerNameGateway = "rds-gateway-scripts"
$containerName = "rds-sh-packages"

# Get SHM storage account
# -----------------------
$_ = Set-AzContext -Subscription $config.shm.subscriptionName;
$storageAccountRg = $config.shm.storage.artifacts.rg
$storageAccountName = $config.shm.storage.artifacts.accountName
$storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg


# Deploying DC from template
# --------------------------
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
$_ = New-AzResourceGroup -Name $rdsResourceGroup -Location $config.dsg.location -Force
New-AzResourceGroupDeployment -ResourceGroupName $rdsResourceGroup -TemplateFile $(Join-Path $PSScriptRoot "$($templateName).json") @params -Verbose -DeploymentDebugLogLevel ResponseContent
$result = $?
LogTemplateOutput -ResourceGroupName $rdsResourceGroup -DeploymentName $templateName
if ($result) {
  Write-Host -ForegroundColor DarkGreen " [o] Template deployment succeeded"
} else {
  Write-Host -ForegroundColor DarkRed " [x] Template deployment failed!"
  throw "Template deployment has failed. Please check the error message above before re-running this script."
}


# Upload RDS deployment scripts to storage
# ----------------------------------------
Write-Host -ForegroundColor DarkCyan "Upload RDS deployment scripts to storage..."

# Template expansion variables
$sreFqdn = $config.dsg.domain.fqdn
$sreNetbiosName = $config.dsg.domain.netbiosName
$shmNetbiosName = $config.shm.domain.netbiosName
$dataSubnetIpPrefix = $config.dsg.network.subnets.data.prefix

# Expand deploy script
$deployScriptLocalFilePath = (New-TemporaryFile).FullName
$template = Get-Content (Join-Path $PSScriptRoot "templates" "rds_configuration.template.ps1") -Raw
$ExecutionContext.InvokeCommand.ExpandString($template) | Out-File $deployScriptLocalFilePath

# Expand web client script
$webclientScriptLocalFilePath = (New-TemporaryFile).FullName
$template = Get-Content (Join-Path $PSScriptRoot "templates" "webclient.template.ps1") -Raw
$ExecutionContext.InvokeCommand.ExpandString($template) | Out-File $webclientScriptLocalFilePath

# Upload scripts
Write-Host " - Uploading RDS gateway scripts to storage account '$storageAccountName'"
Set-AzStorageBlobContent -Container $containerNameGateway -Context $storageAccount.Context -File $deployScriptLocalFilePath -Blob "Deploy_RDS_Environment_$($config.dsg.id).ps1" -Force
Set-AzStorageBlobContent -Container $containerNameGateway -Context $storageAccount.Context -File $webclientScriptLocalFilePath -Blob "Install_Webclient.ps1" -Force


# Add DNS record for RDS Gateway
# ------------------------------
Write-Host -ForegroundColor DarkCyan "Adding DNS record for RDS Gateway"
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName;

# Get public IP address of RDS gateway
$rdsGatewayVM = Get-AzVM -ResourceGroupName $rdsResourceGroup -Name $config.dsg.rds.gateway.vmName
$rdsGatewayPrimaryNicId = ($rdsGateWayVM.NetworkProfile.NetworkInterfaces | Where-Object { $_.Primary })[0].Id
$rdsRgPublicIps = (Get-AzPublicIpAddress -ResourceGroupName $rdsResourceGroup)
$rdsGatewayPublicIp = ($rdsRgPublicIps | Where-Object {$_.IpConfiguration.Id -like "$rdsGatewayPrimaryNicId*"}).IpAddress

# Switch to DNS subscription
$_ = Set-AzContext -SubscriptionId $config.shm.dns.subscriptionName

# Add DNS record to DSG DNS Zone
$dnsRecordname = "$($config.dsg.rds.gateway.hostname)".ToLower()
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

$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Move_RDS_VMs_Into_OUs.ps1"
$params = @{
    dsgDn = "`"$($config.dsg.domain.dn)`""
    dsgNetbiosName = "`"$($config.dsg.domain.netbiosName)`""
    gatewayHostname = "`"$($config.dsg.rds.gateway.hostname)`""
    sh1Hostname = "`"$($config.dsg.rds.sessionHost1.hostname)`""
    sh2Hostname = "`"$($config.dsg.rds.sessionHost2.hostname)`""
};
Write-Host " - Adding RDS VMs to correct OUs on DSG DC"
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
Write-Host -ForegroundColor DarkCyan " - Setting OS locale and DNS on RDS Gateway ($($config.dsg.rds.gateway.vmName))"
$result = Invoke-AzVMRunCommand -Name $config.dsg.rds.gateway.vmName -ResourceGroupName $rdsResourceGroup `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
$success = $?
Write-Output $result.Value;
if ($success) {
  Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
  Write-Host -ForegroundColor DarkRed " [x] Failed!"
}

# RDS session host 1
Write-Host -ForegroundColor DarkCyan " - Setting OS locale and DNS on RDS Session Host 1 ($($config.dsg.rds.sessionHost1.vmName))"
$result = Invoke-AzVMRunCommand -Name $config.dsg.rds.sessionHost1.vmName -ResourceGroupName $rdsResourceGroup `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
$success = $?
Write-Output $result.Value;
if ($success) {
  Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
  Write-Host -ForegroundColor DarkRed " [x] Failed!"
}

# RDS session host 2
Write-Host -ForegroundColor DarkCyan " - Setting OS locale and DNS on RDS Session Host 2($($config.dsg.rds.sessionHost2.vmName))"
$result = Invoke-AzVMRunCommand -Name $config.dsg.rds.sessionHost2.vmName -ResourceGroupName $rdsResourceGroup `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
$success = $?
Write-Output $result.Value;
if ($success) {
  Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
  Write-Host -ForegroundColor DarkRed " [x] Failed!"
}


# Transfer files to RDS VMs
# -------------------------
Write-Host -ForegroundColor DarkCyan "Uploading files to RDS VMs..."

# Switch to SHM subscription
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName

# Get list of packages for each session host
Write-Host -ForegroundColor DarkCyan " - getting list of packages for each VM"
$filePathsSh1 = New-Object System.Collections.ArrayList($null)
$filePathsSh2 = New-Object System.Collections.ArrayList($null)
ForEach ($blob in Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context) {
    if (($blob.Name -like "GoogleChromeStandaloneEnterprise64*") -or ($blob.Name -like "putty-64bit*") -or ($blob.Name -like "WinSCP-*")) {
        $_ = $filePathsSh1.Add($blob.Name)
        $_ = $filePathsSh2.Add($blob.Name)
    } elseif (($blob.Name -like "install-tl-windows*") -or ($blob.Name -like "LibreOffice_*")) {
        $_ = $filePathsSh2.Add($blob.Name)
    }
}
# ... and for the gateway
$filePathsGateway = New-Object System.Collections.ArrayList($null)
ForEach ($blob in Get-AzStorageBlob -Container $containerNameGateway -Context $storageAccount.Context) {
    if (($blob.Name -like "*$($config.dsg.id).ps1") -or ($blob.Name -eq "Install_Webclient.ps1")) {
        $_ = $filePathsGateway.Add($blob.Name)
    }
}


# Get SAS token to download files from storage account
$sasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.shm.subscriptionName -resourceGroup $storageAccountRg -accountName $storageAccountName
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_RDS_Servers" "Import_Artifacts.ps1"

# Switch to SRE subscription
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName

# Copy software packages to RDS SH1 (App server)
Write-Host -ForegroundColor DarkCyan " - copying $($filePathsSh1.Count) packages to RDS Session Host 1 (App server)"
$params = @{
    storageAccountName = "`"$storageAccountName`""
    storageService = "blob"
    shareOrContainerName = "`"$containerName`""
    sasToken = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$($filePathsSh1 -join "|")`""
    downloadDir = "$remoteUploadDir"
}
$result = Invoke-AzVMRunCommand -Name "$($config.dsg.rds.sessionHost1.vmName)" -ResourceGroupName $rdsResourceGroup `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
$success = $?
Write-Output $result.Value;
if ($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Failed!"
}

# Copy software packages to RDS SH2 (Remote desktop server)
Write-Host -ForegroundColor DarkCyan " - copying $($filePathsSh2.Count) packages to RDS Session Host 2 (Remote desktop server)"
$params = @{
    storageAccountName = "`"$storageAccountName`""
    storageService = "blob"
    shareOrContainerName = "`"$containerName`""
    sasToken = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$($filePathsSh2 -join "|")`""
    downloadDir = "$remoteUploadDir"
}
$result = Invoke-AzVMRunCommand -Name "$($config.dsg.rds.sessionHost2.vmName)" -ResourceGroupName $rdsResourceGroup `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
$success = $?
Write-Output $result.Value;
if ($success) {
  Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
  Write-Host -ForegroundColor DarkRed " [x] Failed!"
}

# Copy software packages to RDS Gateway
Write-Host -ForegroundColor DarkCyan " - copying $($filePathsGateway.Count) packages to RDS Gateway"
$params = @{
    storageAccountName = "`"$storageAccountName`""
    storageService = "blob"
    shareOrContainerName = "`"$containerNameGateway`""
    sasToken = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$($filePathsGateway -join "|")`""
    downloadDir = "$remoteUploadDir"
}
$result = Invoke-AzVMRunCommand -Name "$($config.dsg.rds.gateway.vmName)" -ResourceGroupName $rdsResourceGroup `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
$success = $?
Write-Output $result.Value;
if ($success) {
  Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
  Write-Host -ForegroundColor DarkRed " [x] Failed!"
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
