param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Mandatory = $false, HelpMessage = "Last octet of IP address for DSVM to test DNS lockdown. Defaults to '160'")]
    [string]$dsvmIpLastOctet
)
Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Mirrors -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Block external DNS resolution for DSVMs via SHM DNS servers
# -----------------------------------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "network_configuration" "scripts" "Block_External_DNS_Queries_Remote.ps1"
$params = @{
    sreId                          = $config.sre.id
    blockedCidrsCommaSeparatedList = $config.sre.network.vnet.subnets.compute.cidr
}
foreach ($dnsServerName in @($config.shm.dc.vmName, $config.shm.dcb.vmName)) {
    Add-LogMessage -Level Info "Blocking external DNS resolution for DSVMs via ${dnsServerName}..."
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $dnsServerName -ResourceGroupName $config.shm.dc.rg -Parameter $params
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Validate external DNS resolution is blocked from DSVMs
# ------------------------------------------------------
# Get VM for provided IP address
$computeVmIds = @(Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | ForEach-Object { $_.Id })
$computeVmIpAddresses = @(Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -in $computeVmIds } | ForEach-Object { $_.IpConfigurations.PrivateIpAddress })
if (-not $dsvmIpLastOctet) {
    $dsvmIpLastOctet = $computeVmIpAddresses[0].Split(".")[3]
    Add-LogMessage -Level Warning "Test DSVM not specified by providing last octet of its IP address. Attempting to test on DSVM with last octet of '$dsvmIpLastOctet'."
}
$vmIpAddress = @($computeVmIpAddresses | Where-Object { $_.Split(".")[3] -eq $dsvmIpLastOctet })[0]
Add-LogMessage -Level Info "Looking for DSVM with IP address '$vmIpAddress'..."
if (-not $vmIpAddress) {
    Add-LogMessage -Level Fatal "No DSVM found with IP address '$vmIpAddress'. Cannot run test to confirm external DNS resolution is blocked."
} else {
    $vmName = @(Get-AzNetworkInterface | Where-Object { $_.IpConfigurations.PrivateIpAddress -eq $vmIpAddress } | ForEach-Object { $_.VirtualMachine.Id.Split("/")[-1] })[0]
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "network_configuration" "scripts" "test_external_dns_resolution_fails.sh"
    $params = @{
        SHM_DOMAIN_FQDN = $config.shm.domain.fqdn
        SHM_DC1_FQDN    = $config.shm.dc.fqdn
        SHM_DC2_FQDN    = $config.shm.dcb.fqdn
    }
    Add-LogMessage -Level Info "Testing external DNS resolution fails on VM '$vmName'..."
    $null = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
