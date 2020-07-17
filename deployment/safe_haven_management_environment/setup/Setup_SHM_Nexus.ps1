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


# Set up the NSG for Nexus repository
# -----------------------------------
$nsgName = $config.network.nsg.repository.name
$nsgRepository = Deploy-NetworkSecurityGroup -Name $nsgName -ResourceGroupName $config.network.vnet.rg -Location $config.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsgRepository `
                             -Name "AllowRepositoryAccessFromDSVMs" `
                             -Description "Allow port 8081 (nexus) so that DSVM users can get packages" `
                             -Priority 300 `
                             -Direction Inbound `
                             -Access Allow `
                             -Protocol * `
                             -SourceAddressPrefix VirtualNetwork `
                             -SourcePortRange * `
                             -DestinationAddressPrefix $subnetRepository.AddressPrefix `
                             -DestinationPortRange 8081
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

# $null = Get-AzVM -Name $vmName -ResourceGroupName $config.mirrors.rg -ErrorVariable notExists -ErrorAction SilentlyContinue
# if ($notExists) {
# }

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
    $dataDisk = Deploy-ManagedDisk -Name "$vmName-DATA-DISK" -SizeGB $config.repository.nexus.diskSize -Type $config.repository.diskType -ResourceGroupName $config.repository.rg -Location $config.location

    # Construct cloud-init YAML file
    # ------------------------------
    $cloudInitBasePath = Join-Path $PSScriptRoot ".." "cloud_init" -Resolve
    $cloudInitFilePath = Join-Path $cloudInitBasePath "cloud-init-nexus.yaml"
    $cloudInitYaml = Get-Content $cloudInitFilePath -Raw

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
        DataDiskIds            = @($dataDisk.Id)
    }
    $null = Deploy-UbuntuVirtualMachine @params

    # Configure Nexus
    # ---------------
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_nexus.py"
    $result = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.repository.rg
    Write-Output $result.Value
} finally {
    # Remove temporary NSG rules
    Add-LogMessage -Level Info "Removing temporary outbound internet access from $($privateIpAddress)..."
    $null = Remove-AzNetworkSecurityRuleConfig -Name "OutboundAllowInternetTemporary" -NetworkSecurityGroup $nsgRepository
    $null = $nsgRepository | Set-AzNetworkSecurityGroup
}

$null = Set-AzContext -Context $originalContext
