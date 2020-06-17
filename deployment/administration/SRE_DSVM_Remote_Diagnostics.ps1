param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Position = 1,Mandatory = $true,HelpMessage = "Enter last octet of compute VM IP address (e.g. 160)")]
    [string]$ipLastOctet
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Find VM with private IP address matching the provided last octet
# ----------------------------------------------------------------
Add-LogMessage -Level Info "Finding compute VM with last IP octet: $ipLastOctet"
$vmId = Get-AzNetworkInterface -ResourceGroupName $config.sre.dsvm.rg | Where-Object { ($_.IpConfigurations.PrivateIpAddress).Split(".") -eq $ipLastOctet } | ForEach-Object { $_.VirtualMachine.Id }
$vm = Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | Where-Object { $_.Id -eq $vmId }
if ($?) {
    Add-LogMessage -Level Success "Found compute VM '$($vm.Name)'"
} else {
    Add-LogMessage -Level Fatal "Could not find VM with last IP octet '$ipLastOctet'"
}

# Run remote diagnostic scripts
# -----------------------------
Add-LogMessage -Level Info "Running diagnostic scripts on VM $($vm.Name)..."
$params = @{
    TEST_HOST = $config.shm.dc.fqdn
    LDAP_USER = $config.sre.users.computerManagers.dsvm.samAccountName
    DOMAIN_LOWER = $config.shm.domain.fqdn
    SERVICE_PATH = "'$($config.shm.domain.serviceOuPath)'"
}
foreach ($scriptNamePair in (("LDAP connection", "check_ldap_connection.sh"),
                             ("name resolution", "restart_name_resolution_service.sh"),
                             ("realm join", "rerun_realm_join.sh"),
                             ("SSSD service", "restart_sssd_service.sh"),
                             ("xrdp service", "restart_xrdp_service.sh"))) {
    $name, $diagnostic_script = $scriptNamePair
    $scriptPath = Join-Path $PSScriptRoot ".." "secure_research_environment" "remote" "compute_vm" "scripts" $diagnostic_script
    Add-LogMessage -Level Info "[ ] Configuring $name ($diagnostic_script) on compute VM '$($vm.Name)'"
    $result = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vm.Name -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
    $success = $?
    Write-Output $result.Value
    if ($success) {
        Add-LogMessage -Level Success "Configuring $name on $($vm.Name) was successful"
    } else {
        Add-LogMessage -Level Failure "Configuring $name on $($vm.Name) failed!"
    }
}


# Get LDAP secret from the KeyVault
# ---------------------------------
Add-LogMessage -Level Info "[ ] Loading LDAP secret from key vault '$($config.sre.keyVault.name)'"
$kvLdapPassword = (Get-AzKeyVaultSecret -VaultName $config.sre.keyVault.Name -Name $config.sre.keyVault.secretNames.dsvmLdapPassword).SecretValueText;
if ($kvLdapPassword) {
    Add-LogMessage -Level Success "Found LDAP secret in the key vault"
} else {
    Add-LogMessage -Level Fatal "Could not load LDAP secret from key vault '$($config.sre.keyVault.name)'"
}


# Set LDAP secret on the compute VM
# ---------------------------------
Add-LogMessage -Level Info "[ ] Setting LDAP secret on compute VM '$($vm.Name)'"
$scriptPath = Join-Path $PSScriptRoot ".." "secure_research_environment" "remote" "compute_vm" "scripts" "reset_ldap_password.sh"
$params = @{
    ldapPassword = "`"$kvLdapPassword`""
}
$result = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vm.Name -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
$success = $?
Write-Output $result.Value
if ($success) {
    Add-LogMessage -Level Success "Setting LDAP secret on compute VM $($vm.Name) was successful"
} else {
    Add-LogMessage -Level Fatal "Setting LDAP secret on compute VM $($vm.Name) failed!"
}


# Set LDAP secret in local Active Directory on the SHM DC
# -------------------------------------------------------
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$scriptPath = Join-Path $PSScriptRoot ".." "secure_research_environment" "remote" "compute_vm" "scripts" "ResetLdapPasswordOnAD.ps1"
$params = @{
    samAccountName = "`"$($config.sre.users.computerManagers.dsvm.samAccountName)`""
    ldapPassword = "`"$kvLdapPassword`""
}
Add-LogMessage -Level Info "[ ] Setting LDAP secret in local AD on '$($config.shm.dc.vmName)'"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
$success = $?
Write-Output $result.Value
if ($success) {
    Add-LogMessage -Level Success "Setting LDAP secret on SHM DC was successful"
} else {
    Add-LogMessage -Level Fatal "Setting LDAP secret on SHM DC failed!"
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
