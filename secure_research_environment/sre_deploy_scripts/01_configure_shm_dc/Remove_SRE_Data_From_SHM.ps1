param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force

# Get SRE config
$config = Get-SreConfig($sreId);
$originalContext = Get-AzContext

# Directory for local and remote helper scripts
$helperScriptDir = Join-Path $PSScriptRoot "helper_scripts" "Remove_DSG_Data_From_SHM" -Resolve

# Switch to SRE subscription
# --------------------------
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
$dsgResourceGroups = @(Get-AzResourceGroup)
$dsgResources = @(Get-AzResource)
if($dsgResources -or $dsgResourceGroups) {
  Write-Host -ForegroundColor DarkRed "********************************************************************************"
  Write-Host -ForegroundColor DarkRed "*** SRE $sreId subscription '$($config.dsg.subscriptionName)' is not empty!! ***"
  Write-Host -ForegroundColor DarkRed "********************************************************************************"
  Write-Host -ForegroundColor DarkRed "SRE data should not be deleted from the SHM unless all SRE resources have been deleted from the subscription."
  Write-Host -ForegroundColor DarkRed ""
  Write-Host -ForegroundColor DarkRed "Resource Groups present in SRE subscription:"
  Write-Host -ForegroundColor DarkRed "--------------------------------------"
  $dsgResourceGroups
  Write-Host -ForegroundColor DarkRed "Resources present in SRE subscription:"
  Write-Host -ForegroundColor DarkRed "--------------------------------------"
  $dsgResources
  $_ = Set-AzContext -Context $originalContext;
  Exit 1
}

# Switch to SHM subscription
# --------------------------
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
Write-Host -ForegroundColor DarkGreen "Removing SRE secrets from key vault..."
$vault = Get-AzKeyVault -VaultName $config.dsg.keyVault.name
if ($vault -eq $null) {
  Write-Host " - Keyvault '$($config.dsg.keyVault.name)' does not exist"
} else {
  Remove-DsgSecret $config.dsg.dc.admin.passwordSecretName
  Remove-DsgSecret $config.dsg.users.ldap.dsvm.passwordSecretName
  Remove-DsgSecret $config.dsg.users.ldap.gitlab.passwordSecretName
  Remove-DsgSecret $config.dsg.users.ldap.hackmd.passwordSecretName
  Remove-DsgSecret $config.dsg.users.researchers.test.passwordSecretName
  Remove-DsgSecret $config.dsg.rds.gateway.npsSecretName
  Remove-DsgSecret $config.dsg.linux.gitlab.rootPasswordSecretName
  Remove-DsgSecret $config.dsg.dsvm.admin.passwordSecretName
}

# === Remove SHM side of peerings involving this DSG ===
Write-Host -ForegroundColor DarkGreen "Removing peerings for SRE VNet from SHM VNets..."
# --- Remove main DSG <-> SHM VNet peering ---
$peeringName = "PEER_$($config.dsg.network.vnet.name)"
Write-Host -ForegroundColor DarkGreen " - Removing peering '$peeringName' from SHM VNet '$($config.shm.network.vnet.name)'"
$_ = Remove-AzVirtualNetworkPeering -Name "$peeringName" -VirtualNetworkName $config.shm.network.vnet.name `
                                    -ResourceGroupName $config.shm.network.vnet.rg  -Force;
# --- Remove any DSG <-> Mirror VNet peerings
# Iterate over mirror VNets
$mirrorVnets = Get-AzVirtualNetwork -Name "*" -ResourceGroupName $config.shm.mirrors.rg
foreach($mirrorVNet in $mirrorVnets){
  $peeringName = "PEER_$($config.dsg.network.vnet.name)"
  Write-Host -ForegroundColor DarkGreen " - Removing peering '$peeringName' from $($mirrorVNet.Name)..."
  $_ = Remove-AzVirtualNetworkPeering -Name "$peeringName" -VirtualNetworkName $mirrorVNet.Name `
                                      -ResourceGroupName $config.dsg.mirrors.rg  -Force;
}

# === Remove DSG users and groups from SHM DC ===
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Remove_Users_And_Groups_Remote.ps1" -Resolve
$params = @{
  testResearcherSamAccountName = "`"$($config.dsg.users.researchers.test.samAccountName)`""
  dsvmLdapSamAccountName = "`"$($config.dsg.users.ldap.dsvm.samAccountName)`""
  gitlabLdapSamAccountName = "`"$($config.dsg.users.ldap.gitlab.samAccountName)`""
  hackmdLdapSamAccountName = "`"$($config.dsg.users.ldap.hackmd.samAccountName)`""
  dsgResearchUserSG = "`"$($config.dsg.domain.securityGroups.researchUsers.name)`""
}
Write-Host -ForegroundColor DarkGreen "Removing SRE users and groups from SHM DC..."
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.shm.dc.rg -Name $config.shm.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $params
Write-Host $result.Value[0].Message
Write-Host $result.Value[1].Message

# === Remove SRE DNS records from SHM DC ===
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Remove_DNS_Entries_Remote.ps1" -Resolve
$params = @{
  dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
  identitySubnetPrefix = "`"$($config.dsg.network.subnets.identity.prefix)`""
  rdsSubnetPrefix = "`"$($config.dsg.network.subnets.rds.prefix)`""
  dataSubnetPrefix = "`"$($config.dsg.network.subnets.data.prefix)`""
}
Write-Host -ForegroundColor DarkGreen "Removing SRE DNS records from SHM DC..."
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.shm.dc.rg -Name $config.shm.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $params
Write-Host $result.Value[0].Message
Write-Host $result.Value[1].Message

# === Remove DSG AD Trust from SHM DC ===
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Remove_AD_Trust_Remote.ps1" -Resolve
$params = @{
  shmFqdn = "`"$($config.shm.domain.fqdn)`""
  dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
}
Write-Host -ForegroundColor DarkGreen "Removing SRE AD Trust from SHM DC..."
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.shm.dc.rg -Name $config.shm.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $params
Write-Host $result.Value[0].Message
Write-Host $result.Value[1].Message

# === Remove RDS Gateway RADIUS Client from SHM NPS ===
$npsRadiusClientParams = @{
  rdsGatewayFqdn = "`"$($config.dsg.rds.gateway.fqdn)`""
};
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Remove_RDS_Gateway_RADIUS_Client_Remote.ps1" -Resolve
Write-Host -ForegroundColor DarkGreen "Removing RDS Gateway RADIUS Client from SHM NPS..."
$result = Invoke-AzVMRunCommand -ResourceGroupName $($config.shm.nps.rg) `
  -Name "$($config.shm.nps.vmName)" `
  -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
  -Parameter $npsRadiusClientParams
Write-Host $result.Value[0].Message
Write-Host $result.Value[1].Message


# === Remove RDS entries from DSG DNS Zone ===
# Switch to the domain subscription
$_ = Set-AzContext -SubscriptionId $config.shm.dns.subscriptionName;
$dnsResourceGroup = $config.shm.dns.rg
$dsgDomain = $config.dsg.domain.fqdn
$rdsDdnsRecordname = "$($config.dsg.rds.gateway.hostname)".ToLower()
$rdsAcmeDnsRecordname =  ("_acme-challenge." + "$($config.dsg.rds.gateway.hostname)".ToLower())
Write-Host " - Removing '$rdsDdnsRecordname' A record from SRE $sreId DNS zone ($dsgDomain)"
Remove-AzDnsRecordSet -Name $rdsDdnsRecordname -RecordType A -ZoneName $dsgDomain -ResourceGroupName $dnsResourceGroup
Write-Host " - Removing '$rdsAcmeDnsRecordname' TXT record from SRE $sreId DNS zone ($dsgDomain)"
Remove-AzDnsRecordSet -Name $rdsAcmeDnsRecordname -RecordType TXT -ZoneName $dsgDomain -ResourceGroupName $dnsResourceGroup

# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
