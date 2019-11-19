param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/GenerateSasToken.psm1 -Force

# Get SRE config
$config = Get-DsgConfig($sreId);
$originalContext = Get-AzContext

# Switch to SRE subscription
# --------------------------
$storageAccountSubscription = $config.dsg.subscriptionName;
$_ = Set-AzContext -Subscription $storageAccountSubscription;

# Upload artifacts to storage account
$storageAccountLocation = $config.dsg.location
$storageAccountRg = $config.dsg.storage.artifacts.rg
$storageAccountName = $config.dsg.storage.artifacts.accountName

# Create storage account if it doesn't exist
# ------------------------------------------
Write-Host -ForegroundColor DarkCyan "Ensuring that storage account exists..."
$_ = New-AzResourceGroup -Name $storageAccountRg -Location $storageAccountLocation -Force;
$storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -ErrorVariable notExists -ErrorAction SilentlyContinue
if($notExists) {
  Write-Host -ForegroundColor DarkCyan " - Creating storage account '$storageAccountName'"
  $storageAccount = New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -Location $storageAccountLocation -SkuName "Standard_GRS" -Kind "StorageV2"
}
$artifactsFolderName = "dc-create-scripts"
$artifactsDir = (Join-Path $PSScriptRoot "artifacts" $artifactsFolderName)
$containerName = $artifactsFolderName
# Create container if it doesn't exist
if(-not (Get-AzStorageContainer -Context $storageAccount.Context | Where-Object { $_.Name -eq "$containerName" })){
  Write-Host -ForegroundColor DarkCyan " - Creating container '$containerName' in storage account '$storageAccountName'"
  $_ = New-AzStorageContainer -Name $containerName -Context $storageAccount.Context;
}
$blobs = @(Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context)
$numBlobs = $blobs.Length
if($numBlobs -gt 0){
  Write-Host -ForegroundColor DarkCyan " - Deleting $numBlobs blobs aready in container '$containerName'"
  $blobs | ForEach-Object {Remove-AzStorageBlob -Blob $_.Name -Container $containerName -Context $storageAccount.Context -Force}
  while($numBlobs -gt 0){
    Write-Host -ForegroundColor DarkCyan " - Waiting for deletion of $numBlobs remaining blobs"
    Start-Sleep -Seconds 10
    $numBlobs = (Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context).Length
  }
}

# Upload ZIP file with artifacts
Write-Host -ForegroundColor DarkCyan "Uploading artifacts to storage..."
$zipFileName = "dc-create.zip"
$zipFilePath = (Join-Path $artifactsDir $zipFileName )
Write-Host -ForegroundColor DarkCyan " - Uploading '$zipFilePath' to container '$containerName'"
$_ = Set-AzStorageBlobContent -File $zipFilePath -Container $containerName -Context $storageAccount.Context;
if ($?) {
  Write-Host -ForegroundColor DarkGreen " [o] Succeeded"
} else {
  Write-Host -ForegroundColor DarkRed " [x] Failed!"
}

# === Deploying DC from template ====
Write-Host -ForegroundColor DarkCyan "Deploying DC from template..."

# Get SAS token
Write-Host -ForegroundColor DarkCyan " - obtaining SAS token..."
$artifactLocation = "https://$storageAccountName.blob.core.windows.net/$containerName/$zipFileName";
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $storageAccountSubscription -resourceGroup $storageAccountRg -accountName $storageAccountName

# Retrieve passwords from the keyvault
Write-Host -ForegroundColor DarkCyan " - creating/retrieving user passwords..."
$dcAdminUsername = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dcAdminUsername -defaultValue "sre$($config.dsg.id)admin".ToLower()
$dcAdminPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dcAdminPassword

# Deploy template
$templateName = "dc-master-template"
Write-Host -ForegroundColor DarkCyan " - deploying template $templateName..."
$netbiosNameMaxLength = 15
if($config.dsg.domain.netbiosName.length -gt $netbiosNameMaxLength) {
  throw "NetBIOS name must be no more than 15 characters long. '$($config.dsg.domain.netbiosName)' is $($config.dsg.domain.netbiosName.length) characters long."
}
$params = @{
  "DC Name" = $config.dsg.dc.vmName
  "SRE ID" = $config.dsg.id
  "VM Size" = $config.dsg.dc.vmSize
  "IP Address" = $config.dsg.dc.ip
  "Administrator User" = $dcAdminUsername
  "Administrator Password" = (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force)
  "Virtual Network Name" = $config.dsg.network.vnet.name
  "Virtual Network Resource Group" = $config.dsg.network.vnet.rg
  "Virtual Network Subnet" = $config.dsg.network.subnets.identity.name
  "Artifacts Location" = $artifactLocation
  "Artifacts Location SAS Token" = (ConvertTo-SecureString $artifactSasToken -AsPlainText -Force)
  "Domain Name" = $config.dsg.domain.fqdn
  "NetBIOS Name" = $config.dsg.domain.netbiosName
}
$_ = New-AzResourceGroup -Name $config.dsg.dc.rg -Location $config.dsg.location -Force
New-AzResourceGroupDeployment -ResourceGroupName $config.dsg.dc.rg -TemplateFile $(Join-Path $PSScriptRoot "$($templateName).json") @params -Verbose -DeploymentDebugLogLevel ResponseContent
$result = $?
LogTemplateOutput -ResourceGroupName $config.dsg.dc.rg -DeploymentName $templateName
if ($result) {
  Write-Host -ForegroundColor DarkGreen " [o] Template deployment succeeded"
} else {
  Write-Host -ForegroundColor DarkRed " [x] Template deployment failed!"
}

# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;

