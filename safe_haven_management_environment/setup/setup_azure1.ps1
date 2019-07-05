param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$shmId
)


Import-Module Az
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/DsgConfig.psm1 -Force

# Get DSG config
$config = Get-ShmFullConfig($shmId)


# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.subscriptionName;


# # Create Resource Groups
New-AzResourceGroup -Name $config.network.vnet.rg -Location $config.location
New-AzResourceGroup -Name $config.dc.rg  -Location $config.location
New-AzResourceGroup -Name $config.nps.rg -Location $config.location
New-AzResourceGroup -Name RG_DSG_SECRETS -Location $config.location
New-AzResourceGroup -Name $config.storage.artifacts.rg  -Location $config.location

# # Create a keyvault and generate passwords
New-AzKeyVault -Name $vaultName -ResourceGroupName RG_SHM_SECRETS  -Location uksouth


# # VM pass
# $secretvalue = ConvertTo-SecureString (New-Password) -AsPlainText -Force
# Set-AzKeyVaultSecret -VaultName $vaultName -Name 'dcpass' -SecretValue $secretvalue
# # safemode pass
# $secretvalue = ConvertTo-SecureString (New-Password) -AsPlainText -Force
# Set-AzKeyVaultSecret -VaultName $vaultName -Name 'safemodepass' -SecretValue $secretvalue

# # Generate certificates
# $cwd = Get-Location
# Set-Location -Path ../scripts/local/ -PassThru
# sh generate-root-cert.sh
# Set-Location -Path $cwd -PassThru

# # Setup resources
# $storageAccount = New-AzStorageAccount -ResourceGroupName RG_SHM_RESOURCES -Name "shmfiles" -Location uksouth -SkuName "Standard_LRS"
# new-AzStoragecontainer -Name "dsc" -Context $storageAccount.Context 
# New-AzStorageShare -Name 'scripts' -Context $storageAccount.Context
# New-AzStorageShare -Name 'sqlserver' -Context $storageAccount.Context

# # Create directories in file share
# New-AzStorageDirectory -Context $storageAccount.Context -ShareName "scripts" -Path "dc"
# New-AzStorageDirectory -Context $storageAccount.Context -ShareName "scripts" -Path "nps"

# # Upload files
# Get-ChildItem -File "../dsc/shmdc1/" -Recurse | Set-AzStorageBlobContent -Container "dsc" -Context $storageAccount.Context
# Get-ChildItem -File "../dsc/shmdc2/" -Recurse | Set-AzStorageBlobContent -Container "dsc" -Context $storageAccount.Context
# Get-ChildItem -File "../scripts/dc/" -Recurse | Set-AzStorageFileContent -ShareName "scripts" -Path "dc/" -Context $storageAccount.Context 
# Get-ChildItem -File "../scripts/nps/" -Recurse | Set-AzStorageFileContent -ShareName "scripts" -Path "nps/" -Context $storageAccount.Context 

# # Download executables from microsoft
# New-Item -Name "temp" -ItemType "directory"
# Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=853017" -OutFile "temp/SQLServer2017-SSEI-Expr.exe"
# Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2088649" -OutFile "temp/SSMS-Setup-ENU.exe"

# # Upload executables to fileshare
# Get-ChildItem -File "temp/" -Recurse | Set-AzStorageFileContent -ShareName "sqlserver" -Context $storageAccount.Context 
# # Delete the local executable files
# Remove-Item –path 'temp/' –recurse

# # Run template files
# # Deploy the shmvnet template
# # The certificate only seems to works if the first and last line are removed, passed as a single string and white space removed
# $cert = $(Get-Content -Path "../scripts/local/out/certs/caCert.pem") | Select-Object -Skip 1 | Select-Object -SkipLast 1
# $cert = [string]$cert
# $cert = $cert.replace(" ", "")
# New-AzResourceGroupDeployment -resourcegroupname "RG_SHM_VNET" -templatefile "../arm_templates/shmvnet/shmvnet-template.json" -P2S_VPN_Certifciate $cert -Virtual_Network_Name "SHM_VNET1"

# # Deploy the shmdc-template
# New-AzResourceGroupDeployment -resourcegroupname "RG_SHM_DC" -templatefile "../arm_templates/shmdc/shmdc-template.json"`
#         -Administrator_User "atiadmin"`
#         -Administrator_Password (Get-AzKeyVaultSecret -vaultName $vaultName -name "dcpass").SecretValue`
#         -SafeMode_Password (Get-AzKeyVaultSecret -vaultName $vaultName -name "safemodepass").SecretValue`
#         -Virtual_Network_Resource_Group "RG_SHM_VNET"

# Switch back to original subscription
Set-AzContext -Context $prevContext;