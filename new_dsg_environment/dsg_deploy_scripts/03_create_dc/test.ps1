param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../GeneratePassword.psm1 -Force
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../GenerateSasToken.psm1 -Force


# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to DSG subscription
$storageAccountSubscription = $config.dsg.subscriptionName
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $storageAccountSubscription;

# Upload artifacts to storage account
$storageAccountLocation = $config.dsg.location
$storageAccountRg = $config.dsg.storage.artifacts.rg
$storageAccountName = $config.dsg.storage.artifacts.accountName
# Create storage account if is doesn't exist
New-AzResourceGroup -Name $storageAccountRg -Location $storageAccountLocation -Force
$storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -ErrorVariable notExists -ErrorAction SilentlyContinue
if($notExists) {
  Write-Host " - Creating storage account '$storageAccountName'"
  $storageAccount = New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -Location $storageAccountLocation -SkuName "Standard_GRS" -Kind "StorageV2"
}
$artifactsDir = (Join-Path $PSScriptRoot "artifacts")
$containerName = "$($config.dsg.shortName)-dc-scripts"
# Create container if it doesn't exist
if(-not (Get-AzStorageContainer -Context $storageAccount.Context | Where-Object { $_.Name -eq "$containerName" })){
  Write-Host " - Creating container '$containerName' in storage account '$storageAccountName'"
  New-AzStorageContainer -Name $containerName -Context $storageAccount.Context;
}
$blobs = Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context
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

$files = Get-ChildItem -File $artifactsDir -Recurse
$numFiles = $files.Length
Write-Host " - Uploading $numFiles files to container '$containerName'"
$blobs = $files | Set-AzStorageBlobContent -Container $containerName -Context $storageAccount.Context
$blobs = Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context
$blobNames = $blobs | ForEach-Object{$_.Name}

$sasToken = New-AccountSasToken $storageAccountSubscription $storageAccountRg $storageAccountName  Blob,File Service,Container,Object "rl" 
# Download artifacts
$sasContext = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $sasToken
$numFiles = $blobNames.Length
$remoteDir = "~/$containerName"
Remove-Item "$remoteDir" -Recurse
if(-not (Test-Path -Path $remoteDir )){
    New-Item -ItemType directory -Path $remoteDir
}
Write-Host " - Downloading $numFiles files to '$remoteDir'"
$artifactBlobs = $blobNames | ForEach-Object{Get-AzStorageBlobContent -Blob $_ -Container $containerName -Destination "$remoteDir/$_Name" -Context $sasContext}

return $artifactBlobs

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;