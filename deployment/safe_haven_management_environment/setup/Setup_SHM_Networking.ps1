param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/AzureStorage.psm1 -Force
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Create VNet resource group if it does not exist
# -----------------------------------------------
$null = Deploy-ResourceGroup -Name $config.network.vnet.rg -Location $config.location


# Deploy VNet gateway from template
# ---------------------------------
Add-LogMessage -Level Info "Deploying VNet gateway from template..."
$params = @{
    IPAddresses_ExternalNTP = $config.time.ntp.serverAddresses
    NSG_Identity_Name       = $config.network.vnet.subnets.identity.nsg.name
    P2S_VPN_Certificate     = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vpnCaCertificatePlain -AsPlaintext
    Shm_Id                  = ($config.id).ToLower()
    Subnet_Firewall_CIDR    = $config.network.vnet.subnets.firewall.cidr
    Subnet_Firewall_Name    = $config.network.vnet.subnets.firewall.name
    Subnet_Gateway_CIDR     = $config.network.vnet.subnets.gateway.cidr
    Subnet_Gateway_Name     = $config.network.vnet.subnets.gateway.name
    Subnet_Identity_CIDR    = $config.network.vnet.subnets.identity.cidr
    Subnet_Identity_Name    = $config.network.vnet.subnets.identity.name
    Virtual_Network_Name    = $config.network.vnet.name
    VNET_CIDR               = $config.network.vnet.cidr
    VNET_DNS_DC1            = $config.dc.ip
    VNET_DNS_DC2            = $config.dcb.ip
    VPN_CIDR                = $config.network.vpn.cidr
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "shm-vnet-template.json") -Params $params -ResourceGroupName $config.network.vnet.rg


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
