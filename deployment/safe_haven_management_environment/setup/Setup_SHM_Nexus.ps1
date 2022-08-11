param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Which tier of mirrors should be deployed")]
    [ValidateSet("2", "3")]
    [string]$tier
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/AzureCompute.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureKeyVault -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureNetwork.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Retrieve passwords from the Key Vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.keyVault.name)'..."
$nexusAppAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.repository["tier${tier}"].nexus.nexusAppAdminPasswordSecretName -DefaultLength 20 -AsPlaintext


# Get common objects
# ------------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.storage.bootdiagnostics.accountName -ResourceGroupName $config.storage.bootdiagnostics.rg -Location $config.location
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.id)admin".ToLower() -AsPlaintext
$vmName = $config.repository["tier${tier}"].nexus.vmName
$privateIpAddress = $config.repository["tier${tier}"].nexus.ipAddress


# Ensure that package mirror and networking resource groups exist
# ---------------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.repository["tier${tier}"].rg -Location $config.location
$null = Deploy-ResourceGroup -Name $config.network.vnet.rg -Location $config.location


# Set up the VNet and subnet
# -------------------------
$vnetRepository = Deploy-VirtualNetwork -Name $config.network.repositoryVnets["tier${tier}"].name -ResourceGroupName $config.network.vnet.rg -AddressPrefix $config.network.repositoryVnets["tier${tier}"].cidr -Location $config.location
$repositorySubnet = Deploy-Subnet -Name $config.network.repositoryVnets["tier${tier}"].subnets.repository.name -VirtualNetwork $vnetRepository -AddressPrefix $config.network.repositoryVnets["tier${tier}"].subnets.repository.cidr


# Peer repository VNet to SHM VNet in order to allow it to route via the SHM firewall
# -----------------------------------------------------------------------------------
Add-LogMessage -Level Info "Peering repository virtual network to SHM virtual network"
Set-VnetPeering -Vnet1Name $vnetRepository.Name `
                -Vnet1ResourceGroupName $vnetRepository.ResourceGroupName `
                -Vnet1SubscriptionName $config.subscriptionName `
                -Vnet2Name $config.network.vnet.name `
                -Vnet2ResourceGroupName $config.network.vnet.rg `
                -Vnet2SubscriptionName $config.subscriptionName


# Attach repository subnet to SHM route table
# -------------------------------------------
Add-LogMessage -Level Info "[ ] Attaching repository subnet to SHM route table"
$routeTable = Deploy-RouteTable -Name $config.firewall.routeTableName -ResourceGroupName $config.network.vnet.rg -Location $config.location
$vnetRepository = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnetRepository -Name $repositorySubnet.Name -AddressPrefix $repositorySubnet.AddressPrefix -RouteTable $routeTable | Set-AzVirtualNetwork
if ($?) {
    Add-LogMessage -Level Success "Attached subnet '$($repositorySubnet.Name)' to SHM route table."
} else {
    Add-LogMessage -Level Fatal "Failed to attach subnet '$($repositorySubnet.Name)' to SHM route table!"
}


# Ensure that Nexus NSG exists with correct rules and attach it to the Nexus subnet
# ---------------------------------------------------------------------------------
$repositoryNsg = Deploy-NetworkSecurityGroup -Name $config.network.repositoryVnets["tier${tier}"].subnets.repository.nsg.name -ResourceGroupName $config.network.vnet.rg -Location $config.location
$rules = Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $config.network.repositoryVnets["tier${tier}"].subnets.repository.nsg.rules) -Parameters $config -AsHashtable
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $repositoryNsg -Rules $rules
$repositorySubnet = Set-SubnetNetworkSecurityGroup -Subnet $repositorySubnet -NetworkSecurityGroup $repositoryNsg


# Construct cloud-init YAML file
# ------------------------------
$cloudInitBasePath = Join-Path $PSScriptRoot ".." "cloud_init" -Resolve
$BasePath = Join-Path $PSScriptRoot ".." ".." ".." -Resolve
$config["nexus"] = @{
    adminPassword = $nexusAppAdminPassword
    tier          = $tier
}
# Load the cloud-init template then add resources and expand mustache placeholders
$cloudInitTemplate = Get-Content (Join-Path $cloudInitBasePath "cloud-init-nexus.mustache.yaml") -Raw
$cloudInitTemplate = Expand-CloudInitResources -Template $cloudInitTemplate -ResourcePath (Join-Path $cloudInitBasePath "resources")
$cloudInitTemplate = Expand-CloudInitResources -Template $cloudInitTemplate -ResourcePath (Join-Path $BasePath "environment_configs" "package_lists")
$cloudInitTemplate = Expand-MustacheTemplate -Template $cloudInitTemplate -Parameters $config


# Deploy the VM
# -------------
$vmNic = Deploy-NetworkInterface -Name "$vmName-NIC" -ResourceGroupName $config.repository["tier${tier}"].rg -Subnet $repositorySubnet -PrivateIpAddress $privateIpAddress -Location $config.location
$params = @{
    Name                   = $vmName
    Size                   = $config.repository["tier${tier}"].vmSize
    AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.repository["tier${tier}"].nexus.adminPasswordSecretName -DefaultLength 20)
    AdminUsername          = $vmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $cloudInitTemplate
    Location               = $config.location
    NicId                  = $vmNic.Id
    OsDiskType             = $config.repository["tier${tier}"].diskType
    ResourceGroupName      = $config.repository["tier${tier}"].rg
    ImageSku               = "Ubuntu-latest"
}
$null = Deploy-LinuxVirtualMachine @params
Start-VM -Name $vmName -ResourceGroupName $config.repository["tier${tier}"].rg


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
