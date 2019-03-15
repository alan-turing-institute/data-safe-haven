param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Fetch HackMD password (or create if not present)
$hackMdPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.users.ldap.hackmd.passwordSecretName).SecretValueText;
if ($null -eq $hackMdPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.users.ldap.hackmd.passwordSecretName -SecretValue $newPassword;
  $hackMdPassword = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.users.ldap.hackmd.passwordSecretName).SecretValueText;
}

# Fetch Gitlab password (or create if not present)
$gitlabPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.users.ldap.gitlab.passwordSecretName).SecretValueText;
if ($null -eq $gitlabPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.users.ldap.gitlab.passwordSecretName -SecretValue $newPassword;
  $gitlabPassword = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.users.ldap.gitlab.passwordSecretName).SecretValueText;
}

# Fetch DSVM password (or create if not present)
$dsvmPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.users.ldap.dsvm.passwordSecretName).SecretValueText;
if ($null -eq $dsvmPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.users.ldap.dsvm.passwordSecretName -SecretValue $newPassword;
  $dsvmPassword = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.users.ldap.dsvm.passwordSecretName).SecretValueText;
}

# Fetch test research user password (or create if not present)
$testResearcherPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.users.researchers.test.passwordSecretName).SecretValueText;
if ($null -eq $testResearcherPassword) {
  # Create password locally but round trip via KeyVault to ensure it is successfully stored
  $newPassword = New-Password;
  $newPassword = (ConvertTo-SecureString $newPassword -AsPlainText -Force);
  Set-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.users.researchers.test.passwordSecretName -SecretValue $newPassword;
  $testResearcherPassword = (Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $config.dsg.users.researchers.test.passwordSecretName).SecretValueText;
}

# Temporarily switch to management subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.shm.subscriptionName;

# Run remote script
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Create_New_DSG_User_Service_Accounts_Remote.ps1"
# For some reason, passing a JSON string as the -Parameter value for Invoke-AzVMRunCommand
# results in the double quotes in the JSON string being stripped in transit
# Escaping these with a single backslash retains the double quotes but the transferred
# string is truncated. Escaping these with backticks still results in the double quotes
# being stripped in transit, but we can then replace the backticks with double quotes 
# at the other end to recover a valid JSON string.
$configJson = ($config | ConvertTo-Json -depth 10 -Compress).Replace("`"","```"")

$params = @{
  configJson = $configJson
  hackMdPassword = $hackMdPassword
  gitlabPassword = $gitlabPassword
  dsvmPassword = $dsvmPassword
  testResearcherPassword = $testResearcherPassword
}

Invoke-AzVMRunCommand -ResourceGroupName $config.shm.dc.rg -Name $config.shm.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $params

# Switch back to previous subscription
Set-AzContext -Context $prevContext;

