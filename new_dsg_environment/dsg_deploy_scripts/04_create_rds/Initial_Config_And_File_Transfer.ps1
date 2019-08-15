param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../GeneratePassword.psm1 -Force
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../GenerateSasToken.psm1 -Force

$helperScriptDir = Join-Path $PSScriptRoot "helper_scripts" "Configure_RDS_Servers";

# Get DSG config
$config = Get-DsgConfig($dsgId)

# === Add DNS record for RDS Gateway ===
# --- Get public IP address of RDS gateway ---
# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName
$rdsGatewayVM = Get-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.gateway.vmName
$rdsGatewayPrimaryNicId = ($rdsGateWayVM.NetworkProfile.NetworkInterfaces | Where-Object { $_.Primary })[0].Id
$rdsRgPublicIps = (Get-AzPublicIpAddress -ResourceGroupName $config.dsg.rds.rg)
$rdsGatewayPublicIp = ($rdsRgPublicIps | Where-Object {$_.IpConfiguration.Id -like "$rdsGatewayPrimaryNicId*"}).IpAddress
# --- Add DNS record to DSG DNS Zone ---
# Temporarily switch to SHM subscription
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$dnsRecordname = "$($config.dsg.rds.gateway.hostname)".ToLower()
$dnsResourceGroup = $config.shm.dns.rg
$dnsTtlSeconds = 30
$dsgDomain = $config.dsg.domain.fqdn
Write-Host " - Setting 'A' record for 'rds' host to '$rdsGatewayPublicIp' in DSG $dsgId DNS zone ($dsgDomain)"
Remove-AzDnsRecordSet -Name $dnsRecordname -RecordType A -ZoneName $dsgDomain -ResourceGroupName $dnsResourceGroup
$_ = New-AzDnsRecordSet -Name $dnsRecordname -RecordType A -ZoneName $dsgDomain `
    -ResourceGroupName $dnsResourceGroup -Ttl $dnsTtlSeconds `
    -DnsRecords (New-AzDnsRecordConfig -IPv4Address $rdsGatewayPublicIp)

# === Create NPS shared secret if it doesn't exist ===
# Temporarily switch to SHM subscription
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
# Fetch admin password (or create if not present)
$npsSecret = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.rds.gateway.npsSecretName).SecretValueText;
if ($null -eq $npsSecret) {
  Write-Host " - Creating NPS shared secret for RDS gateway"
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password -length 12; # We think there are issues authenticating to the NPS RADIUS server if this password is too long
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.rds.gateway.npsSecretName -SecretValue $newPassword;
  Do {
    "   - Fetching NPS shared secret from KeyVault"
    $npsSecret = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.rds.gateway.npsSecretName).SecretValueText;
    Start-Sleep -Seconds 1
  } Until (-not ($null -eq $npsSecret))
} else {
    Write-Host " - NPS shared secret for RDS gateway already exists"
}

# === Configure SHM NPS for DSG RDS RADIUS client ===
$npsRadiusClientParams = @{
    rdsGatewayIp = "`"$($config.dsg.rds.gateway.ip)`""
    rdsGatewayFqdn = "`"$($config.dsg.rds.gateway.fqdn)`""
    npsSecret = "`"$($npsSecret)`""
    dsgId = "`"$($config.dsg.id)`""
};
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Add_RDS_Gateway_RADIUS_Client_Remote.ps1"
Write-Host " - Adding RDS Gateway as RADIUS client on SHM NPS"
$result = Invoke-AzVMRunCommand -ResourceGroupName $($config.shm.nps.rg) `
    -Name "$($config.shm.nps.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $npsRadiusClientParams
Write-Host $result.Value[0].Message
Write-Host $result.Value[1].Message

# === Move RDS VMs into correct OUs ===
# Temporarily switch to DSG subscription
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName

$rdsResourceGroup = $config.dsg.rds.rg;

$vmOuMoveParams = @{
    dsgDn = "`"$($config.dsg.domain.dn)`""
    dsgNetbiosName = "`"$($config.dsg.domain.netbiosName)`""
    gatewayHostname = "`"$($config.dsg.rds.gateway.hostname)`""
    sh1Hostname = "`"$($config.dsg.rds.sessionHost1.hostname)`""
    sh2Hostname = "`"$($config.dsg.rds.sessionHost2.hostname)`""
};
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Move_RDS_VMs_Into_OUs.ps1"
Write-Host " - Moving RDS VMs to correct OUs on DSG DC"
$result = Invoke-AzVMRunCommand -ResourceGroupName $($config.dsg.dc.rg) `
    -Name "$($config.dsg.dc.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $vmOuMoveParams
Write-Host $result.Value[0].Message
Write-Host $result.Value[1].Message

# === Run OS prep script on RDS VMs ===
# Temporarily switch to DSG subscription
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName
$osPrepParams = @{
    dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
    shmFqdn = "`"$($config.shm.domain.fqdn)`""
};

$scriptPath = Join-Path $helperScriptDir "remote_scripts" "OS_Prep_Remote.ps1"
$vmName = "$($config.dsg.rds.gateway.vmName)"
Write-Host " - Running OS Prep on RDS Gateway ($vmName)"
$result = Invoke-AzVMRunCommand -ResourceGroupName $rdsResourceGroup `
    -Name $vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $osPrepParams
Write-Host $result.Value[0].Message
Write-Host $result.Value[1].Message

$vmName = "$($config.dsg.rds.sessionHost1.vmName)"
Write-Host " - Running OS Prep on RDS Session Host 1 ($vmName)"
$result = Invoke-AzVMRunCommand -ResourceGroupName $rdsResourceGroup `
    -Name $vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $osPrepParams
Write-Host $result.Value[0].Message
Write-Host $result.Value[1].Message

$vmName = "$($config.dsg.rds.sessionHost2.vmName)"
Write-Host " - Running OS Prep on RDS Session Host 2 ($vmName)"
$result = Invoke-AzVMRunCommand -ResourceGroupName $rdsResourceGroup `
    -Name $vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $osPrepParams
Write-Host $result.Value[0].Message
Write-Host $result.Value[1].Message

# === Transfer files to RDS VMs ===
# Temporarily switch to storage account subscription
$storageAccountSubscription = $config.shm.subscriptionName
$_ = Set-AzContext -SubscriptionId $storageAccountSubscription;
$storageAccountRg = $config.shm.storage.artifacts.rg
$storageAccountName = $config.shm.storage.artifacts.accountName
$containerName = "rdssh-packages"
$storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg

# Get list of packages for each session host
$packageFolderSh1 = "rdssh1-app-server"
$filesSh1 = Get-AzStorageBlob -Container $containerName -Prefix $packageFolderSh1 -Context $storageAccount.Context
$filePathsSh1 = $filesSh1 | ForEach-Object{"$($_.Name)"}
$pipeSeparatedFilePathsSh1 = $filePathsSh1 -join "|"
# RDSSH2 (remote desktop server)
$packageFolderSh2 = "rdssh2-virtual-desktop-server"
$filesSh2 = Get-AzStorageBlob -Container $containerName -Prefix $packageFolderSh2 -Context $storageAccount.Context
$filePathsSh2 = $filesSh2 | ForEach-Object{"$($_.Name)"}
$pipeSeparatedFilePathsSh2 = $filePathsSh2 -join "|"

# Get SAS token to download files from storage account
$sasToken = New-ReadOnlyAccountSasToken -subscriptionName $storageAccountSubscription `
                -resourceGroup $storageAccountRg -accountName $storageAccountName

# Temporarily switch to DSG subscription to run remote scripts
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName

# Download software packages to RDS Session Hosts
# RDSSH1: App server
$packageDownloadParams = @{
    storageAccountName = "`"$storageAccountName`""
    storageService = "blob"
    shareOrContainerName = "`"$containerName`""
    sasToken = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$pipeSeparatedFilePathsSh1`""
    downloadDir = "C:\Software"
}
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Download_Files.ps1"
Write-Host " - Copying $($filesSh1.Length) packages to RDS Session Host 1"
$result = Invoke-AzVMRunCommand -ResourceGroupName $rdsResourceGroup `
    -Name "$($config.dsg.rds.sessionHost1.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $packageDownloadParams
Write-Host $result.Value[0].Message
Write-Host $result.Value[1].Message

# RDSSH2: Remote desktop server
$packageDownloadParams = @{
    storageAccountName = "`"$storageAccountName`""
    storageService = "blob"
    shareOrContainerName = "`"$containerName`""
    sasToken = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$pipeSeparatedFilePathsSh2`""
    downloadDir = "C:\Software"
}
Write-Host " - Copying $($filesSh2.Length) packages to RDS Session Host 2"
$result = Invoke-AzVMRunCommand -ResourceGroupName $rdsResourceGroup `
    -Name "$($config.dsg.rds.sessionHost2.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $packageDownloadParams
Write-Host $result.Value[0].Message
Write-Host $result.Value[1].Message

# Upload RDS deployment scripts to RDS Gateway
$scriptPath = Join-Path $helperScriptDir "local_scripts" "Upload_RDS_Deployment_Scripts.ps1"
Write-Host " - Uploading RDS environment installation scripts"
Invoke-Expression -Command "$scriptPath -dsgId $dsgId"

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
