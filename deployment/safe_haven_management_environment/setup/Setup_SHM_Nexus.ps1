param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Which tier of mirrors should be deployed")]
    [ValidateSet("2", "3")]
    [string]$tier
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/AzureStorage.psm1 -Force
Import-Module $PSScriptRoot/../../common/Templates.psm1 -Force
Import-Module $PSScriptRoot/../../common/Networking.psm1 -Force
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Check requested tier
# --------------------
if ($tier -ne "2") {
    Add-LogMessage -Level Fatal "Currently Nexus only supports tier-2 repositories!"
}


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Retrieve passwords from the key vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.keyVault.name)'..."
$nexusAppAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.repository.nexus.nexusAppAdminPasswordSecretName -DefaultLength 20 -AsPlaintext


# Get common objects
# ------------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.storage.bootdiagnostics.accountName -ResourceGroupName $config.storage.bootdiagnostics.rg -Location $config.location
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.id)admin".ToLower() -AsPlaintext
$vmName = $config.repository.nexus.vmName
$privateIpAddress = $config.repository.nexus.ipAddress


# Ensure that package mirror and networking resource groups exist
# ---------------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.repository.rg -Location $config.location
$null = Deploy-ResourceGroup -Name $config.network.vnet.rg -Location $config.location


# Set up the VNet and subnet
# -------------------------
$vnetRepository = Deploy-VirtualNetwork -Name $config.network.repositoryVnet.name -ResourceGroupName $config.network.vnet.rg -AddressPrefix $config.network.repositoryVnet.cidr -Location $config.location
$repositorySubnet = Deploy-Subnet -Name $config.network.repositoryVnet.subnets.repository.name -VirtualNetwork $vnetRepository -AddressPrefix $config.network.repositoryVnet.subnets.repository.cidr


# Attach repository subnet to SHM route table
# -------------------------------------------
Add-LogMessage -Level Info "[ ] Attaching repository subnet to SHM route table"
$routeTable = Get-AzRouteTable | Where-Object { $_.Name -eq $config.firewall.routeTableName }
$vnetRepository = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnetRepository -Name $config.network.repositoryVnet.subnets.repository.name -AddressPrefix $config.network.repositoryVnet.subnets.repository.cidr -RouteTable $routeTable | Set-AzVirtualNetwork
if ($?) {
    Add-LogMessage -Level Success "Attached subnet '$($repositorySubnet.Name)' to SHM route table."
} else {
    Add-LogMessage -Level Fatal "Failed to attach subnet '$($repositorySubnet.Name)' to SHM route table!"
}


# Peer repository vnet to SHM vnet
# --------------------------------
Add-LogMessage -Level Info "Peering repository virtual network to SHM virtual network"
Set-VnetPeering -Vnet1Name $config.network.repositoryVnet.name `
                -Vnet1ResourceGroup $config.network.vnet.rg `
                -Vnet1SubscriptionName $config.subscriptionName `
                -Vnet2Name $config.network.vnet.name `
                -Vnet2ResourceGroup $config.network.vnet.rg `
                -Vnet2SubscriptionName $config.subscriptionName


# Ensure that Nexus NSG exists with correct rules and attach it to the Nexus subnet
# ---------------------------------------------------------------------------------
$repositoryNsg = Deploy-NetworkSecurityGroup -Name $config.network.repositoryVnet.subnets.repository.nsg.name -ResourceGroupName $config.network.vnet.rg -Location $config.location
$tmpConfig = @{"network" = @{"repositoryVnet" = @{"subnets" = @{"repository" = @{"cidr" = $config.network.repositoryVnet.subnets.repository.cidr } } } } } # Note that PR #873 has the fix which means that this will no longer be needed
$rules = Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $config.network.repositoryVnet.subnets.repository.nsg.rules) -ArrayJoiner '"' -Parameters $tmpConfig -AsHashtable
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $repositoryNsg -Rules $rules
$repositorySubnet = Set-SubnetNetworkSecurityGroup -Subnet $repositorySubnet -NetworkSecurityGroup $repositoryNsg


# Construct cloud-init YAML file
# ------------------------------
$cloudInitBasePath = Join-Path $PSScriptRoot ".." "cloud_init" -Resolve
$cloudInitTemplate = Get-Content (Join-Path $cloudInitBasePath "cloud-init-nexus.yaml") -Raw
# Insert additional files into the cloud-init template
foreach ($resource in (Get-ChildItem (Join-Path $cloudInitBasePath "resources"))) {
    $indent = $cloudInitTemplate -split "`n" | Where-Object { $_ -match "<$($resource.Name)>" } | ForEach-Object { $_.Split("<")[0] } | Select-Object -First 1
    $indentedContent = (Get-Content $resource.FullName -Raw) -split "`n" | ForEach-Object { "${indent}$_" } | Join-String -Separator "`n"
    $cloudInitTemplate = $cloudInitTemplate.Replace("${indent}<$($resource.Name)>", $indentedContent)
}
# Expand placeholders in the cloud-init template
$cloudInitTemplate = $cloudInitTemplate.
    Replace("<nexus-admin-password>", $nexusAppAdminPassword).
    Replace("<ntp-server>", $config.time.ntp.poolFqdn).
    Replace("<tier>", $tier).
    Replace("<timezone>", $config.time.timezone.linux)


# Deploy the VM
# -------------
$vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.repository.rg -Subnet $repositorySubnet -PrivateIpAddress $privateIpAddress -Location $config.location
$params = @{
    Name                   = $vmName
    Size                   = $config.repository.vmSize
    AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.repository.nexus.adminPasswordSecretName -DefaultLength 20)
    AdminUsername          = $vmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $cloudInitTemplate
    Location               = $config.location
    NicId                  = $vmNic.Id
    OsDiskType             = $config.repository.diskType
    ResourceGroupName      = $config.repository.rg
    ImageSku               = "18.04-LTS"
}
$null = Deploy-UbuntuVirtualMachine @params
Start-VM -Name $vmName -ResourceGroupName $config.repository.rg


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
