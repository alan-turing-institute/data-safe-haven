param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates.psm1 -Force -ErrorAction Stop


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


# Ensure that identity NSG exists with correct rules and attach it to the identity subnet
# -------------------------------------------------------------------------------------
$identityNsg = Deploy-NetworkSecurityGroup -Name $config.network.vnet.subnets.identity.nsg.name -ResourceGroupName $config.network.vnet.rg -Location $config.location
$rules = Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules"$config.network.vnet.subnets.identity.nsg.rules) -Parameters $config -AsHashtable
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $identityNsg -Rules $rules
$identitySubnet = Set-SubnetNetworkSecurityGroup -Subnet $identitySubnet -NetworkSecurityGroup $identityNsg


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
