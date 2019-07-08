param(
  [string]$uri,
  [string]$sasToken
)



Write-Host $uri;
Write-Host $sasToken;

Invoke-WebRequest -Uri $uri -OutFile C:/Scripts/SHM_DC.zip


# azcopy copy

# $StorageContext = (New-AzureStorageContext $accountName -SasToken $sasToken)

# Get-AzureStorageBlobContent -Container 'scripts' -Blob 'SHM_DC.zip' -Destination 'C:/Scripts/SHM_DC.zip' -Context $storageAccountContext -Force

# # The cmdkey utility is a command-line (rather than PowerShell) tool. We use Invoke-Expression to allow us to 
# # consume the appropriate values from the storage account variables. The value given to the add parameter of the
# # cmdkey utility is the host address for the storage account, <storage-account>.file.core.windows.net for Azure 
# # Public Regions. $storageAccount.Context.FileEndpoint is used because non-Public Azure regions, such as sovereign 
# # clouds or Azure Stack deployments, will have different hosts for Azure file shares (and other storage resources).
# Invoke-Expression -Command ("cmdkey /add:dsgtestbartifacts.file.core.windows.net /user:Azure\dsgtestbartifacts /pass:OFy1QJKpPOLVV13RfvlxRelV3wkEg2tH3LQM7CGzEfpLuIyiqSVeunppWt22OSA3AIXHu0PwnxwiwnAZjCd4/A==
# net use Z: \\dsgtestbartifacts.file.core.windows.net\scripts /persistent:Yes")

# Expand-Archive C:/Scripts/SHM_DC.zip -DestinationPath C:\Scripts\

Write-Host (Get-ChildItem -Path C:\Scripts\)

