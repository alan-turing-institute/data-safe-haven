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
Import-Module $PSScriptRoot/../../common/AzurePrivateDns -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Construct list of always-allowed FQDNs
# --------------------------------------
$templateParams = $config.shm
$templateParams.logging["workspaceId"] = (Deploy-LogAnalyticsWorkspace -Name $config.shm.monitoring.loggingWorkspace.name -ResourceGroupName $config.shm.monitoring.rg -Location $config.sre.location).CustomerId
$firewallRules = Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." ".." "safe_haven_management_environment" "network_rules" "shm-firewall-rules.json") -Parameters $templateParams -AsHashtable
$allowedFqdns = $firewallRules.applicationRuleCollections | ForEach-Object { $_.properties.rules.targetFqdns } | Sort-Object -Unique
$allowedFqdns += Get-PrivateDnsZones -ResourceGroupName $config.shm.network.vnet.rg -SubscriptionName $config.shm.subscriptionName | ForEach-Object { $_.Name.Replace("privatelink", "*") }


# Construct lists of CIDRs to apply restrictions to
# -------------------------------------------------
$cidrsToRestrict = ($config.sre.remoteDesktop.networkRules.outboundInternet -eq "Allow") ? @() : @($config.sre.network.vnet.subnets.compute.cidr, $config.sre.network.vnet.subnets.databases.cidr, $config.sre.network.vnet.subnets.webapps.cidr)
$cidrsToAllow = @($config.sre.network.vnet.subnets.deployment.cidr)


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
    $vmName = @(Get-AzNetworkInterface | Where-Object { $_.IpConfigurations.PrivateIpAddress -eq $vmIpAddress } | ForEach-Object { $_.VirtualMachine.Id.Split("/")[-1] })[0]
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
