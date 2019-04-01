param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../GeneratePassword.psm1 -Force
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../GenerateSasToken.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Set deployment parameters not directly set in config file
$vmSize = "Standard_DS2_v2";

# Fetch admin password (or create if not present)
$adminPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.dc.admin.passwordSecretName).SecretValueText;
if ($null -eq $adminPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.dc.admin.passwordSecretName -SecretValue $newPassword;
  $adminPassword = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.dc.admin.passwordSecretName).SecretValueText;
}
$adminPassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force;

# Get SAS token
$artifactLocation = "https://" + $config.shm.storage.artifacts.accountName + ".blob.core.windows.net";
$currentSubscription = (Get-AzContext).Subscription.Name
Write-Host $currentSubscription 
$artifactSasToken = (New-AccountSasToken -subscriptionName $config.shm.subscriptionName -resourceGroup $config.shm.storage.artifacts.rg `
  -accountName $config.shm.storage.artifacts.accountName -service Blob,File -resourceType Service,Container,Object `
  -permission "rl" -prevSubscription $currentSubscription);
 Write-Host $artifactSasToken.GetType()
$artifactSasToken = (ConvertTo-SecureString $artifactSasToken -AsPlainText -Force);

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

$params = @{
 "DC Name" = $config.dsg.dc.vmName
 "VM Size" = $vmSize
 "IP Address" = $config.dsg.dc.ip
 "Administrator User" = $config.dsg.dc.admin.username
 "Administrator Password" = $adminPassword
 "Virtual Network Name" = $config.dsg.network.vnet.name
 "Virtual Network Resource Group" = $config.dsg.network.vnet.rg
 "Virtual Network Subnet" = $config.dsg.network.subnets.identity.name
 "Artifacts Location" = $artifactLocation
 "Artifacts Location SAS Token" = $artifactSasToken
 "Domain Name" = $config.dsg.domain.fqdn
}

$templatePath = Join-Path $PSScriptRoot "dc-master-template.json"

Write-Output ($params | ConvertTo-JSON -depth 10)

New-AzResourceGroup -Name $config.dsg.dc.rg -Location $config.dsg.location
New-AzResourceGroupDeployment -ResourceGroupName $config.dsg.dc.rg `
  -TemplateFile $templatePath @params -Verbose


# Switch back to original subscription
Set-AzContext -Context $prevContext;
