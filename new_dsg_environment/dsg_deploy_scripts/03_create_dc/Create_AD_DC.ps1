param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../GeneratePassword.psm1 -Force
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../GenerateSasToken.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$storageAccountSubscription = $config.dsg.subscriptionName;
$_ = Set-AzContext -SubscriptionId $storageAccountSubscription;

# Set deployment parameters not directly set in config file
$vmSize = "Standard_B2ms";

# Upload artifacts to storage account
$storageAccountLocation = $config.dsg.location
$storageAccountRg = $config.dsg.storage.artifacts.rg
$storageAccountName = $config.dsg.storage.artifacts.accountName

# Create storage account if it doesn't exist
$_ = New-AzResourceGroup -Name $storageAccountRg -Location $storageAccountLocation -Force;
$storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -ErrorVariable notExists -ErrorAction SilentlyContinue
if($notExists) {
  Write-Host " - Creating storage account '$storageAccountName'"
  $storageAccount = New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -Location $storageAccountLocation -SkuName "Standard_GRS" -Kind "StorageV2"
}
$artifactsFolderName = "dc-create-scripts"
$artifactsDir = (Join-Path $PSScriptRoot "artifacts" $artifactsFolderName)
$containerName = $artifactsFolderName
# Create container if it doesn't exist
if(-not (Get-AzStorageContainer -Context $storageAccount.Context | Where-Object { $_.Name -eq "$containerName" })){
  Write-Host " - Creating container '$containerName' in storage account '$storageAccountName'"
  $_ = New-AzStorageContainer -Name $containerName -Context $storageAccount.Context;
}
$blobs = @(Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context)
$numBlobs = $blobs.Length
if($numBlobs -gt 0){
  Write-Host " - Deleting $numBlobs blobs aready in container '$containerName'"
  $blobs | ForEach-Object {Remove-AzStorageBlob -Blob $_.Name -Container $containerName -Context $storageAccount.Context -Force}
  while($numBlobs -gt 0){
    Write-Host " - Waiting for deletion of $numBlobs remaining blobs"
    Start-Sleep -Seconds 10
    $numBlobs = (Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context).Length
  }
}

# Upload ZIP file with artifacts
$zipFileName = "dc-create.zip"
$zipFilePath = (Join-Path $artifactsDir $zipFileName )
Write-Host " - Uploading '$zipFilePath' to container '$containerName'"
$_ = Set-AzStorageBlobContent -File $zipFilePath -Container $containerName -Context $storageAccount.Context;

# Get SAS token
$artifactLocation = "https://$storageAccountName.blob.core.windows.net/$containerName/$zipFileName";
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $storageAccountSubscription `
                      -resourceGroup $storageAccountRg -accountName $storageAccountName

$artifactSasToken = (ConvertTo-SecureString $artifactSasToken -AsPlainText -Force);


# Temporarily switch to DSG subscription
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# Fetch DC admin username (or create if not present)
$dcAdminUsername = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.dsg.dc.usernameSecretName).SecretValueText;
if ($null -eq $dcAdminPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.dsg.dc.usernameSecretName -SecretValue $newPassword;
  $dcAdminUsername = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.dsg.dc.usernameSecretName ).SecretValueText;
}
# Fetch admin password (or create if not present)
$adminPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.dc.admin.passwordSecretName).SecretValueText;
if ($null -eq $adminPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.dc.admin.passwordSecretName -SecretValue $newPassword;
  $adminPassword = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.dc.admin.passwordSecretName).SecretValueText;
}
$adminPassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force;

$netbiosNameMaxLength = 15
if($config.dsg.domain.netbiosName.length -gt $netbiosNameMaxLength) {
    throw "Netbios name must be no more than 15 characters long. '$($config.dsg.domain.netbiosName)' is $($config.dsg.domain.netbiosName.length) characters long."
} 
$params = @{
 "DC Name" = $config.dsg.dc.vmName
 "VM Size" = $vmSize
 "IP Address" = $config.dsg.dc.ip
 "Administrator User" = $dcAdminUsername
 "Administrator Password" = $adminPassword
 "Virtual Network Name" = $config.dsg.network.vnet.name
 "Virtual Network Resource Group" = $config.dsg.network.vnet.rg
 "Virtual Network Subnet" = $config.dsg.network.subnets.identity.name
 "Artifacts Location" = $artifactLocation
 "Artifacts Location SAS Token" = $artifactSasToken
 "Domain Name" = $config.dsg.domain.fqdn
 "NetBIOS Name" = $config.dsg.domain.netbiosName
}

$templatePath = Join-Path $PSScriptRoot "dc-master-template.json"

Write-Output ($params | ConvertTo-JSON -depth 10)

$_ = New-AzResourceGroup -Name $config.dsg.dc.rg -Location $config.dsg.location
New-AzResourceGroupDeployment -ResourceGroupName $config.dsg.dc.rg `
  -TemplateFile $templatePath @params -Verbose

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
