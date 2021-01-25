param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Enter last octet of compute VM IP address (e.g. 160)")]
    [string]$ipLastOctet
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Find VM with private IP address matching the provided last octet
# ----------------------------------------------------------------
Add-LogMessage -Level Info "Finding compute VM with last IP octet: $ipLastOctet"
$vmId = Get-AzNetworkInterface -ResourceGroupName $config.sre.dsvm.rg | Where-Object { ($_.IpConfigurations.PrivateIpAddress).Split(".") -eq $ipLastOctet } | ForEach-Object { $_.VirtualMachine.Id }
$vmIpAddress = (Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq $vmId }).IpConfigurations.PrivateIpAddress
$vm = Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | Where-Object { $_.Id -eq $vmId }
if ($?) {
    Add-LogMessage -Level Success "Found compute VM '$($vm.Name)'"
} else {
    Add-LogMessage -Level Fatal "Could not find VM with last IP octet '$ipLastOctet'"
}


# Run remote diagnostic scripts
# -----------------------------
Invoke-Expression -Command "$(Join-Path $PSScriptRoot '..' 'secure_research_environment' 'setup' 'Run_SRE_DSVM_Remote_Diagnostics.ps1') -configId $configId -ipLastOctet $ipLastOctet"


# Get LDAP secret from the Key Vault
# ---------------------------------
Add-LogMessage -Level Info "[ ] Loading LDAP secret from key vault '$($config.sre.keyVault.name)'"
$ldapSearchPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.ldapSearch.passwordSecretName -DefaultLength 20 -AsPlaintext
if ($ldapSearchPassword) {
    Add-LogMessage -Level Success "Found LDAP secret in the key vault"
} else {
    Add-LogMessage -Level Fatal "Could not load LDAP secret from key vault '$($config.sre.keyVault.name)'"
}


# Set LDAP secret on the compute VM
# ---------------------------------
Add-LogMessage -Level Info "[ ] Setting LDAP secret on compute VM '$($vm.Name)'"
$scriptPath = Join-Path $PSScriptRoot ".." "secure_research_environment" "remote" "compute_vm" "scripts" "reset_ldap_password.sh"
$params = @{
    ldapPassword = "`"$ldapSearchPassword`""
}
$null = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vm.Name -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
if ($?) {
    Add-LogMessage -Level Success "Setting LDAP secret on compute VM $($vm.Name) was successful"
} else {
    Add-LogMessage -Level Fatal "Setting LDAP secret on compute VM $($vm.Name) failed!"
}


# Set LDAP secret in local Active Directory on the SHM DC
# -------------------------------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
$scriptPath = Join-Path $PSScriptRoot ".." "secure_research_environment" "remote" "compute_vm" "scripts" "ResetLdapPasswordOnAD.ps1"
$params = @{
    samAccountName = "`"$($config.sre.users.serviceAccounts.ldapSearch.samAccountName)`""
    ldapPassword   = "`"$ldapSearchPassword`""
}
Add-LogMessage -Level Info "[ ] Setting LDAP secret in local AD on '$($config.shm.dc.vmName)'"
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
if ($?) {
    Add-LogMessage -Level Success "Setting LDAP secret on SHM DC was successful"
} else {
    Add-LogMessage -Level Fatal "Setting LDAP secret on SHM DC failed!"
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Update DNS record on the SHM for this VM
# ----------------------------------------
$null = Set-AzContext -SubscriptionId $config.shm. -ErrorAction Stop
Add-LogMessage -Level Info "[ ] Updating DNS record for DSVM '$($vm.Name)'..."
$scriptPath = Join-Path $PSScriptRoot ".." "secure_research_environment" "remote" "compute_vm" "scripts" "UpdateDNSRecord.ps1"
$params = @{
    Fqdn      = $config.shm.domain.fqdn
    HostName  = $vm.Name
    IpAddress = $vmIpAddress
}
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop



# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
