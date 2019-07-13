param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../GeneratePassword.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Directory for local and remote helper scripts
$helperScripDir = Join-Path $PSScriptRoot "helper_scripts" "Remove_DSG_Data_From_SHM" -Resolve

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
$dsgResourceGroups = @(Get-AzResourceGroup)
$dsgResources = @(Get-AzResource)
if($dsgResources -or $dsgResourceGroups) {
  Write-Host "********************************************************************************"
  Write-Host "*** DSG $dsgId subscription '$($config.dsg.subscriptionName)' is not empty!! ***"
  Write-Host "********************************************************************************"
  Write-Host "DSG data should not be deleted from the SHM unless all DSG resources have been deleted from the subscription."
  Write-Host ""
  Write-Host "Resource Groups present in DSG subscription:"
  Write-Host "--------------------------------------"
  $dsgResourceGroups
  Write-Host "Resources present in DSG subscription:"
  Write-Host "--------------------------------------"
  $dsgResources
  $_ = Set-AzContext -Context $prevContext;
  Exit 1
}

# Temporarily switch to SHM subscription
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;
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

# === Remove SHM side of peerings involving this DSG ===
Write-Output ("Removing peerings for DSG VNet from SHM VNets")
# --- Remove main DSG <-> SHM VNet peering ---
$peeringName = "PEER_$($config.dsg.network.vnet.name)"
Write-Output " - Removing peering '$peeringName' from SHM VNet '$($config.shm.network.vnet.name)'"
$_ = Remove-AzVirtualNetworkPeering -Name "$peeringName" -VirtualNetworkName $config.shm.network.vnet.name `
                                    -ResourceGroupName $config.shm.network.vnet.rg  -Force;
# --- Remove any DSG <-> Mirror VNet peerings
# Iterate over mirror VNets
$mirrorVnets = Get-AzVirtualNetwork -Name "*" -ResourceGroupName $config.dsg.mirrors.rg
foreach($mirrorVNet in $mirrorVnets){
  $peeringName = "PEER_$($config.dsg.network.vnet.name)"
  Write-Output (" - Removing peering '$peeringName' from $($mirrorVNet.Name)")
  $_ = Remove-AzVirtualNetworkPeering -Name "$peeringName" -VirtualNetworkName $mirrorVNet.Name `
                                      -ResourceGroupName $config.dsg.mirrors.rg  -Force;
}

# === Remove RDS entries from DSG DNS Zone ===
$dnsResourceGroup = $config.shm.dns.rg
$dsgDomain = $config.dsg.domain.fqdn
$rdsDdnsRecordname = "$($config.dsg.rds.gateway.hostname)".ToLower()
$rdsAcmeDnsRecordname =  ("_acme-challenge." + "$($config.dsg.rds.gateway.hostname)".ToLower())
Write-Host " - Removing '$rdsDdnsRecordname' A record from DSG $dsgId DNS zone ($dsgDomain)"
Remove-AzDnsRecordSet -Name $rdsDdnsRecordname -RecordType A -ZoneName $dsgDomain -ResourceGroupName $dnsResourceGroup
Write-Host " - Removing '$rdsAcmeDnsRecordname' TXT record from DSG $dsgId DNS zone ($dsgDomain)"
Remove-AzDnsRecordSet -Name $rdsAcmeDnsRecordname -RecordType TXT -ZoneName $dsgDomain -ResourceGroupName $dnsResourceGroup

# === Remove DSG users and groups from SHM DC ===
$scriptPath = Join-Path $helperScripDir "remote_scripts" "Remove_Users_And_Groups_Remote.ps1" -Resolve
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
$scriptPath = Join-Path $helperScripDir "remote_scripts" "Remove_DNS_Entries_Remote.ps1" -Resolve
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
$scriptPath = Join-Path $helperScripDir "remote_scripts" "Remove_AD_Trust_Remote.ps1" -Resolve
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
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Remove_RDS_Gateway_RADIUS_Client_Remote.ps1" -Resolve
Write-Host "Removing RDS Gateway RADIUS Client from SHM NPS"
Invoke-AzVMRunCommand -ResourceGroupName $($config.shm.nps.rg) `
  -Name "$($config.shm.nps.vmName)" `
  -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
  -Parameter $npsRadiusClientParams

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;
