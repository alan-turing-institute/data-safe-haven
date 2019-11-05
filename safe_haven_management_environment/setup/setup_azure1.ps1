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
# Fetch DC admin username (or create if not present)
$dcAdminUsername = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.dcAdminUsername).SecretValueText;
if ($null -eq $dcAdminPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.dcAdminUsername -SecretValue $newPassword;
  $dcAdminUsername = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.dcAdminUsername ).SecretValueText;
}
# Fetch DC admin user password (or create if not present)
$dcAdminPassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.dcAdminPassword).SecretValueText;
if ($null -eq $dcAdminPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.dcAdminPassword -SecretValue $newPassword;
  $dcAdminPassword = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.dcAdminPassword ).SecretValueText;
}
# Fetch DC safe mode password (or create if not present)
$dcSafemodePassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.dcSafemodePassword).SecretValueText;
if ($null -eq $dcSafemodePassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.dcSafemodePassword -SecretValue $newPassword;
  $dcSafemodePassword  = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.dcSafemodePassword ).SecretValueText
}

$vpnClientCertificate = (Get-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertificate).Certificate
$vpnCaCertificate = (Get-AzKeyVaultCertificate -vaultName $config.keyVault.name -name $config.keyVault.secretNames.vpnCaCertificate).Certificate
$vpnCaCertificatePlain = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.vpnCaCertificatePlain).SecretValueText

# Define cert folder outside of conditional cert creation to ensure cleanup on nest run if code exits with error during cert creation 
$certFolderPathName = "certs"
$certFolderPath = "$PSScriptRoot/$certFolderPathName"

if($vpnClientCertificate -And $vpnCaCertificate -And $vpnCaCertificatePlain){
  Write-Host "Both CA and Client certificates already exist in KeyVault. Skipping certificate creation."
} else {
  # Generate certificates
  Write-Host "===Started creating certificates==="
  # Fetch VPN Client certificate password (or create if not present)
  $vpnClientCertPassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.vpnClientCertPassword).SecretValueText;
  if ($null -eq $vpnClientCertPassword) {
    # Create password locally but round trip via KeyVault to ensure it is successfully stored
    $newPassword = New-Password;
    $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
    $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.vpnClientCertPassword -SecretValue $newPassword;
    $vpnClientCertPassword  = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnClientCertPassword ).SecretValueText
  }
  # Fetch VPN CA certificate password (or create if not present)
  $vpnCaCertPassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.vpnCaCertPassword).SecretValueText;
  if ($null -eq $vpnCaCertPassword) {
    # Create password locally but round trip via KeyVault to ensure it is successfully stored
    $newPassword = New-Password;
    $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
    $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name  $config.keyVault.secretNames.vpnCaCertPassword -SecretValue $newPassword;
    $vpnCaCertPassword  = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertPassword ).SecretValueText
  }

  # Generate keys and certificates
  $caValidityDays = 2196 # 5 years
  $clientValidityDays = 732 # 2 years
  $_ = new-item -Path $PSScriptRoot -Name $certFolderPathName -ItemType directory -Force
  $caStem = "SHM-P2S-$($config.id)-CA"
  $clientStem = "SHM-P2S-$($config.id)-Client"
  # Create self-signed CA certificate
  openssl req -subj "/CN=$caStem" -new -newkey rsa:2048 -sha256 -days $caValidityDays -nodes -x509 -keyout $certFolderPath/$caStem.key -out $certFolderPath/$caStem.crt
  # Create Client key
  openssl genrsa -out $certFolderPath/$clientStem.key 2048
  # Create Client CSR
  openssl req -new -sha256 -key $certFolderPath/$clientStem.key -subj "/CN=$clientStem" -out $certFolderPath/$clientStem.csr
  # Sign Client cert
  openssl x509 -req -in $certFolderPath/$clientStem.csr -CA $certFolderPath/$caStem.crt -CAkey $certFolderPath/$caStem.key -CAcreateserial -out $certFolderPath/$clientStem.crt -days $clientValidityDays -sha256
  # Create Client private key + signed cert bundle
  openssl pkcs12 -in "$certFolderPath/$clientStem.crt" -inkey "$certFolderPath/$clientStem.key" -certfile $certFolderPath/$caStem.crt -export -out "$certFolderPath/$clientStem.pfx" -password "pass:$vpnClientCertPassword"
  # Create CA private key + signed cert bundle
  openssl pkcs12 -in "$certFolderPath/$caStem.crt" -inkey "$certFolderPath/$caStem.key" -export -out "$certFolderPath/$caStem.pfx" -password "pass:$vpnCaCertPassword"
  Write-Host "===Completed creating certificates==="

  # The certificate only seems to work for the VNET Gateway if the first and last line are removed and it is passed as a single string with white space removed
  $vpnCaCertificatePlain = $(Get-Content -Path "$certFolderPath/$caStem.crt") | Select-Object -Skip 1 | Select-Object -SkipLast 1
  $vpnCaCertificatePlain = [string]$vpnCaCertificatePlain
  $vpnCaCertificatePlain = $vpnCaCertificatePlain.replace(" ", "")

  # Store CA cert in KeyVault
  Write-Host "Storing CA cert in '$($config.keyVault.name)' KeyVault as secret $($config.keyVault.secretNames.vpnCaCertificatePlain) (no private key)"
  $_ = Set-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificatePlain -SecretValue (ConvertTo-SecureString $vpnCaCertificatePlain -AsPlainText -Force);
  $vpnCaCertificatePlain = (Get-AzKeyVaultSecret -VaultName $config.keyVault.name -Name $config.keyVault.secretNames.vpnCaCertificatePlain ).SecretValueText;

  # Store CA key + cert bundle in KeyVault
  Write-Host "Storing CA private key + cert bundle in '$($config.keyVault.name)' KeyVault as certificate $($config.keyVault.secretNames.vpnCaCertificate) (includes private key)"
  $_ = Import-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyvault.secretNames.vpnCaCertificate -FilePath "$certFolderPath/$caStem.pfx" -Password (ConvertTo-SecureString $vpnCaCertPassword -AsPlainText -Force);
  
  # Store Client key + cert bundle in KeyVault
  Write-Host "Storing Client private key + cert bundle in '$($config.keyVault.name)' KeyVault as certificate $($config.keyVault.secretNames.vpnClientCertificate) (includes private key)"
  $_ = Import-AzKeyVaultCertificate -VaultName $config.keyVault.name -Name $config.keyvault.secretNames.vpnClientCertificate -FilePath "$certFolderPath/$clientStem.pfx" -Password (ConvertTo-SecureString $vpnClientCertPassword -AsPlainText -Force);

}
# Delete local copies of certificates and private keys
Get-ChildItem $certFolderPath -Recurse | Remove-Item -Recurse

# Setup storage account and upload artifacts
$storageAccountRg = $config.storage.artifacts.rg;
$storageAccountName = $config.storage.artifacts.accountName;
$storageAccountLocation = $config.location;
$_ = New-AzResourceGroup -Name $storageAccountRg -Location $storageAccountLocation -Force
$storageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -ErrorVariable notExists -ErrorAction SilentlyContinue
if($notExists) {
  Write-Host " - Creating storage account '$storageAccountName'"
  $storageAccount = New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $storageAccountRg -Location $storageAccountLocation -SkuName "Standard_LRS" -Kind "StorageV2"
}
# Create blob storage containers
"dsc", "scripts" | ForEach-Object {
  $containerName = $_
  if(-not (Get-AzStorageContainer -Context $storageAccount.Context | Where-Object { $_.Name -eq "$containerName" })){
    Write-Host " - Creating container '$containerName' in storage account '$storageAccountName'"
    $_ = New-AzStorageContainer -Name $containerName -Context $storageAccount.Context;
  }
}
# Create file storage shares
"sqlserver" | ForEach-Object {
  $shareName = $_
  if(-not (Get-AzStorageShare -Context $storageAccount.Context | Where-Object { $_.Name -eq "$shareName" })){
    Write-Host " - Creating share '$shareName' in storage account '$storageAccountName'"
    $_ = New-AzStorageShare -Name $shareName -Context $storageAccount.Context;
  }
}

# Upload files
Set-AzStorageBlobContent -Container "dsc" -Context $storageAccount.Context -File "$PSScriptRoot/../dsc/shmdc1/CreateADPDC.zip" -Force
Set-AzStorageBlobContent -Container "dsc" -Context $storageAccount.Context -File "$PSScriptRoot/../dsc/shmdc2/CreateADBDC.zip" -Force
Set-AzStorageBlobContent -Container "scripts" -Context $storageAccount.Context -File "$PSScriptRoot/../scripts/dc/SHM_DC.zip" -Force
Set-AzStorageBlobContent -Container "scripts" -Context $storageAccount.Context -File "$PSScriptRoot/../scripts/nps/SHM_NPS.zip" -Force

# URI to Azure File copy does not support 302 redirect, so get the latest working endpoint redirected from "https://go.microsoft.com/fwlink/?linkid=853017"
Start-AzStorageFileCopy -AbsoluteUri "https://download.microsoft.com/download/5/E/9/5E9B18CC-8FD5-467E-B5BF-BADE39C51F73/SQLServer2017-SSEI-Expr.exe" -DestShareName "sqlserver" -DestFilePath "SQLServer2017-SSEI-Expr.exe" -DestContext $storageAccount.Context -Force
# URI to Azure File copy does not support 302 redirect, so get the latest working endpoint redirected from "https://go.microsoft.com/fwlink/?linkid=2088649"
Start-AzStorageFileCopy -AbsoluteUri "https://download.microsoft.com/download/5/4/E/54EC1AD8-042C-4CA3-85AB-BA307CF73710/SSMS-Setup-ENU.exe" -DestShareName "sqlserver" -DestFilePath "SSMS-Setup-ENU.exe" -DestContext $storageAccount.Context -Force

# Get SAS token
$artifactLocation = "https://" + $config.storage.artifacts.accountName + ".blob.core.windows.net";

$artifactSasToken = (New-AccountSasToken -subscriptionName $config.subscriptionName -resourceGroup $config.storage.artifacts.rg `
  -accountName $config.storage.artifacts.accountName -service Blob,File -resourceType Service,Container,Object `
  -permission "rl" -validityHours 2);

$vnetCreateParams = @{
 "Virtual_Network_Name" = $config.network.vnet.name
 "P2S_VPN_Certificate" = $vpnCaCertificatePlain
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

New-AzResourceGroup -Name $config.network.vnet.rg -Location $config.location -Force
New-AzResourceGroupDeployment -resourcegroupname $config.network.vnet.rg `
        -templatefile "$PSScriptRoot/../arm_templates/shmvnet/shmvnet-template.json" `
        @vnetCreateParams -Verbose;

# Deploy the shmdc-template
$netbiosNameMaxLength = 15
if($config.domain.netbiosName.length -gt $netbiosNameMaxLength) {
    throw "Netbios name must be no more than 15 characters long. '$($config.domain.netbiosName)' is $($config.domain.netbiosName.length) characters long."
}
New-AzResourceGroup -Name $config.dc.rg  -Location $config.location -Force
New-AzResourceGroupDeployment -resourcegroupname $config.dc.rg `
        -templatefile "$PSScriptRoot/../arm_templates/shmdc/shmdc-template.json"`
        -Administrator_User $dcAdminUsername `
        -Administrator_Password (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force)`
        -SafeMode_Password (ConvertTo-SecureString $dcSafemodePassword -AsPlainText -Force)`
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
