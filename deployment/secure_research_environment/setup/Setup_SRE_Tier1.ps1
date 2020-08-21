param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


$keyVault = $config.sre.keyVault.name


# Ensure that NSG exists
# ----------------------
$nsg = Deploy-NetworkSecurityGroup -Name $config.sre.dsvm.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                             -Name "OutboundInternetAccess" `
                             -Description "Outbound internet access" `
                             -Priority 2000 `
                             -Direction Outbound `
                             -Access Deny `
                             -Protocol * `
                             -SourceAddressPrefix VirtualNetwork `
                             -SourcePortRange * `
                             -DestinationAddressPrefix Internet `
                             -DestinationPortRange *
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                             -Name "OutboundDenyAll" `
                             -Description "Outbound deny all" `
                             -Priority 3000 `
                             -Direction Outbound `
                             -Access Deny `
                             -Protocol * `
                             -SourceAddressPrefix * `
                             -SourcePortRange * `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange *
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                             -Name "InboundAllowSSH" `
                             -Description "Inbound allow SSH" `
                             -Priority 2000 `
                             -Direction Inbound `
                             -Access Allow `
                             -Protocol TCP `
                             -SourceAddressPrefix * `
                             -SourcePortRange 22 `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange *
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                             -Name "InboundDenyAll" `
                             -Description "Inbound deny all" `
                             -Priority 3000 `
                             -Direction Inbound `
                             -Access Deny `
                             -Protocol * `
                             -SourceAddressPrefix * `
                             -SourcePortRange * `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange *


# Check that VNET and subnet exist
# --------------------------------
Add-LogMessage -Level Info "Looking for virtual network '$($config.sre.network.vnet.name)'..."
try {
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $config.sre.network.vnet.rg -Name $config.sre.network.vnet.name -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
    Add-LogMessage -Level Fatal "Virtual network '$($config.sre.network.vnet.name)' could not be found!"
}
Add-LogMessage -Level Success "Found virtual network '$($vnet.Name)' in $($vnet.ResourceGroupName)"

Add-LogMessage -Level Info "Looking for subnet '$($config.sre.network.vnet.subnets.data.name)'..."
$subnet = $vnet.subnets | Where-Object { $_.Name -eq $config.sre.network.vnet.subnets.data.name }
if ($null -eq $subnet) {
    Add-LogMessage -Level Fatal "Subnet '$($config.sre.network.vnet.subnets.data.name)' could not be found in virtual network '$($vnet.Name)'!"
}
Add-LogMessage -Level Success "Found subnet '$($subnet.Name)' in $($vnet.Name)"


# Retrieve credentials from the keyvault
# --------------------------------------
$vmAdminPassword = Resolve-KeyVaultSecret -VaultName $keyVault -SecretName $config.sre.dsvm.adminPasswordSecretName -DefaultLength 20
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $keyVault -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()


#Construct cloud-init YAML file
# ------------------------------
$cloudInitBasePath = Join-Path $PSScriptRoot ".." "cloud_init" -Resolve
$cloudInitFilePath = Join-Path $cloudInitBasePath "cloud-init-tier1.yaml"
$cloudInitYaml = Get-Content $cloudInitFilePath -Raw

# Create empty disks
$dataDisk = Deploy-ManagedDisk -Name "$vmName-DATA-DISK" -SizeGB $config.sre.dsvm.disks.scratch.sizeGb -Type $config.sre.dsvm.disks.scratch.type -ResourceGroupName $config.sre.dsvm.rg -Location $config.sre.location


# Deploy a VM using adminUserName and adminPublicKeyPath usersYamlPath
$vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.sre.dsvm.rg -Subnet $subnet -PrivateIpAddress $vmIpAddress -Location $config.sre.location
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$params = @{
    Name                   = $vmName
    Size                   = $vmSize
    AdminPassword          = $vmAdminPassword
    AdminUsername          = $vmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $cloudInitYaml
    location               = $config.sre.location
    NicId                  = $vmNic.Id
    OsDiskSizeGb           = $config.sre.dsvm.disks.os.sizeGb
    OsDiskType             = $config.sre.dsvm.disks.os.type
    ResourceGroupName      = $config.sre.dsvm.rg
    DataDiskIds            = @($dataDisk.Id)
}
$null = Deploy-UbuntuVirtualMachine @params


pushd ../ansible


# Create or retrieve SSH keys
# ---------------------------
$keySecretPrefix ="$($vmName)-KEY"
if (-not $(Get-AzKeyVaultSecret -Vaultname $keyVault -Name "$($keySecretPrefix)-PRIVATE") {
    # Create SSH keys
    ssh-keygen -m PEM -t rsa -b 4096 -f "$($vmName).pem"

    # Copy public key to VM
    $sshPublicKey = cat "$($vmName).pem.pub"
    Add-AzVMSshPublicKey `
        -VM $vmconfig `
        -KeyData $sshPublicKey `
        -Path "/home/$($vmAdminUsername)/.ssh/authorized_keys"

    # Upload keys to key vault
    $null = Set-AzKeyVaultSecret -VaultName $keyVault -Name "$($keySecretPrefix)-PUBLIC" -SecretValue $sshPublicKey
    $sshPrivateKey = cat "$($vmName).pem"
    $null = Set-AzKeyVaultSecret -VaultName $keyVault -Name "$($keySecretPrefix)-PRIVATE" -SecretValue $sshPrivateKey
} else {
    # Fetch private key from key vault
    $sshPrivateKey = Get-AzKeyVaultSecret -VaultName $keyVault -Name "$($keySecretPrefix)-PRIVATE"
    $sshPrivateKey | Set-Content -Path "$($vmName).pem"
}


# Configure hosts file
# --------------------
$hostsTemplate = Get-Content -Path "tier1-hosts.yaml"
$hostsTemplate = $hostsTemplate -replace "<tier1_host>" $vmIpAddress
$hostsTemplate = $hostsTemplate -replace "<tier1_admin>" $vmAdminUsername
$hostsTemplate = $hostsTemplate -replace "<tier1_key>" "$($vmName).pem"
$hostsTemplate | Set-Content -Path "hosts.yaml"


# Configures users file
# ---------------------
$users = $config.sre.users
$users | ConvertTo-JSON | Set-Content -Path "users.json"


# Run ansible playbook
# --------------------
ansible-playbook tier1-playbook.yaml -i hosts.yaml


# Generate qr codes
# -----------------
./generate_qr_codes.py


# Remove temporary files
# ----------------------
rm hosts.yaml users.json "$($vmName).pem"
popd


# NB. to update for new users simply re-run this script
# We need to make sure that this allows us to remove users too


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
