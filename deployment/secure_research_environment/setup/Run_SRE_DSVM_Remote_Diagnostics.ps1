param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Mandatory = $true, ParameterSetName = "ByIPAddress", HelpMessage = "Last octet of IP address eg. '160'")]
    [string]$ipLastOctet
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Use the IP last octet to get the VM name
# ----------------------------------------
$vmNamePrefix = "SRE-$($config.sre.id)-${ipLastOctet}-DSVM".ToUpper()
$vmName = (Get-AzVM | Where-Object { $_.Name -match "$vmNamePrefix-\d-\d-\d{10}" }).Name
$ipAddress = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.compute.cidr -Offset $ipLastOctet
if (-not $vmName) {
    Add-LogMessage -Level Fatal "Could not find a VM with last IP octet equal to '$ipLastOctet'"
}


# Update DNS record on the SHM for this VM
# ----------------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
Add-LogMessage -Level Info "[ ] Resetting DNS record for DSVM '$vmName'..."
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "compute_vm" "scripts" "ResetDNSRecord.ps1"
$params = @{
    Fqdn = $config.shm.domain.fqdn
    HostName = $vmName
    IpAddress = $ipAddress
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
$success = $?
Write-Output $result.Value
if ($success) {
    Add-LogMessage -Level Success "Resetting DNS record for DSVM '$vmName' was successful"
} else {
    Add-LogMessage -Level Failure "Resetting DNS record for DSVM '$vmName' failed!"
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Run remote diagnostic scripts
# -----------------------------
Add-LogMessage -Level Info "Running diagnostic scripts on VM $vmName..."
$params = @{
    DOMAIN_CONTROLLER = $config.shm.dc.fqdn
    DOMAIN_JOIN_OU    = "`"$($config.shm.domain.ous.linuxServers.path)`""
    DOMAIN_JOIN_USER  = $config.shm.users.computerManagers.linuxServers.samAccountName
    DOMAIN_LOWER      = $config.shm.domain.fqdn
    LDAP_SEARCH_USER  = $config.sre.users.serviceAccounts.ldapSearch.samAccountName
    LDAP_TEST_USER    = $config.shm.users.serviceAccounts.aadLocalSync.samAccountName
    SERVICE_PATH      = "`"$($config.shm.domain.ous.serviceAccounts.path)`""
}
foreach ($scriptNamePair in (("LDAP connection", "check_ldap_connection.sh"),
                             ("name resolution", "restart_name_resolution_service.sh"),
                             ("realm join", "rerun_realm_join.sh"),
                             ("mounted drives", "check_drive_mounts.sh"),
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
