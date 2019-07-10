param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)


$vmResourceGroup = $config.dsg.rds.rg;
$helperScriptDir = Join-Path $PSScriptRoot "helper_scripts" "Configure_RDS_Servers";

# Get list of software packages present on storage account

# Temporarily switch to storage account subscription
$storageAccountSubscription = $config.shm.subscriptionName
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $storageAccountSubscription;
$storageAccountRg = $config.shm.storage.artifacts.rg
$storageAccountName = $config.shm.storage.artifacts.accountName
$shareName = "configpackages"
$remoteFolder = "packages"

# Get software package file paths
$storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg

$files = Get-AzStorageFile -ShareName $shareName -path $remoteFolder -Context $storageAccount.Context | Get-AzStorageFile
$filePaths = $files | ForEach-Object{"$remoteFolder\$($_.Name)"}

$pipeSeparatedFilePaths = $filePaths -join "|"

$sasToken = New-ReadOnlyAccountSasToken -subscriptionName $storageAccountSubscription `
                -resourceGroup $storageAccountRg -accountName $storageAccountName

# Temporarily switch to DSG subscription to run remote scripts
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName

# Download software packages to RDS Session Hosts
$packageDownloadParams = @{
    storageAccountName = "`"$storageAccountName`""
    fileShareName = "`"$shareName`""
    sasToken = "`"$sasToken`""
    pipeSeparatedremoteFilePaths = "`"$pipeSeparatedFilePaths`""
    downloadDir = "C:\Software"
}
$packageDownloadParams

$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Download_Packages.ps1"
Write-Host " - Copying packages to RDS Session Host 1"
Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup `
    -Name "$($config.dsg.rds.sessionHost1.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $packageDownloadParams

Write-Host " - Copying packages to RDS Session Host 2"
Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup `
    -Name "$($config.dsg.rds.sessionHost2.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $packageDownloadParams

Exit 0
# Run OS prep on all RDS VMs
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "OS_Prep_Remote.ps1"

$osPrepParams = @{
    dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
    shmFqdn = "`"$($config.shm.domain.fqdn))`""
};

Write-Host " - Running OS Prep on RDS Gateway"
Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup `
    -Name "$($config.dsg.rds.gateway.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $osPrepParams

Write-Host " - Running OS Prep on RDS Session Host 1"
Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup `
    -Name "$($config.dsg.rds.sessionHost1.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $osPrepParams

Write-Host " - Running OS Prep on RDS Session Host 2"
Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup `
    -Name "$($config.dsg.rds.sessionHost2.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $osPrepParams

# Configure RDS servers
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Configure_RDS_Servers_Remote.ps1"

$configureRdsParams = @{
  dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
  dsgNetbiosName = "`"$($config.dsg.domain.netbiosName)`""
  shmNetbiosName = "`"$($config.shm.domain.netBiosName))`""
  dataSubnetIpPrefix = "`"$($config.dsg.network.subnets.data.prefix))`""
};

Write-Host " - Configuring RDS Servers"
Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup `
    -Name "$($config.dsg.rds.gateway.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $configureRdsParams

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
