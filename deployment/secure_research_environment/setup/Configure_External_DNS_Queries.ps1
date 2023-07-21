param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId,
    [Parameter(Mandatory = $false, HelpMessage = "Last octet of IP address for SRD to test DNS lockdown. Defaults to '160'")]
    [string]$srdIpLastOctet
)
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzurePrivateDns -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop

# Construct list of always-allowed FQDNs
# --------------------------------------
$firewallRules = Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." ".." "safe_haven_management_environment" "network_rules" "shm-firewall-rules.json") -Parameters $config.shm -AsHashtable
$allowedFqdns = @($firewallRules.applicationRuleCollections | ForEach-Object { $_.properties.rules.targetFqdns }) +
                @(Get-PrivateDnsZones -ResourceGroupName $config.shm.network.vnet.rg -SubscriptionName $config.shm.subscriptionName | ForEach-Object { $_.Name })
# List all unique FQDNs
$allowedFqdns = $allowedFqdns |
                Where-Object { $_ -notlike "*-sb.servicebus.windows.net" } | # Remove AzureADConnect password reset endpoints
                Where-Object { $_ -notlike "pksproddatastore*.blob.core.windows.net" } | # Remove AzureAD operations endpoints
                Sort-Object -Unique
Add-LogMessage -Level Info "Restricted networks will be allowed to run DNS lookup on the following $($allowedFqdns.Count) FQDNs:"
foreach ($allowedFqdn in $allowedFqdns) { Add-LogMessage -Level Info "... $allowedFqdn" }
# Allow DNS resolution for arbitrary subdomains under a private link
# Note: this does NOT guarantee that we control the subdomain, but there is currently no way to dynamically resolve only those subdomains belonging to the private link
$allowedFqdns = $allowedFqdns | ForEach-Object { $_.Replace("privatelink", "*") }


# Construct lists of CIDRs to apply restrictions to
# -------------------------------------------------
if ($config.sre.remoteDesktop.networkRules.outboundInternet -eq "Allow") {
    $cidrsToRestrict = @()
    $cidrsToAllow = @($config.sre.network.vnet.subnets.compute.cidr, $config.sre.network.vnet.subnets.databases.cidr, $config.sre.network.vnet.subnets.deployment.cidr, $config.sre.network.vnet.subnets.webapps.cidr)
} else {
    $cidrsToRestrict = @($config.sre.network.vnet.subnets.compute.cidr, $config.sre.network.vnet.subnets.databases.cidr, $config.sre.network.vnet.subnets.webapps.cidr)
    $cidrsToAllow = @($config.sre.network.vnet.subnets.deployment.cidr)
}


# Configure external DNS resolution for SRDs via SHM DNS servers
# --------------------------------------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
$params = @{
    AllowedFqdnsCommaSeparatedList      = ($allowedFqdns -join ",")
    RestrictedCidrsCommaSeparatedList   = ($cidrsToRestrict -join ",")
    SreId                               = $config.sre.id
    UnrestrictedCidrsCommaSeparatedList = ($cidrsToAllow -join ",")
}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "network_configuration" "scripts" "Configure_External_DNS_Queries_Remote.ps1"
foreach ($dnsServerName in @($config.shm.dc.vmName, $config.shm.dcb.vmName)) {
    Add-LogMessage -Level Info "Configuring external DNS resolution for SRDs via ${dnsServerName}..."
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $dnsServerName -ResourceGroupName $config.shm.dc.rg -Parameter $params
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Validate external DNS resolution is blocked from SRDs
# -----------------------------------------------------
# Get VM for provided IP address
$computeVmIds = @(Get-AzVM -ResourceGroupName $config.sre.srd.rg | ForEach-Object { $_.Id })
$computeVmIpAddresses = @(Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -in $computeVmIds } | ForEach-Object { $_.IpConfigurations.PrivateIpAddress })
if (-not $srdIpLastOctet) {
    $srdIpLastOctet = $computeVmIpAddresses[0].Split(".")[3]
    Add-LogMessage -Level Warning "Test SRD not specified by providing last octet of its IP address. Attempting to test on SRD with last octet of '$srdIpLastOctet'."
}
$vmIpAddress = @($computeVmIpAddresses | Where-Object { $_.Split(".")[3] -eq $srdIpLastOctet })[0]
Add-LogMessage -Level Info "Looking for SRD with IP address '$vmIpAddress'..."
if (-not $vmIpAddress) {
    Add-LogMessage -Level Fatal "No SRD found with IP address '$vmIpAddress'. Cannot run test to confirm external DNS resolution."
} else {
    # Match on IP address within approriate SRE resource group
    $vmName = @(Get-AzNetworkInterface -ResourceGroupName $config.sre.srd.rg | Where-Object { $_.IpConfigurations.PrivateIpAddress -eq $vmIpAddress } | ForEach-Object { $_.VirtualMachine.Id.Split("/")[-1] })[0]
    Add-LogMessage -Level Info "Testing external DNS resolution on VM '$vmName'..."
    $params = @{
        SHM_DOMAIN_FQDN   = $config.shm.domain.fqdn
        SHM_DC1_FQDN      = $config.shm.dc.fqdn
        SHM_DC2_FQDN      = $config.shm.dcb.fqdn
        OUTBOUND_INTERNET = $config.sre.remoteDesktop.networkRules.outboundInternet
    }
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "network_configuration" "scripts" "test_external_dns_resolution_fails.sh"
    $null = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.srd.rg -Parameter $params
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
