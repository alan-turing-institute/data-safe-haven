param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId,
    [Parameter(Position = 1,Mandatory = $true,HelpMessage = "Enter last octet of compute VM IP address (e.g. 160)")]
    [string]$ipLastOctet
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force

# Get SRE config
$config = Get-SreConfig ($sreId);
$prevContext = Get-AzContext


# Find VM with private IP address matching the provided last octet
# ----------------------------------------------------------------
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName;
Add-LogMessage -Level Info "Finding VM with last IP octet: $ipLastOctet"
$vmId = Get-AzNetworkInterface -ResourceGroupName $config.sre.dsvm.rg | Where-Object { ($_.IpConfigurations.PrivateIpAddress).Split(".") -eq $ipLastOctet } | ForEach-Object { $_.VirtualMachine.Id }
$vm = Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | Where-Object { $_.Id -eq $vmId }
if ($?) {
    Add-LogMessage -Level Success "Found VM: $($vm.Name)"
} else {
    Add-LogMessage -Level Fatal "Could not find VM with last IP octet '$ipLastOctet'"
}


# Get LDAP secret from the KeyVault
# ---------------------------------
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName;
Add-LogMessage -Level Info "Checking LDAP secret in KeyVault: $($config.sre.keyVault.name)"
$kvLdapPassword = (Get-AzKeyVaultSecret -VaultName $config.sre.keyVault.Name -Name $config.sre.keyVault.secretNames.dsvmLdapPassword).SecretValueText;
if ($kvLdapPassword -ne $null) {
    Add-LogMessage -Level Success "Found LDAP secret in the KeyVault"
} else {
    Add-LogMessage -Level Fatal "Could not load LDAP secret from KeyVault '$($config.sre.keyVault.name)'"
}


# Set LDAP secret in local Active Directory on the SHM DC
# -------------------------------------------------------
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "ResetLdapPasswordOnAD.ps1"
$params = @{
    samAccountName = "`"$($config.sre.users.ldap.dsvm.samAccountName)`""
    ldapPassword = "`"$kvLdapPassword`""
}
Add-LogMessage -Level Info "Setting LDAP secret in local AD on: $($config.shm.dc.vmName)"
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.shm.dc.rg -Name $config.shm.dc.vmName `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
                                -Parameter $params
$success = $?
Write-Output $result.Value
if ($success) {
    Add-LogMessage -Level Success "Setting LDAP secret on SHM DC was successful"
}


# Set LDAP secret on the VM
# -------------------------
Add-LogMessage -Level Info "Setting LDAP secret on compute VM: $($vm.Name)"
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName;
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "reset_ldap_password.sh"
$params = @{
    ldapPassword = "`"$kvLdapPassword`""
}
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.sre.dsvm.rg -Name $vm.Name `
                                -CommandId 'RunShellScript' -ScriptPath $scriptPath -Parameter $params
$success = $?
Write-Output $result.Value
if ($success) {
    Add-LogMessage -Level Success "Setting LDAP secret on compute VM was successful"
}
