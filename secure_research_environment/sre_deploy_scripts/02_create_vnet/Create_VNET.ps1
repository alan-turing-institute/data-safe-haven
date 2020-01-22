param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Create VNet resource group if it does not exist
# -----------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.network.vnet.rg -Location $config.sre.location


# Create VNet from template
# -------------------------
Add-LogMessage -Level Info "Creating virtual network '$($config.sre.network.vnet.name)' from template..."
$params = @{
    "Virtual Network Name" = $config.sre.network.vnet.Name
    "P2S VPN Certificate" = (Get-AzKeyVaultSecret -Name $config.shm.keyVault.secretNames.vpnCaCertificatePlain -VaultName $config.shm.keyVault.Name).SecretValue
    "Virtual Network Address Space" = $config.sre.network.vnet.cidr
    "Subnet-Identity Address Prefix" = $config.sre.network.subnets.identity.cidr
    "Subnet-RDS Address Prefix" = $config.sre.network.subnets.rds.cidr
    "Subnet-Data Address Prefix" = $config.sre.network.subnets.data.cidr
    "GatewaySubnet Address Prefix" = $config.sre.network.subnets.gateway.cidr
    "Subnet-Identity Name" = $config.sre.network.subnets.identity.Name
    "Subnet-RDS Name" = $config.sre.network.subnets.rds.Name
    "Subnet-Data Name" = $config.sre.network.subnets.data.Name
    "GatewaySubnet Name" = $config.sre.network.subnets.gateway.Name
    "DNS Server IP Address" = $config.sre.dc.ip
}
Deploy-ArmTemplate -TemplatePath "$PSScriptRoot/sre-vnet-gateway-template.json" -Params $params -ResourceGroupName $config.sre.network.vnet.rg


# Fetch VNet information
# ----------------------
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$sreVnet = Get-AzVirtualNetwork -Name $config.sre.network.vnet.Name -ResourceGroupName $config.sre.network.vnet.rg
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$shmVnet = Get-AzVirtualNetwork -Name $config.shm.network.vnet.Name -ResourceGroupName $config.shm.network.vnet.rg

# Remove existing peerings
# ------------------------
$shmPeeringName = "PEER_$($config.sre.network.vnet.Name)"
$srePeeringName = "PEER_$($config.shm.network.vnet.Name)"
# From SHM VNet
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
if ((Get-AzVirtualNetworkPeering -VirtualNetworkName $config.shm.network.vnet.name -ResourceGroupName $config.shm.network.vnet.rg) -ne $null) {
    Add-LogMessage -Level Info "[ ] Removing existing peering '$shmPeeringName' from '$($config.sre.network.vnet.name)' to '$($config.shm.network.vnet.name)'..."
    Remove-AzVirtualNetworkPeering -Name $shmPeeringName -VirtualNetworkName $config.shm.network.vnet.name -ResourceGroupName $config.shm.network.vnet.rg -Force
    if ($?) {
        Add-LogMessage -Level Success "Peering removal succeeded"
    } else {
        Add-LogMessage -Level Fatal "Peering removal failed!"
    }
}
# From SRE VNet
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
if ((Get-AzVirtualNetworkPeering -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg) -ne $null) {
    Add-LogMessage -Level Info "[ ] Removing existing peering '$srePeeringName' from '$($config.shm.network.vnet.name)' to '$($config.sre.network.vnet.name)'..."
    Remove-AzVirtualNetworkPeering -Name $srePeeringName -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -Force
    if ($?) {
        Add-LogMessage -Level Success "Peering removal succeeded"
    } else {
        Add-LogMessage -Level Fatal "Peering removal failed!"
    }
}

# Add peering to SHM Vnet
# -----------------------
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
Add-LogMessage -Level Info "[ ] Adding peering '$shmPeeringName' from '$($config.sre.network.vnet.name)' to '$($config.shm.network.vnet.name)'..."
$_ = Add-AzVirtualNetworkPeering -Name $shmPeeringName -VirtualNetwork $shmVnet -RemoteVirtualNetworkId $sreVnet.Id #-BlockVirtualNetworkAccess $false -AllowForwardedTraffic $false -AllowGatewayTransit $false -UseRemoteGateways $false
if ($?) {
    Add-LogMessage -Level Success "Peering '$($config.sre.network.vnet.name)' to '$($config.shm.network.vnet.name)' succeeded"
} else {
    Add-LogMessage -Level Fatal "Peering '$($config.sre.network.vnet.name)' to '$($config.shm.network.vnet.name)' failed!"
}


# Add peering to SRE VNet
# -----------------------
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
Add-LogMessage -Level Info "[ ] Adding peering '$srePeeringName' from '$($config.shm.network.vnet.name)' to '$($config.sre.network.vnet.name)'..."
$_ = Add-AzVirtualNetworkPeering -Name $srePeeringName -VirtualNetwork $sreVnet -RemoteVirtualNetworkId $shmVnet.Id #-BlockVirtualNetworkAccess $false -AllowForwardedTraffic $false -AllowGatewayTransit $false -UseRemoteGateways $false
if ($?) {
    Add-LogMessage -Level Success "Peering '$($config.shm.network.vnet.name)' to '$($config.sre.network.vnet.name)' succeeded"
} else {
    Add-LogMessage -Level Fatal "Peering '$($config.shm.network.vnet.name)' to '$($config.sre.network.vnet.name)' failed!"
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
