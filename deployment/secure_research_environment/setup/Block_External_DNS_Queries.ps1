param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Mandatory = $false, HelpMessage = "Last octet of IP address for DSVM to test DNS lockdown. Defaults to '160'")]
    [string]$dsvmIpLastOctet
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Mirrors.psm1 -Force
Import-Module $PSScriptRoot/../../common/Networking.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Block external DNS resolution for VMs researchers can log onto
# --------------------------------------------------------------
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "network_configuration" "scripts" "Block_External_DNS_Queries_Remote.ps1"
$params = @{
    sreId                  = "`"$($config.sre.id)`""
    sreVirtualNetworkIndex = "`"$(Get-VirtualNetworkIndex -CIDR $config.sre.network.vnet.cidr)`""
    blockedCidrsList       = "`"$($config.sre.network.vnet.subnets.data.cidr)`""
    exceptionCidrsList     = "`"$($config.sre.dataserver.ip)/32`""
}
Add-LogMessage -Level Info "Blocking external DNS resolution for researcher accessible VMs on $($config.shm.dc.vmName)..."
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value
Add-LogMessage -Level Info "Blocking external DNS resolution for researcher accessible VMs on $($config.shm.dcb.vmName)..."
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dcb.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value


# Validate external DNS resolution is blocked from DSVMs
# ------------------------------------------------------
# Get VM for provided IP address
$defaultDsvmIpLastOctet = "160"
if (-not $dsvmIpLastOctet) {
    Add-LogMessage -Level Warning "Test DSVM not specified by providing last octet of its IP address. Attempting to test on DSVM with last octet of '$defaultDsvmIpLastOctet'."
    $dsvmIpLastOctet = $defaultDsvmIpLastOctet
}
$vmIpAddress = Get-IpAddressFromRangeAndOffset -IpRangeCidr $config.sre.network.vnet.subnets.data.cidr -Offset $dsvmIpLastOctet
$existingNic = Get-AzNetworkInterface | Where-Object { $_.IpConfigurations.PrivateIpAddress -eq $vmIpAddress }
if (-not $existingNic) {
    Add-LogMessage -Level Fatal "No network card found with IP address '$vmIpAddress'. Cannot run test to confirm external DNS resolution is blocked."
} elseif (-not $existingNic.VirtualMachine.Id) {
    Add-LogMessage -Level Fatal "No VM attached to network card with IP address '$vmIpAddress'. Cannot run test to confirm external DNS resolution is blocked."
} else {
    $vmName = $existingNic.VirtualMachine.Id.Split("/")[-1]
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "network_configuration" "scripts" "test_external_dns_resolution_fails.sh"
    $params = @{
        SHM_DOMAIN_FQDN = "`"$($config.shm.domain.fqdn)`""
        SHM_DC1_FQDN    = "`"$($config.shm.dc.fqdn)`""
        SHM_DC2_FQDN    = "`"$($config.shm.dcb.fqdn)`""
    }
    Add-LogMessage -Level Info "Testing external DNS resolution fails on VM '$vmName'..."
    $result = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
    Write-Output $result.Value
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext