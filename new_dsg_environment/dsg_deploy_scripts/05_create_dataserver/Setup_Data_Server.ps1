param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force


# Get SRE config
# --------------
$config = Get-DsgConfig($sreId);
$originalContext = Get-AzContext


# Retrieve passwords from the keyvault
# ------------------------------------
Write-Host -ForegroundColor DarkCyan "Creating/retrieving secrets from '$($config.dsg.keyVault.name)' KeyVault..."
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName;
$dcAdminUsername = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dcAdminUsername -defaultValue "sre$($config.dsg.id)admin".ToLower()
$dcAdminPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dcAdminPassword


# Deploy data server from template
# --------------------------------
Write-Host -ForegroundColor DarkCyan "Deploying data server from template..."
$_ = New-AzResourceGroup -Name $config.dsg.dataserver.rg -Location $config.dsg.location -Force
$templateName = "sre-data-server-template"
$params = @{
  "SRE ID" = $config.dsg.id
  "Data Server Name" = $config.dsg.dataserver.vmName
  "Domain Name" = $config.dsg.domain.fqdn
  "VM Size" = $config.dsg.dataserver.vmSize
  "IP Address" = $config.dsg.dataserver.ip
  "Administrator User" = $dcAdminUsername
  "Administrator Password" = (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force)
  "Virtual Network Name" = $config.dsg.network.vnet.name
  "Virtual Network Resource Group" = $config.dsg.network.vnet.rg
  "Virtual Network Subnet" = $config.dsg.network.subnets.data.name
}
# Deploy data server template
New-AzResourceGroupDeployment -ResourceGroupName $config.dsg.dataserver.rg -TemplateFile $(Join-Path $PSScriptRoot "$($templateName).json") @params -Verbose


# # Add RDS VMs to correct OUs
# # --------------------------
# Write-Host -ForegroundColor DarkCyan "Adding data server VM to correct OU..."
# $_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName
# $scriptPath = Join-Path "remote_scripts" "Move_Data_Server_VM_Into_OU.ps1"
# $params = @{
#     dsgDn = "`"$($config.dsg.domain.dn)`""
#     dsgNetbiosName = "`"$($config.dsg.domain.netbiosName)`""
#     dataServerHostname = "`"$($config.dsg.dataserver.hostname)`""
# };
# $result = Invoke-AzVMRunCommand -Name "$($config.dsg.dc.vmName)" -ResourceGroupName "$($config.dsg.dc.rg)" `
#                                 -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
# $success = $?
# Write-Output $result.Value;
# if ($success) {
#     Write-Host -ForegroundColor DarkGreen " [o] Successfully added data server VM to correct OU"
# } else {
#     Write-Host -ForegroundColor DarkRed " [x] Failed to add data server VM to correct OU!"
# }


# # Add RDS VMs to correct OUs
# # --------------------------
# Write-Host -ForegroundColor DarkCyan "Configuring data server VM..."
# $_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName
# $scriptPath = Join-Path "remote_scripts" "Configure_Data_Server_Remote.ps1"
# $params = @{
#   dsgNetbiosName = "`"$($config.dsg.domain.netbiosName)`""
#   shmNetbiosName = "`"$($config.shm.domain.netbiosName)`""
#   researcherUserSgName = "`"$($config.dsg.domain.securityGroups.researchUsers.name)`""
#   serverAdminSgName = "`"$($config.dsg.domain.securityGroups.serverAdmins.name)`""
# };
# $vmResourceGroup =
# $vmName =

# Write-Host "Configuring Data Server"
# $result = Invoke-AzVMRunCommand -Name "$($config.dsg.dataserver.vmName)" -ResourceGroupName "$($config.dsg.dataserver.rg)" `
#                                 -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params
# $success = $?
# Write-Output $result.Value;
# if ($success) {
#     Write-Host -ForegroundColor DarkGreen " [o] Successfully added data server VM to correct OU"
# } else {
#     Write-Host -ForegroundColor DarkRed " [x] Failed to add data server VM to correct OU!"
# }


# # Switch back to original subscription
# # ------------------------------------
# $_ = Set-AzContext -Context $originalContext;
