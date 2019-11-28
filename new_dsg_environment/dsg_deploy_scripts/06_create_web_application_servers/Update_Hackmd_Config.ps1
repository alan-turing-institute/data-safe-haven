# param(
#   [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
#   [string]$dsgId
# )

# Import-Module Az
# Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force
# Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force

# # Get DSG config
# $config = Get-DsgConfig($dsgId);

# # Temporarily switch to DSG subscription
# $prevContext = Get-AzContext
# $_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# # Find VM with private IP address matching the provided last octect
# ## Turn provided last octect into full IP address in the data subnet
# $vmIpAddress = $config.dsg.linux.hackmd.ip
# Write-Host " - Finding VM with IP $vmIpAddress"
# ## Get all web app server VMs
# $webAppVms = Get-AzVM -ResourceGroupName $config.dsg.linux.rg
# ## Get the NICs attached to all the compute VMs
# $webAppVmNicIds = ($webAppVms | ForEach-Object{(Get-AzVM -ResourceGroupName $config.dsg.linux.rg -Name $_.Name).NetworkProfile.NetworkInterfaces.Id})
# $webAppVmNics = ($webAppVmNicIds | ForEach-Object{Get-AzNetworkInterface -ResourceGroupName $config.dsg.linux.rg -Name $_.Split("/")[-1]})
# ## Filter the NICs to the one matching the desired IP address and get the name of the VM it is attached to
# $vmName = ($webAppVmNics | Where-Object{$_.IpConfigurations.PrivateIpAddress -match $vmIpAddress})[0].VirtualMachine.Id.Split("/")[-1]
# Write-Output " - VM '$vmName' found"

# # Set HackMD config values
# $hackmdLdapSearchFilter = "(&(objectClass=user)(memberOf=CN=" + $config.dsg.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + ")(userPrincipalName={{username}}))"
# $hackmdLdapSearchBase = $config.shm.domain.userOuPath;
# $hackmdBindCreds = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.users.ldap.hackmd.passwordSecretName).SecretValueText;
# $hackmdLdapBindDn = "CN=" + $config.dsg.users.ldap.hackmd.name + "," + $config.shm.domain.serviceOuPath
# $hackmdLdapUrl = "ldap://" + $config.shm.dc.fqdn
# $hackmdLdapProviderName = $config.shm.domain.netbiosName

# # Run remote script
# $scriptPath = Join-Path $PSScriptRoot "remote_scripts" "update_hackmd_config.sh"

# $params = @{
#     HMD_LDAP_SEARCHFILTER="'" + $hackmdLdapSearchFilter.Replace("&","\&") + "'"
#     HMD_LDAP_SEARCHBASE="'$hackmdLdapSearchBase'"
#     HMD_LDAP_BINDCREDENTIALS="'$hackmdBindCreds'"
#     HMD_LDAP_BINDDN="'$hackmdLdapBindDn'"
#     HMD_LDAP_URL="'$hackmdLdapUrl'"
#     HMD_LDAP_PROVIDERNAME="'$hackmdLdapProviderName'"
# };

# $result = Invoke-AzVMRunCommand -ResourceGroupName $config.dsg.linux.rg -Name "$vmName" `
#           -CommandId 'RunShellScript' -ScriptPath $scriptPath -Parameter $params
# Write-Output $result.Value;

# # Switch back to previous subscription
# $_ = Set-AzContext -Context $prevContext;
