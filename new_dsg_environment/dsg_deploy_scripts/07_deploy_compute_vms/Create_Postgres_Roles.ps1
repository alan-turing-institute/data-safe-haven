param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter last octet of compute VM IP address (e.g. 160)")]
  [string]$ipLastOctet
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../GeneratePassword.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# Find VM with private IP address matching the provided last octect
## Turn provided last octect into full IP address in the data subnet
$vmIpAddress = ($config.dsg.network.subnets.data.prefix + "." + $ipLastOctet)
Write-Host " - Finding VM with IP $vmIpAddress"
## Get all compute VMs
$computeVms = Get-AzVM -ResourceGroupName $config.dsg.dsvm.rg
## Get the NICs attached to all the compute VMs
$computeVmNicIds = ($computeVms | ForEach-Object{(Get-AzVM -ResourceGroupName $config.dsg.dsvm.rg -Name $_.Name).NetworkProfile.NetworkInterfaces.Id})
$computeVmNics = ($computeVmNicIds | ForEach-Object{Get-AzNetworkInterface -ResourceGroupName $config.dsg.dsvm.rg -Name $_.Split("/")[-1]})
## Filter the NICs to the one matching the desired IP address and get the name of the VM it is attached to
$vmName = ($computeVmNics | Where-Object{$_.IpConfigurations.PrivateIpAddress -match $vmIpAddress})[0].VirtualMachine.Id.Split("/")[-1]


# Fetch Postgres DB Admin password (or create if not present)
$dbAdminRole = "admin"
$dbAdminUser = "dbadmin"
$dbAdminPasswordSecretName = ($config.dsg.shortName + "-pgdbadmin-password")
$dbAdminPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $dbAdminPasswordSecretName).SecretValueText;
if ($null -eq $dbAdminPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $dbAdminPasswordSecretName -SecretValue $newPassword;
  $dbAdminPassword = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $dbAdminPasswordSecretName).SecretValueText;
}

# Fetch Postgres DB Writer password (or create if not present)
$dbWriterRole = "writer"
$dbWriterUser = "dbwriter"
$dbWriterPasswordSecretName = ($config.dsg.shortName + "-pgdbwriter-password")
$dbWriterPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $dbWriterPasswordSecretName).SecretValueText;
if ($null -eq $dbWriterPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $dbWriterPasswordSecretName -SecretValue $newPassword;
  $dbWriterPassword = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $dbWriterPasswordSecretName).SecretValueText;
}

# Fetch Postgres DB Reader password (or create if not present)
$dbReaderRole = "reader"
$dbReaderUser = "dbreader"
$dbReaderPasswordSecretName = ($config.dsg.shortName + "-pgdbreader-password")
$dbReaderPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $dbReaderPasswordSecretName).SecretValueText;
if ($null -eq $dbReaderPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  $_ = Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $dbReaderPasswordSecretName -SecretValue $newPassword;
  $dbReaderPassword = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $dbReaderPasswordSecretName).SecretValueText;
}

# Run remote script
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "create_postgres_roles.sh"

$params = @{
    DBADMINROLE = $dbAdminRole
    DBADMINUSER = $dbAdminUser
    DBADMINPWD = $dbAdminPassword
    DBWRITERROLE = $dbWriterRole
    DBWRITERUSER = $dbWriterUser
    DBWRITERPWD = $dbWriterPassword
    DBREADERROLE = $dbReaderRole
    DBREADERUSER = $dbReaderUser
    DBREADERPWD = $dbReaderPassword
};

Write-Output " - Ensuring Postgres DB roles and initial shared users exist on VM $vmName"
Write-Output " - User: '$dbAdminUser'; Role: '$dbAdminRole'; Password in KeyVault secret name '$dbAdminPasswordSecretName'"
Write-Output " - User: '$dbWriterUser'; Role: '$dbWriterRole'; Password in KeyVault secret name '$dbWriterPasswordSecretName'"
Write-Output " - User: '$dbReaderUser'; Role: '$dbReaderRole'; Password in KeyVault secret name '$dbReaderPasswordSecretName'"

# Switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $subscriptionTarget;

$result = Invoke-AzVMRunCommand -ResourceGroupName $config.dsg.dsvm.rg -Name "$vmName" `
          -CommandId 'RunShellScript' -ScriptPath $scriptPath -Parameter $params
Write-Output $result.Value;

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;
