param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/GeneratePassword.psm1 -Force
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/GenerateSasToken.psm1 -Force

# Get DSG config
$config = Get-ShmFullConfig($shmId)

# Fetch DC root user password (or create if not present)
$DCRootPassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.dc).SecretValueText;
if ($null -eq $DCRootPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.dc -SecretValue $newPassword;
  $DCRootPassword = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.dc ).SecretValueText;
}

# Fetch DC root user password (or create if not present)
$DCSafemodePassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.safemode).SecretValueText;
if ($null -eq $DCSafemodePassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.safemode -SecretValue $newPassword;
  $DCSafemodePassword  = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.safemode ).SecretValueText
}

# Generate certificates
$cwd = Get-Location
Set-Location -Path ../scripts/local/ -PassThru
sh generate-root-cert.sh
Set-Location -Path $cwd -PassThru


# Import-AzureKeyVaultCertificate -VaultName $config.keyVault.name `
#            -Name $("DSG-P2S-" + $shmId) `
#            -FilePath '../scripts/local/out/certs/client.pfx' `
#            -Password $securepfxpwd;
           

# Setup resources
$storageAccount = New-AzStorageAccount -ResourceGroupName $config.storage.artifacts.rg -Name $config.storage.artifacts.accountName -Location $config.location -SkuName "Standard_LRS"
new-AzStoragecontainer -Name "dsc" -Context $storageAccount.Context 
new-AzStoragecontainer -Name "scripts" -Context $storageAccount.Context 

New-AzStorageShare -Name 'scripts' -Context $storageAccount.Context
New-AzStorageShare -Name 'sqlserver' -Context $storageAccount.Context

# Create directories in file share
# New-AzStorageDirectory -Context $storageAccount.Context -ShareName "scripts" -Path "dc"
New-AzStorageDirectory -Context $storageAccount.Context -ShareName "scripts" -Path "nps"

# Upload files
Get-ChildItem -File "../dsc/shmdc1/" -Recurse | Set-AzStorageBlobContent -Container "dsc" -Context $storageAccount.Context
Get-ChildItem -File "../dsc/shmdc2/" -Recurse | Set-AzStorageBlobContent -Container "dsc" -Context $storageAccount.Context
Set-AzStorageBlobContent -Container "scripts" -Context $storageAccount.Context -File "../scripts/dc/SHM_DC.zip"
Set-AzStorageBlobContent -Container "scripts" -Context $storageAccount.Context -File "../scripts/nps/SHM_NPS.zip"

# Get-ChildItem -File "../scripts/dc/" -Recurse | Set-AzStorageFileContent -ShareName "scripts" -Path "dc/" -Context $storageAccount.Context 
Get-ChildItem -File "../scripts/nps/" -Recurse | Set-AzStorageFileContent -ShareName "scripts" -Path "nps/" -Context $storageAccount.Context 

# Download executables from microsoft
New-Item -Name "temp" -ItemType "directory"
Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=853017" -OutFile "temp/SQLServer2017-SSEI-Expr.exe"
Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2088649" -OutFile "temp/SSMS-Setup-ENU.exe"

# Upload executables to fileshare
Get-ChildItem -File "temp/" -Recurse | Set-AzStorageFileContent -ShareName "sqlserver" -Context $storageAccount.Context 

# Delete the local executable files
Remove-Item –path 'temp/' –recurse

# Get SAS token
$artifactLocation = "https://" + $config.storage.artifacts.accountName + ".blob.core.windows.net";
$currentSubscription = $config.subscriptionName;
$artifactSasToken = (New-AccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg `
  -accountName $config.storage.artifacts.accountName -service Blob,File -resourceType Service,Container,Object `
  -permission "rl" -prevSubscription $currentSubscription);
 
# Run template files
# Deploy the shmvnet template
# The certificate only seems to works if the first and last line are removed, passed as a single string and white space removed
$cert = $(Get-Content -Path "../scripts/local/out/certs/caCert.pem") | Select-Object -Skip 1 | Select-Object -SkipLast 1
$cert = [string]$cert
$cert = $cert.replace(" ", "")

New-AzResourceGroup -Name $config.network.vnet.rg -Location $config.location
New-AzResourceGroupDeployment -resourcegroupname $config.network.vnet.rg `
        -templatefile "../arm_templates/shmvnet/shmvnet-template.json" `
        -P2S_VPN_Certifciate $cert `
        -Virtual_Network_Name "SHM_VNET1";

# Deploy the shmdc-template

New-AzResourceGroup -Name $config.dc.rg  -Location $config.location
New-AzResourceGroupDeployment -resourcegroupname $config.dc.rg`
        -templatefile "../arm_templates/shmdc/shmdc-template.json"`
        -Administrator_User "atiadmin"`
        -Administrator_Password (ConvertTo-SecureString $DCRootPassword -AsPlainText -Force)`
        -SafeMode_Password (ConvertTo-SecureString $DCSafemodePassword -AsPlainText -Force)`
        -Virtual_Network_Resource_Group $config.network.vnet.rg `
        -Artifacts_Location $artifactLocation `
        -Artifacts_Location_SAS_Token (ConvertTo-SecureString $artifactSasToken -AsPlainText -Force)`
        -Domain_Name $config.domain.fqdn;
        
# Switch back to original subscription
Set-AzContext -Context $prevContext;