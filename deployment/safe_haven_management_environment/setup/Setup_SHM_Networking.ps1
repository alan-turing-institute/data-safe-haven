param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureKeyVault -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureNetwork -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Cryptography -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Create VNet resource group if it does not exist
# -----------------------------------------------
$null = Deploy-ResourceGroup -Name $config.network.vnet.rg -Location $config.location


# Create VNet and subnets
# -----------------------
$vnet = Deploy-VirtualNetwork -Name $config.network.vnet.name -ResourceGroupName $config.network.vnet.rg -AddressPrefix $config.network.vnet.cidr -Location $config.location -DnsServer $config.dc.ip, $config.dcb.ip
$null = Deploy-Subnet -Name $config.network.vnet.subnets.firewall.name -VirtualNetwork $vnet -AddressPrefix $config.network.vnet.subnets.firewall.cidr
$gatewaySubnet = Deploy-Subnet -Name $config.network.vnet.subnets.gateway.name -VirtualNetwork $vnet -AddressPrefix $config.network.vnet.subnets.gateway.cidr
$identitySubnet = Deploy-Subnet -Name $config.network.vnet.subnets.identity.name -VirtualNetwork $vnet -AddressPrefix $config.network.vnet.subnets.identity.cidr
$monitoringSubnet = Deploy-Subnet -Name $config.network.vnet.subnets.monitoring.name -VirtualNetwork $vnet -AddressPrefix $config.network.vnet.subnets.monitoring.cidr
$updateServersSubnet = Deploy-Subnet -Name $config.network.vnet.subnets.updateServers.name -VirtualNetwork $vnet -AddressPrefix $config.network.vnet.subnets.updateServers.cidr


# Ensure that NSGs exist with the correct rules and attach them to the correct subnet
# -----------------------------------------------------------------------------------
# Identity
$identityNsg = Deploy-NetworkSecurityGroup -Name $config.network.vnet.subnets.identity.nsg.name -ResourceGroupName $config.network.vnet.rg -Location $config.location
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $identityNsg -Rules (Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $config.network.vnet.subnets.identity.nsg.rules) -Parameters $config -AsHashtable)
$identitySubnet = Set-SubnetNetworkSecurityGroup -Subnet $identitySubnet -NetworkSecurityGroup $identityNsg
# Monitoring
$monitoringNsg = Deploy-NetworkSecurityGroup -Name $config.network.vnet.subnets.monitoring.nsg.name -ResourceGroupName $config.network.vnet.rg -Location $config.location
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $monitoringNsg -Rules (Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $config.network.vnet.subnets.monitoring.nsg.rules) -Parameters $config -AsHashtable)
$monitoringSubnet = Set-SubnetNetworkSecurityGroup -Subnet $monitoringSubnet -NetworkSecurityGroup $monitoringNsg
# Update servers
$updateServersNsg = Deploy-NetworkSecurityGroup -Name $config.network.vnet.subnets.updateServers.nsg.name -ResourceGroupName $config.network.vnet.rg -Location $config.location
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $updateServersNsg -Rules (Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $config.network.vnet.subnets.updateServers.nsg.rules) -Parameters $config -AsHashtable)
$updateServersSubnet = Set-SubnetNetworkSecurityGroup -Subnet $updateServersSubnet -NetworkSecurityGroup $updateServersNsg


# Create the VPN gateway
# ----------------------
$publicIp = Deploy-PublicIpAddress -Name "$($config.network.vnet.name)_GW_PIP" -ResourceGroupName $config.network.vnet.rg -AllocationMethod Dynamic -Location $config.location
$certificate = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vpnCaCertificatePlain -AsPlaintext
$null = Deploy-VirtualNetworkGateway -Name "$($config.network.vnet.name)_GW" -ResourceGroupName $config.network.vnet.rg -Location $config.location -PublicIpAddressId $publicIp.Id -SubnetId $gatewaySubnet.Id -P2SCertificate $certificate -VpnClientAddressPool $config.network.vpn.cidr


# Create a route table for the SHM
# --------------------------------
$null = Deploy-RouteTable -Name $config.firewall.routeTableName -ResourceGroupName $config.network.vnet.rg -Location $config.location


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
