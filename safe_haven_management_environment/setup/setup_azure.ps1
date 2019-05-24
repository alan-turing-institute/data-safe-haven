param([string] $SubscriptionId = "", 
        [string] $vaultName = "shmvault")


# Set the subscriptionID
Set-AzContext -SubscriptionId $SubscriptionId

# Create Resource Groups
New-AzResourceGroup -Name RG_SHM_VNET -Location uksouth
New-AzResourceGroup -Name RG_SHM_DC -Location uksouth
New-AzResourceGroup -Name RG_SHM_NPS -Location uksouth
New-AzResourceGroup -Name RG_SHM_SECRETS -Location uksouth
New-AzResourceGroup -Name RG_SHM_RESOURCES -Location uksouth

# Create a keyvault and generate passwords
New-AzKeyVault -Name $vaultName -ResourceGroupName RG_SHM_SECRETS  -Location uksouth

Import-Module ../scripts/local/GeneratePassword.psm1

# VM pass
$secretvalue = ConvertTo-SecureString (New-Password) -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $vaultName -Name 'dcpass' -SecretValue $secretvalue
# safemode pass
$secretvalue = ConvertTo-SecureString (New-Password) -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $vaultName -Name 'safemodepass' -SecretValue $secretvalue
# VM3
$secretvalue = ConvertTo-SecureString (New-Password) -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $vaultName -Name 'NPS' -SecretValue $secretvalue


# Generate certificates
$cwd = Get-Location
Set-Location -Path ../scripts/local/ -PassThru
sh generate-root-cert.sh
Set-Location -Path $cwd -PassThru

# Setup resources
$storageAccount = New-AzStorageAccount -ResourceGroupName RG_SHM_RESOURCES -Name "shmfiles" -Location uksouth -SkuName "Standard_LRS"
new-AzStoragecontainer -Name "dsc" -Context $storageAccount.Context 
New-AzStorageShare -Name 'scripts' -Context $storageAccount.Context
New-AzStorageShare -Name 'sqlserver' -Context $storageAccount.Context

# Create directories in file share
New-AzStorageDirectory -Context $storageAccount.Context -ShareName "scripts" -Path "dc"
New-AzStorageDirectory -Context $storageAccount.Context -ShareName "scripts" -Path "nps"


# Upload files
Get-ChildItem -File "../dsc/shmdc1/" -Recurse | Set-AzStorageBlobContent -Container "dsc" -Context $storageAccount.Context

Get-ChildItem -File "../scripts/dc/" -Recurse | Set-AzStorageFileContent -ShareName "scripts" -Path "dc/" -Context $storageAccount.Context 
Get-ChildItem -File "../scripts/nps/" -Recurse | Set-AzStorageFileContent -ShareName "scripts" -Path "nps/" -Context $storageAccount.Context 

    
# Download executables from microsoft
New-Item -Name "temp" -ItemType "directory"
Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=853017" -OutFile "temp/SQLServer2017-SSEI-Expr.exe"
Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2088649" -OutFile "temp/SSMS-Setup-ENU.exe"

# Upload executables to fileshare
Get-ChildItem -File "temp/" -Recurse | Set-AzStorageFileContent -ShareName "sqlserver" -Context $storageAccount.Context 

# Tidy up - Delete the local executable files
Remove-Item –path 'temp/' –recurse




# Run template files
# Deploy the shmvnet template
$cert = $(Get-Content -Path "../scripts/local/out/certs/caCert.pem") | Select-Object -Skip 1 | Select-Object -SkipLast 1
New-AzResourceGroupDeployment -resourcegroupname "RG_SHM_VNET" -templatefile "../arm_templates/shmvnet/shmvnet-template.json" -P2S_VPN_Certifciate [string]$cert -Virtual_Network_Name "SHM_VNET1"

# Deploy the shmdc-template
New-AzResourceGroupDeployment -resourcegroupname "RG_SHM_DC" -templatefile "../arm_templates/shmdc/shmdc-template.json"  `
        -Administrator_User "atiadmin"
        -Administrator_Password (Get-AzKeyVaultSecret -vaultName $vaultName -name "dcpass").SecretValueText
        -SafeMode_Password (Get-AzKeyVaultSecret -vaultName $vaultName -name "safemodepass").SecretValueText
        -Virtual_Network_Resource_Group "RG_SHM_VNET"
        -Artifacts_Location ""
        -Artifacts_Location_SAS_Token ""
        -Domain_Name ""


# TO RUN THIS SCRIPT (second is my personal subscription)
# ./setup_azure.ps1 -SubscriptionId "ff4b0757-0eb8-4e76-a53d-4065421633a6"
# ./setup_azure.ps1 -SubscriptionId "a570a7a2-8632-4a2f-aa10-d7fe37eca122" -vaultName "shmvault"