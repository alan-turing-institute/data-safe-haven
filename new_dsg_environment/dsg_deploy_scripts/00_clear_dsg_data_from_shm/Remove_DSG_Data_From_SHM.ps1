param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../GeneratePassword.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to management subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;

$helperScripDir = Join-Path $PSScriptRoot "helper_scripts" "Remove_DSG_Data_From_SHM" 

# === Remove all DSG secrets from SHM KeyVault ===
function Remove-DsgSecret($secretName){
  if(Get-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $secretName) {
    Write-Host " - Deleting secret '$secretName'"
    Remove-AzKeyVaultSecret -VaultName $config.dsg.keyVault.name -Name $secretName -Force 
  } else {
    Write-Host " - No secret '$secretName' exists"
  }
}
Write-Host "Removing DSG secrets from SHM KeyVault"
Remove-DsgSecret $config.dsg.dc.admin.passwordSecretName
Remove-DsgSecret $config.dsg.users.ldap.dsvm.passwordSecretName
Remove-DsgSecret $config.dsg.users.ldap.gitlab.passwordSecretName
Remove-DsgSecret $config.dsg.users.ldap.hackmd.passwordSecretName
Remove-DsgSecret $config.dsg.users.researchers.test.passwordSecretName
Remove-DsgSecret $config.dsg.rds.gateway.npsSecretName
Remove-DsgSecret $config.dsg.linux.gitlab.rootPasswordSecretName
Remove-DsgSecret $config.dsg.dsvm.admin.passwordSecretName

# === Remove DSG users and groups from SHM DC ===
$scriptPath = Join-Path $helperScripDir "remote_scripts" "Remove_Users_And_Groups_Remote.ps1"
$params = @{
  testResearcherSamAccountName = "`"$($config.dsg.users.researchers.test.samAccountName)`""
  dsvmLdapSamAccountName = "`"$($config.dsg.users.ldap.dsvm.samAccountName)`""
  gitlabLdapSamAccountName = "`"$($config.dsg.users.ldap.gitlab.samAccountName)`""
  hackmdLdapSamAccountName = "`"$($config.dsg.users.ldap.hackmd.samAccountName)`""
  dsgResearchUserSG = "`"$($config.dsg.domain.securityGroups.researchUsers.name)`""
}
Write-Host "Removing DSG users and groups from SHM DC"
Invoke-AzVMRunCommand -ResourceGroupName $config.shm.dc.rg -Name $config.shm.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $params

# === Remove DSG DNS records from SHM DC ===
$scriptPath = Join-Path $helperScripDir "remote_scripts" "Remove_DNS_Entries_Remote.ps1"
$params = @{
  dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
  identitySubnetPrefix = "`"$($config.dsg.network.subnets.identity.prefix)`""
  rdsSubnetPrefix = "`"$($config.dsg.network.subnets.rds.prefix)`""
  dataSubnetPrefix = "`"$($config.dsg.network.subnets.data.prefix)`""
}
Write-Host "Removing DSG DNS records from SHM" DC
Invoke-AzVMRunCommand -ResourceGroupName $config.shm.dc.rg -Name $config.shm.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $params

# === Remove DSG AD Trust from SHM DC ===
$scriptPath = Join-Path $helperScripDir "remote_scripts" "Remove_AD_Trust_Remote.ps1"
$params = @{
  shmFqdn = "`"$($config.shm.domain.fqdn)`""
  dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
}
Write-Host "Removing DSG AD Trust from SHM DC"
Invoke-AzVMRunCommand -ResourceGroupName $config.shm.dc.rg -Name $config.shm.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $params

# === Remove RDS Gateway RADIUS Client from SHM NPS ===
$npsRadiusClientParams = @{
  rdsGatewayFqdn = "`"$($config.dsg.rds.gateway.fqdn)`""
};
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Add_RDS_Gateway_RADIUS_Client_Remote.ps1"
Write-Host "Removing RDS Gateway RADIUS Client from SHM NPS"
Invoke-AzVMRunCommand -ResourceGroupName $($config.shm.nps.rg) `
  -Name "$($config.shm.nps.vmName)" `
  -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
  -Parameter $npsRadiusClientParams

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;
