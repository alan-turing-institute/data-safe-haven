param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName


# Retrieve passwords from the key vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.keyVault.name)'..."
$nexusAppAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.repository.nexus.nexusAppAdminPasswordSecretName -DefaultLength 20


# Get common objects
# ------------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.storage.bootdiagnostics.accountName -ResourceGroupName $config.storage.bootdiagnostics.rg -Location $config.location
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.id)admin".ToLower()

$vmName = $config.repository.nexus.vmName
$privateIpAddress = $config.repository.nexus.ipAddress


# Ensure that package mirror and networking resource groups exist
# ---------------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.repository.rg -Location $config.location
$null = Deploy-ResourceGroup -Name $config.network.vnet.rg -Location $config.location


# Set up the VNet and subnet
# -------------------------
$vnetRepository = Deploy-VirtualNetwork -Name $config.network.repositoryVnet.name -ResourceGroupName $config.network.vnet.rg -AddressPrefix $config.network.repositoryVnet.cidr -Location $config.location
$subnetRepository = Deploy-Subnet -Name $config.network.repositoryVnet.subnets.repository.name -VirtualNetwork $vnetRepository -AddressPrefix $config.network.repositoryVnet.subnets.repository.cidr


# Attach repository subnet to SHM firewall route table
# ----------------------------------------------------
Add-LogMessage -Level Info "[ ] Attaching repository subnet to SHM firewall route table"
$routeTable = Get-AzRouteTable | Where-Object { $_.Name -eq $config.firewall.routeTableName }
$vnetRepository = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnetRepository -Name $config.network.repositoryVnet.subnets.repository.name -AddressPrefix $config.network.repositoryVnet.subnets.repository.cidr -RouteTable $routeTable | Set-AzVirtualNetwork
if ($?) {
    Add-LogMessage -Level Success "Route table attached"
} else {
    Add-LogMessage -Level Fatal "Attaching route table failed!"
}


# Peer repository vnet to SHM vnet
# --------------------------------
Add-LogMessage -Level Info "Peering repository vnet to shm vnet"
Set-VnetPeering -Vnet1Name $config.network.repositoryVnet.name -Vnet1ResourceGroup $config.network.vnet.rg -Vnet1SubscriptionName $config.subscriptionName -Vnet2Name $config.network.vnet.name -Vnet2ResourceGroup $config.network.vnet.rg -Vnet2SubscriptionName $config.subscriptionName


# Set up the NSG for Nexus repository
# -----------------------------------
$nsgName = $config.network.nsg.repository.name
$nsgRepository = Deploy-NetworkSecurityGroup -Name $nsgName -ResourceGroupName $config.network.vnet.rg -Location $config.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgRepository `
                             -Name "AllowRepositoryAccessFromDSVMs" `
                             -Description "Allow port 80 (nexus) so that DSVM users can get packages" `
                             -Priority 300 `
                             -Direction Inbound `
                             -Access Allow `
                             -Protocol * `
                             -SourceAddressPrefix VirtualNetwork `
                             -SourcePortRange * `
                             -DestinationAddressPrefix $subnetRepository.AddressPrefix `
                             -DestinationPortRange 80
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgRepository `
                             -Name "IgnoreInboundRulesBelowHere" `
                             -Description "Deny all other inbound" `
                             -Priority 3000 `
                             -Direction Inbound `
                             -Access Deny `
                             -Protocol * `
                             -SourceAddressPrefix * `
                             -SourcePortRange * `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange *
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgRepository `
                             -Name "AllowPackageFetchingFromInternet" `
                             -Description "Allow ports 443 (https) and 80 (http) for fetching packages" `
                             -Priority 300 `
                             -Direction Outbound `
                             -Access Allow `
                             -Protocol * `
                             -SourceAddressPrefix $subnetRepository.AddressPrefix `
                             -SourcePortRange * `
                             -DestinationAddressPrefix Internet `
                             -DestinationPortRange 443, 80
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgRepository `
                             -Name "IgnoreOutboundRulesBelowHere" `
                             -Description "Deny all other outbound" `
                             -Priority 3000 `
                             -Direction Outbound `
                             -Access Deny `
                             -Protocol * `
                             -SourceAddressPrefix * `
                             -SourcePortRange * `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange *
$subnetRepository = Set-SubnetNetworkSecurityGroup -Subnet $subnetRepository -NetworkSecurityGroup $nsgRepository -VirtualNetwork $vnetRepository
if ($?) {
    Add-LogMessage -Level Success "Configuring NSG '$nsgName' succeeded"
} else {
    Add-LogMessage -Level Fatal "Configuring NSG '$nsgName' failed!"
}


try {
    # Temporarily allow outbound internet during deployment
    # -----------------------------------------------------
    Add-LogMessage -Level Warning "Temporarily allowing outbound internet access from $($privateIpAddress)..."
    Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgRepository `
                                 -Name "OutboundAllowInternetTemporary" `
                                 -Description "Outbound allow internet" `
                                 -Priority 100 `
                                 -Direction Outbound `
                                 -Access Allow -Protocol * `
                                 -SourceAddressPrefix $privateIpAddress `
                                 -SourcePortRange * `
                                 -DestinationAddressPrefix Internet `
                                 -DestinationPortRange *
    # Deploy NIC and data disks
    # -------------------------
    $vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.repository.rg -Subnet $subnetRepository -PrivateIpAddress $privateIpAddress -Location $config.location

    # Construct cloud-init YAML file
    # ------------------------------
    $cloudInitBasePath = Join-Path $PSScriptRoot ".." "cloud_init" -Resolve
    $cloudInitFilePath = Join-Path $cloudInitBasePath "cloud-init-nexus.yaml"
    $cloudInitYaml = Get-Content $cloudInitFilePath -Raw
    # Insert Nexus configuration script into cloud-init
    $indent = "      "
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_nexus.py"
    $raw_script = Get-Content $scriptPath -Raw
    $indented_script = $raw_script -split "`n" | ForEach-Object { "${indent}$_" } | Join-String -Separator "`n"
    $cloudInitYaml = $cloudInitYaml.Replace("${indent}<configure_nexus.py>", $indented_script)
    $cloudInitYaml = $cloudInitYaml.Replace("<nexus-admin-password>", $nexusAppAdminPassword)

    $adminPasswordSecretName = $config.repository.nexus.adminPasswordSecretName
    # Deploy the VM
    $params = @{
        Name                   = $vmName
        Size                   = $config.repository.vmSize
        AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $adminPasswordSecretName -DefaultLength 20)
        AdminUsername          = $vmAdminUsername
        BootDiagnosticsAccount = $bootDiagnosticsAccount
        CloudInitYaml          = $cloudInitYaml
        Location               = $config.location
        NicId                  = $vmNic.Id
        OsDiskType             = $config.repository.diskType
        ResourceGroupName      = $config.repository.rg
        ImageSku               = "18.04-LTS"
    }
    $null = Deploy-UbuntuVirtualMachine @params

} finally {
    # Remove temporary NSG rules
    Add-LogMessage -Level Info "Removing temporary outbound internet access from $($privateIpAddress)..."
    $null = Remove-AzNetworkSecurityRuleConfig -Name "OutboundAllowInternetTemporary" -NetworkSecurityGroup $nsgRepository
    $null = $nsgRepository | Set-AzNetworkSecurityGroup
}

Enable-AzVM -Name $vmName -ResourceGroupName $config.repository.rg

$null = Set-AzContext -Context $originalContext
