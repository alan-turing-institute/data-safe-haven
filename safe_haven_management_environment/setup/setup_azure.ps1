param([string] $SubscriptionId = "", 
        [string] $vaultName = "shmvault")


# Set the subscriptionID
Set-AzContext -SubscriptionId $SubscriptionId

# Create Resource Groups
New-AzResourceGroup -Name RG_SHM_VNET -Location uksouth
New-AzResourceGroup -Name RG_SHM_DC -Location uksouth
New-AzResourceGroup -Name RG_SHM_NPS -Location uksouth
New-AzResourceGroup -Name RG_SHM_SECRETS -Location uksouth


# Create a keyvault
New-AzKeyVault -Name 'shmvault' -ResourceGroupName RG_SHM_VNET -Location uksouth

# Generate certificates
$cwd = Get-Location
Set-Location -Path ../scripts/local/ -PassThru
sh generate-root-cert.sh
Set-Location -Path $cwd -PassThru

# ./setup_azure.ps1 -SubscriptionId "ff4b0757-0eb8-4e76-a53d-4065421633a6"
# ./setup_azure.ps1 -SubscriptionId "a570a7a2-8632-4a2f-aa10-d7fe37eca122" -vaultName "shmvault"

