param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId,
    [Parameter(Mandatory = $true, ParameterSetName = "ByIPAddress", HelpMessage = "Last octet of IP address eg. '160'")]
    [string]$ipLastOctet
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Use the IP last octet to get the VM name
# ----------------------------------------
$vmNamePrefix = "SRE-$($config.sre.id)-${ipLastOctet}-DSVM".ToUpper()
$vmName = (Get-AzVM | Where-Object { $_.Name -match "$vmNamePrefix-\d-\d-\d{10}" }).Name
if (-not $vmName) {
    Add-LogMessage -Level Fatal "Could not find a VM with last IP octet equal to '$ipLastOctet'"
}


# Run remote diagnostic scripts
# -----------------------------
Add-LogMessage -Level Info "Running diagnostic scripts on VM $vmName..."
$params = @{
    DOMAIN_CONTROLLER = $config.shm.dc.fqdn
    DOMAIN_JOIN_OU    = "'$($config.shm.domain.ous.linuxServers.path)'"
    DOMAIN_JOIN_USER  = $config.shm.users.computerManagers.linuxServers.samAccountName
    DOMAIN_LOWER      = $config.shm.domain.fqdn
    LDAP_SEARCH_USER  = $config.sre.users.serviceAccounts.ldapSearch.samAccountName
    LDAP_TEST_USER    = $config.shm.users.serviceAccounts.aadLocalSync.samAccountName
    SERVICE_PATH      = "'$($config.shm.domain.ous.serviceAccounts.path)'"
}
foreach ($scriptNamePair in (("LDAP connection", "check_ldap_connection.sh"),
                             ("name resolution", "restart_name_resolution_service.sh"),
                             ("realm join", "rerun_realm_join.sh"),
                             ("mounted drives", "check_drive_mounts.sh"),
                             ("SSSD service", "restart_sssd_service.sh"),
                             ("xrdp service", "restart_xrdp_service.sh"))) {
    $name, $diagnostic_script = $scriptNamePair
    Add-LogMessage -Level Info "[ ] Configuring $name ($diagnostic_script) on compute VM '$vmName'"
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "compute_vm" "scripts" $diagnostic_script
    $null = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
    if ($?) {
        Add-LogMessage -Level Success "Configuring $name on $vmName was successful"
    } else {
        Add-LogMessage -Level Failure "Configuring $name on $vmName failed!"
    }
}

# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
