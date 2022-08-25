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


# Create main virtual network and subnets
# ---------------------------------------
$vnet = Deploy-VirtualNetwork -Name $config.network.vnet.name -ResourceGroupName $config.network.vnet.rg -AddressPrefix $config.network.vnet.cidr -Location $config.location -DnsServer $config.dc.ip, $config.dcb.ip
$null = Deploy-Subnet -Name $config.network.vnet.subnets.firewall.name -AddressPrefix $config.network.vnet.subnets.firewall.cidr -VirtualNetwork $vnet
$gatewaySubnet = Deploy-Subnet -Name $config.network.vnet.subnets.gateway.name -AddressPrefix $config.network.vnet.subnets.gateway.cidr -VirtualNetwork $vnet
$identitySubnet = Deploy-Subnet -Name $config.network.vnet.subnets.identity.name -AddressPrefix $config.network.vnet.subnets.identity.cidr -VirtualNetwork $vnet
$monitoringSubnet = Deploy-Subnet -Name $config.network.vnet.subnets.monitoring.name -AddressPrefix $config.network.vnet.subnets.monitoring.cidr -VirtualNetwork $vnet
$updateServersSubnet = Deploy-Subnet -Name $config.network.vnet.subnets.updateServers.name -AddressPrefix $config.network.vnet.subnets.updateServers.cidr -VirtualNetwork $vnet


# Create package repository virtual networks and subnets
# ------------------------------------------------------
# Tier 2
$vnetRepositoriesTier2 = Deploy-VirtualNetwork -Name $config.network.vnetRepositoriesTier2.name -ResourceGroupName $config.network.vnetRepositoriesTier2.rg -AddressPrefix $config.network.vnetRepositoriesTier2.cidr -Location $config.location
$mirrorsExternalTier2Subnet = Deploy-Subnet -Name $config.network.vnetRepositoriesTier2.subnets.mirrorsExternal.name -AddressPrefix $config.network.vnetRepositoriesTier2.subnets.mirrorsExternal.cidr -VirtualNetwork $vnetRepositoriesTier2
$mirrorsInternalTier2Subnet = Deploy-Subnet -Name $config.network.vnetRepositoriesTier2.subnets.mirrorsInternal.name -AddressPrefix $config.network.vnetRepositoriesTier2.subnets.mirrorsInternal.cidr -VirtualNetwork $vnetRepositoriesTier2
$proxiesTier2Subnet = Deploy-Subnet -Name $config.network.vnetRepositoriesTier2.subnets.proxies.name -AddressPrefix $config.network.vnetRepositoriesTier2.subnets.proxies.cidr -VirtualNetwork $vnetRepositoriesTier2
$deploymentTier2Subnet = Deploy-Subnet -Name $config.network.vnetRepositoriesTier2.subnets.deployment.name -AddressPrefix $config.network.vnetRepositoriesTier2.subnets.deployment.cidr -VirtualNetwork $vnetRepositoriesTier2
# Tier 3
$vnetRepositoriesTier3 = Deploy-VirtualNetwork -Name $config.network.vnetRepositoriesTier3.name -ResourceGroupName $config.network.vnetRepositoriesTier3.rg -AddressPrefix $config.network.vnetRepositoriesTier3.cidr -Location $config.location
$mirrorsExternalTier3Subnet = Deploy-Subnet -Name $config.network.vnetRepositoriesTier3.subnets.mirrorsExternal.name -AddressPrefix $config.network.vnetRepositoriesTier3.subnets.mirrorsExternal.cidr -VirtualNetwork $vnetRepositoriesTier3
$mirrorsInternalTier3Subnet = Deploy-Subnet -Name $config.network.vnetRepositoriesTier3.subnets.mirrorsInternal.name -AddressPrefix $config.network.vnetRepositoriesTier3.subnets.mirrorsInternal.cidr -VirtualNetwork $vnetRepositoriesTier3
$proxiesTier3Subnet = Deploy-Subnet -Name $config.network.vnetRepositoriesTier3.subnets.proxies.name -AddressPrefix $config.network.vnetRepositoriesTier3.subnets.proxies.cidr -VirtualNetwork $vnetRepositoriesTier3
$deploymentTier3Subnet = Deploy-Subnet -Name $config.network.vnetRepositoriesTier3.subnets.deployment.name -AddressPrefix $config.network.vnetRepositoriesTier3.subnets.deployment.cidr -VirtualNetwork $vnetRepositoriesTier3
# As we do not currently support Tier 4 we do not deploy any networks for it


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
# Tier 2 external mirrors
$mirrorsExternalTier2Nsg = Deploy-NetworkSecurityGroup -Name $config.network.vnetRepositoriesTier2.subnets.mirrorsExternal.nsg.name -ResourceGroupName $config.network.vnetRepositoriesTier2.rg -Location $config.location
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $mirrorsExternalTier2Nsg -Rules (Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $config.network.vnetRepositoriesTier2.subnets.mirrorsExternal.nsg.rules) -Parameters $config -AsHashtable)
$mirrorsExternalTier2Subnet = Set-SubnetNetworkSecurityGroup -Subnet $mirrorsExternalTier2Subnet -NetworkSecurityGroup $mirrorsExternalTier2Nsg
# Tier 2 internal mirrors
$mirrorsInternalTier2Nsg = Deploy-NetworkSecurityGroup -Name $config.network.vnetRepositoriesTier2.subnets.mirrorsInternal.nsg.name -ResourceGroupName $config.network.vnetRepositoriesTier2.rg -Location $config.location
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $mirrorsInternalTier2Nsg -Rules (Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $config.network.vnetRepositoriesTier2.subnets.mirrorsInternal.nsg.rules) -Parameters $config -AsHashtable)
$mirrorsInternalTier2Subnet = Set-SubnetNetworkSecurityGroup -Subnet $mirrorsInternalTier2Subnet -NetworkSecurityGroup $mirrorsInternalTier2Nsg
# Tier 2 proxies
$proxiesTier2Nsg = Deploy-NetworkSecurityGroup -Name $config.network.vnetRepositoriesTier2.subnets.proxies.nsg.name -ResourceGroupName $config.network.vnetRepositoriesTier2.rg -Location $config.location
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $proxiesTier2Nsg -Rules (Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $config.network.vnetRepositoriesTier2.subnets.proxies.nsg.rules) -Parameters $config -AsHashtable)
$proxiesTier2Subnet = Set-SubnetNetworkSecurityGroup -Subnet $proxiesTier2Subnet -NetworkSecurityGroup $proxiesTier2Nsg
# Tier 2 deployment
$deploymentTier2Nsg = Deploy-NetworkSecurityGroup -Name $config.network.vnetRepositoriesTier2.subnets.deployment.nsg.name -ResourceGroupName $config.network.vnetRepositoriesTier2.rg -Location $config.location
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $deploymentTier2Nsg -Rules (Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $config.network.vnetRepositoriesTier2.subnets.deployment.nsg.rules) -Parameters $config -AsHashtable)
$deploymentTier2Subnet = Set-SubnetNetworkSecurityGroup -Subnet $deploymentTier2Subnet -NetworkSecurityGroup $deploymentTier2Nsg
# Tier 3 external mirrors
$mirrorsExternalTier3Nsg = Deploy-NetworkSecurityGroup -Name $config.network.vnetRepositoriesTier3.subnets.mirrorsExternal.nsg.name -ResourceGroupName $config.network.vnetRepositoriesTier3.rg -Location $config.location
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $mirrorsExternalTier3Nsg -Rules (Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $config.network.vnetRepositoriesTier3.subnets.mirrorsExternal.nsg.rules) -Parameters $config -AsHashtable)
$mirrorsExternalTier3Subnet = Set-SubnetNetworkSecurityGroup -Subnet $mirrorsExternalTier3Subnet -NetworkSecurityGroup $mirrorsExternalTier3Nsg
# Tier 3 internal mirrors
$mirrorsInternalTier3Nsg = Deploy-NetworkSecurityGroup -Name $config.network.vnetRepositoriesTier3.subnets.mirrorsInternal.nsg.name -ResourceGroupName $config.network.vnetRepositoriesTier3.rg -Location $config.location
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $mirrorsInternalTier3Nsg -Rules (Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $config.network.vnetRepositoriesTier3.subnets.mirrorsInternal.nsg.rules) -Parameters $config -AsHashtable)
$mirrorsInternalTier3Subnet = Set-SubnetNetworkSecurityGroup -Subnet $mirrorsInternalTier3Subnet -NetworkSecurityGroup $mirrorsInternalTier3Nsg
# Tier 3 proxies
$proxiesTier3Nsg = Deploy-NetworkSecurityGroup -Name $config.network.vnetRepositoriesTier3.subnets.proxies.nsg.name -ResourceGroupName $config.network.vnetRepositoriesTier3.rg -Location $config.location
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $proxiesTier3Nsg -Rules (Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $config.network.vnetRepositoriesTier3.subnets.proxies.nsg.rules) -Parameters $config -AsHashtable)
$proxiesTier3Subnet = Set-SubnetNetworkSecurityGroup -Subnet $proxiesTier3Subnet -NetworkSecurityGroup $proxiesTier3Nsg
# Tier 3 deployment
$deploymentTier3Nsg = Deploy-NetworkSecurityGroup -Name $config.network.vnetRepositoriesTier3.subnets.deployment.nsg.name -ResourceGroupName $config.network.vnetRepositoriesTier3.rg -Location $config.location
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $deploymentTier3Nsg -Rules (Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $config.network.vnetRepositoriesTier3.subnets.deployment.nsg.rules) -Parameters $config -AsHashtable)
$deploymentTier3Subnet = Set-SubnetNetworkSecurityGroup -Subnet $deploymentTier3Subnet -NetworkSecurityGroup $deploymentTier3Nsg


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
