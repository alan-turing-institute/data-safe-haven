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

# Temporarily switch to SHM subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.subscriptionName;

# Set VM Default Size
$vmSize = "Standard_DS2_v2"
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
# NB. Windows uses docker-compose.exe so check for this first, falling back to docker-compose
if ((Get-Command "docker-compose.exe" -ErrorAction SilentlyContinue) -ne $null) {
  Write-Host "Using docker-compose.exe"
  docker-compose.exe -f ./build/docker-compose.certs.yml up
} else {
  Write-Host "Using docker-compose"
  docker-compose -f ./build/docker-compose.certs.yml up
}
Set-Location -Path $cwd -PassThru

# Setup resources
New-AzResourceGroup -Name $config.storage.artifacts.rg  -Location $config.location
$storageAccount = New-AzStorageAccount -ResourceGroupName $config.storage.artifacts.rg -Name $config.storage.artifacts.accountName -Location $config.location -SkuName "Standard_LRS"
new-AzStoragecontainer -Name "dsc" -Context $storageAccount.Context
new-AzStoragecontainer -Name "scripts" -Context $storageAccount.Context

New-AzStorageShare -Name 'scripts' -Context $storageAccount.Context
New-AzStorageShare -Name 'sqlserver' -Context $storageAccount.Context

# Create directories in file share
# New-AzStorageDirectory -Context $storageAccount.Context -ShareName "scripts" -Path "dc"
New-AzStorageDirectory -Context $storageAccount.Context -ShareName "scripts" -Path "nps"

# Upload files
Set-AzStorageBlobContent -Container "dsc" -Context $storageAccount.Context -File "../dsc/shmdc1/CreateADPDC.zip"
Set-AzStorageBlobContent -Container "dsc" -Context $storageAccount.Context -File "../dsc/shmdc2/CreateADBDC.zip"
Set-AzStorageBlobContent -Container "scripts" -Context $storageAccount.Context -File "../scripts/dc/SHM_DC.zip"
Set-AzStorageBlobContent -Container "scripts" -Context $storageAccount.Context -File "../scripts/nps/SHM_NPS.zip"

# Get-ChildItem -File "../scripts/dc/" -Recurse | Set-AzStorageFileContent -ShareName "scripts" -Path "dc/" -Context $storageAccount.Context
Get-ChildItem -File "../scripts/nps/" -Recurse | Set-AzStorageFileContent -ShareName "scripts" -Path "nps/" -Context $storageAccount.Context

# Create folder for downloaded executables from Microsoft
if (-Not (Test-Path "temp")) {
  New-Item -Name "temp" -ItemType "directory"
}
# Download SQLServer2017
$outputFile = "temp/SQLServer2017-SSEI-Expr.exe"
if (-Not (Test-Path $outputFile -PathType Leaf)) {
  Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=853017" -OutFile $outputFile
}
# Download SSMS-Setup
$outputFile = "temp/SSMS-Setup-ENU.exe"
if (-Not (Test-Path $outputFile -PathType Leaf)) {
  Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2088649" -OutFile $outputFile
}

# Upload executables to fileshare
Get-ChildItem -File "temp/" -Recurse | Set-AzStorageFileContent -ShareName "sqlserver" -Context $storageAccount.Context

# Delete the local executable files
Remove-Item –path 'temp/' –recurse

# Get SAS token
$artifactLocation = "https://" + $config.storage.artifacts.accountName + ".blob.core.windows.net";

$artifactSasToken = (New-AccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg `
  -accountName $config.storage.artifacts.accountName -service Blob,File -resourceType Service,Container,Object `
  -permission "rl" -validityHours 2);

# Run template files
# Deploy the shmvnet template
# The certificate only seems to works if the first and last line are removed, passed as a single string and white space removed
$cert = $(Get-Content -Path "../scripts/local/out/certs/caCert.pem") | Select-Object -Skip 1 | Select-Object -SkipLast 1
$cert = [string]$cert
$cert = $cert.replace(" ", "")

$vnetCreateParams = @{
 "Virtual_Network_Name" = $config.network.vnet.name
 "P2S_VPN_Certificate" = $cert
 "VNET_CIDR" = $config.network.vnet.cidr
 "Subnet_Identity_Name" = $config.network.subnets.identity.name
 "Subnet_Identity_CIDR" = $config.network.subnets.identity.cidr
 "Subnet_Web_Name" = $config.network.subnets.web.name
 "Subnet_Web_CIDR" = $config.network.subnets.web.cidr  
 "Subnet_Gateway_Name" = $config.network.subnets.gateway.name
 "Subnet_Gateway_CIDR" = $config.network.subnets.gateway.cidr
 "VNET_DNS1" = $config.dc.ip
 "VNET_DNS2" = $config.dcb.ip
}
New-AzResourceGroup -Name $config.network.vnet.rg -Location $config.location
New-AzResourceGroupDeployment -resourcegroupname $config.network.vnet.rg `
        -templatefile "../arm_templates/shmvnet/shmvnet-template.json" `
        @vnetCreateParams -Verbose;

# Deploy the shmdc-template
$netbiosNameMaxLength = 15
if($config.domain.netbiosName.length -gt $netbiosNameMaxLength) {
    throw "Netbios name must be no more than 15 characters long. '$($config.domain.netbiosName)' is $($config.domain.netbiosName.length) characters long."
}
New-AzResourceGroup -Name $config.dc.rg  -Location $config.location
New-AzResourceGroupDeployment -resourcegroupname $config.dc.rg`
        -templatefile "../arm_templates/shmdc/shmdc-template.json"`
        -Administrator_User "atiadmin"`
        -Administrator_Password (ConvertTo-SecureString $DCRootPassword -AsPlainText -Force)`
        -SafeMode_Password (ConvertTo-SecureString $DCSafemodePassword -AsPlainText -Force)`
        -Virtual_Network_Resource_Group $config.network.vnet.rg `
        -Artifacts_Location $artifactLocation `
        -Artifacts_Location_SAS_Token (ConvertTo-SecureString $artifactSasToken -AsPlainText -Force)`
        -Domain_Name $config.domain.fqdn `
        -Domain_Name_NetBIOS_Name $config.domain.netbiosName `
        -VM_Size $vmSize `
        -Virtual_Network_Name $config.network.vnet.name `
        -Virtual_Network_Subnet $config.network.subnets.identity.name `
        -DC1_VM_Name $config.dc.vmName `
        -DC2_VM_Name $config.dcb.vmName `
        -DC1_Host_Name $config.dc.hostname `
        -DC2_Host_Name $config.dcb.hostname `
        -DC1_IP_Address $config.dc.ip `
        -DC2_IP_Address $config.dcb.ip; 
      

# Switch back to original subscription
Set-AzContext -Context $prevContext;