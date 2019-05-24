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

# VM1
$secretvalue = ConvertTo-SecureString (New-Password) -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $vaultName -Name 'SHMDC1' -SecretValue $secretvalue
# VM2
$secretvalue = ConvertTo-SecureString (New-Password) -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $vaultName -Name 'SHMDC2' -SecretValue $secretvalue
# VM3
$secretvalue = ConvertTo-SecureString (New-Password) -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName $vaultName -Name 'NPS' -SecretValue $secretvalue

# To retrieve keys
# (Get-AzKeyVaultSecret -vaultName "Contosokeyvault" -name "ExamplePassword").SecretValueText

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

    
# TO RUN THIS SCRIPT (second is my personal subscription)
# ./setup_azure.ps1 -SubscriptionId "ff4b0757-0eb8-4e76-a53d-4065421633a6"
# ./setup_azure.ps1 -SubscriptionId "a570a7a2-8632-4a2f-aa10-d7fe37eca122" -vaultName "shmvault"

