param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Mandatory = $true, HelpMessage = "Name of VM to run diagnostics on.")]
    [string]$vmName
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Run remote diagnostic scripts
# -----------------------------
Add-LogMessage -Level Info "Running diagnostic scripts on VM $vmName..."
$params = @{
    DOMAIN_CONTROLLER = $config.shm.dc.fqdn
    DOMAIN_JOIN_USER  = $config.shm.users.computerManagers.linuxServers.samAccountName
    DOMAIN_LOWER      = $config.shm.domain.fqdn
    LDAP_SEARCH_USER  = $config.sre.users.serviceAccounts.ldapSearch.samAccountName
    LDAP_TEST_USER    = $config.shm.users.serviceAccounts.aadLocalSync.samAccountName
    SERVICE_PATH      = "`"$($config.shm.domain.ous.serviceAccounts.path)`""
}
foreach ($scriptNamePair in (("mounted drives", "check_drive_mounts.sh"),
                             ("LDAP connection", "check_ldap_connection.sh"),
                             ("name resolution", "restart_name_resolution_service.sh"),
                             ("realm join", "rerun_realm_join.sh"),
                             ("SSSD service", "restart_sssd_service.sh"),
                             ("xrdp service", "restart_xrdp_service.sh"))) {
    $name, $diagnostic_script = $scriptNamePair
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "compute_vm" "scripts" $diagnostic_script
    Add-LogMessage -Level Info "[ ] Configuring $name ($diagnostic_script) on compute VM '$vmName'"
    $result = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
    $success = $?
    Write-Output $result.Value
    if ($success) {
        Add-LogMessage -Level Success "Configuring $name on $vmName was successful"
    } else {
        Add-LogMessage -Level Failure "Configuring $name on $vmName failed!"
    }
}

# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
