param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter last octet of compute VM IP address (e.g. 160)")]
  [string]$ipLastOctet
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);
$prevContext = Get-AzContext


# Find VM with private IP address matching the provided last octet
# ----------------------------------------------------------------
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
Write-Host "Finding VM with last IP octet: $ipLastOctet"
$vmId = Get-AzNetworkInterface -ResourceGroupName $config.dsg.dsvm.rg | Where-Object { ($_.IpConfigurations.PrivateIpAddress).Split(".") -eq $ipLastOctet } | % { $_.VirtualMachine.Id }
$vm = Get-AzVm -ResourceGroupName $config.dsg.dsvm.rg | Where-Object { $_.Id -eq $vmId }


# Get LDAP secret from the KeyVault
# ---------------------------------
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
Write-Host "Checking LDAP secret in KeyVault: $($config.dsg.keyVault.name)"
$kvLdapPassword = (Get-AzKeyVaultSecret -vaultName $config.dsg.keyVault.name -name $config.dsg.users.ldap.dsvm.passwordSecretName).SecretValueText;
Write-Host "LDAP secret in the KeyVault: '$kvLdapPassword'"


# Set LDAP secret in local Active Directory on the SHM DC
# -------------------------------------------------------
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "ResetLdapPasswordOnAD.ps1"
$params = @{
    samAccountName = "`"$($config.dsg.users.ldap.dsvm.samAccountName)`""
    ldapPassword = "`"$kvLdapPassword`""
}
Write-Host "Setting LDAP secret in local AD on: $($config.shm.dc.vmName)"
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.shm.dc.rg -Name $config.shm.dc.vmName `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
                                -Parameter $params
Write-Host $result.Value


# Set LDAP secret on the VM
# -------------------------
Write-Host "Setting LDAP secret on VM: $($vm.Name)"
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "reset_ldap_password.sh"
$params = @{
    ldapPassword = "`"$kvLdapPassword`""
}
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.dsg.dsvm.rg -Name $vm.Name `
                                -CommandId 'RunShellScript' -ScriptPath $scriptPath -Parameter $params
$vmLdapPasswordOld = $result.Value.Message -Split "`n" | Select-String 'Previous LDAP password' | %{ ($_ -Split "'" )[1] }
Write-Host "Previous LDAP secret on the VM: '$vmLdapPasswordOld'"
$vmLdapPasswordNew = $result.Value.Message -Split "`n" | Select-String 'New LDAP password' | %{ ($_ -Split "'" )[1] }
Write-Host "New LDAP secret on the VM: '$vmLdapPasswordNew'"
