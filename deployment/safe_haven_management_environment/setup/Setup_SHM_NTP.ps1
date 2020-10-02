param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/GenerateSasToken.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName


# Ensure that NTP resource group exists
# ---------------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.ntp.rg -Location $config.location


# Ensure that NTP subnet exists
# -----------------------------
$virtualNetwork = Get-AzVirtualNetwork -Name $config.network.vnet.name -ResourceGroupName $config.network.vnet.rg
$subnet = Deploy-Subnet -Name $config.network.vnet.subnets.ntp.name -VirtualNetwork $virtualNetwork -AddressPrefix $config.network.vnet.subnets.ntp.cidr


# Set up the NSG for external package mirrors
# -------------------------------------------
$nsg = Deploy-NetworkSecurityGroup -Name $config.network.nsg.ntp.name -ResourceGroupName $config.network.vnet.rg -Location $config.location
# Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
#                              -Name "IgnoreInboundRulesBelowHere" `
#                              -Description "Deny all other inbound" `
#                              -Priority 3000 `
#                              -Direction Inbound `
#                              -Access Deny `
#                              -Protocol * `
#                              -SourceAddressPrefix * `
#                              -SourcePortRange * `
#                              -DestinationAddressPrefix * `
#                              -DestinationPortRange *
# Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
#                              -Name "UpdateFromInternet" `
#                              -Description "Allow ports 443 (https) and 873 (unencrypted rsync) for updating mirrors" `
#                              -Priority 300 `
#                              -Direction Outbound `
#                              -Access Allow `
#                              -Protocol TCP `
#                              -SourceAddressPrefix $subnetExternal.AddressPrefix `
#                              -SourcePortRange * `
#                              -DestinationAddressPrefix Internet `
#                              -DestinationPortRange 443, 873
# Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
#                              -Name "IgnoreOutboundRulesBelowHere" `
#                              -Description "Deny all other outbound" `
#                              -Priority 3000 `
#                              -Direction Outbound `
#                              -Access Deny `
#                              -Protocol * `
#                              -SourceAddressPrefix * `
#                              -SourcePortRange * `
#                              -DestinationAddressPrefix * `
#                              -DestinationPortRange *
if ($?) {
    Add-LogMessage -Level Success "Configuring NSG '$($config.network.nsg.ntp.name)' succeeded"
} else {
    Add-LogMessage -Level Fatal "Configuring NSG '$($config.network.nsg.ntp.name)' failed!"
}

# Retrieve common objects
# -----------------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.storage.bootdiagnostics.accountName -ResourceGroupName $config.storage.bootdiagnostics.rg -Location $config.location
$networkCard = Deploy-VirtualMachineNIC -Name "$($config.ntp.vmName)-NIC" -ResourceGroupName $config.ntp.rg -Subnet $subnet -PrivateIpAddress $config.ntp.ip -Location $config.location


# Retrieve key vault secrets
# --------------------------
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.id)admin".ToLower()
$vmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.ntp.adminPasswordSecretName -DefaultLength 20


# Load template cloud-init file
# -----------------------------
$cloudInitYaml = Get-Content (Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-ntp.yaml") -Raw
$cloudInitYaml = $cloudInitYaml.Replace("<timezone>", $config.timezone.linux)


# Deploy the VM
# -------------
$params = @{
    Name                   = $config.ntp.vmName
    Size                   = $config.ntp.vmSize
    AdminPassword          = $vmAdminPassword
    AdminUsername          = $vmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $cloudInitYaml
    Location               = $config.location
    NicId                  = $networkCard.Id
    OsDiskType             = $config.ntp.disks.os.type
    OsDiskSize             = $config.ntp.disks.os.sizeGb
    ResourceGroupName      = $config.ntp.rg
    ImageSku               = "18.04-LTS"
}
$null = Deploy-UbuntuVirtualMachine @params
Enable-AzVM -Name $config.ntp.vmName -ResourceGroupName $config.ntp.rg


# Set-SubnetNetworkSecurityGroup


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
