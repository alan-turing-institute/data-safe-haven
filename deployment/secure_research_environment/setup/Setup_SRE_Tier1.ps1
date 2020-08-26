param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Mandatory = $false, HelpMessage = "Enter VM size to use (or leave empty to use default)")]
    [string]$vmSize = "",
    [Parameter(Mandatory = $false, HelpMessage = "Path to the users file for the Tier1 VM.")]
    [string]$userslYAMLPath
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


# Generate VM name
# ----------------
$vmName = "SRE-$($config.sre.id)-TIER1-VM".ToUpper()


# Get VM size
# -----------
if (!$vmSize) { $vmSize = $config.sre.dsvm.vmSizeDefault }

# Create VNet resource group if it does not exist
# -----------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.network.vnet.rg -Location $config.sre.location
$sreVnet = Deploy-VirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -AddressPrefix $config.sre.network.vnet.cidr -Location $config.sre.location -DnsServer $config.shm.dc.ip, $config.shm.dcb.ip
$subnet = Deploy-Subnet -Name $config.sre.network.vnet.subnets.data.name -VirtualNetwork $sreVnet -AddressPrefix $config.sre.network.vnet.subnets.data.cidr


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


# Retrieve credentials from the keyvault
# --------------------------------------
$keyVault = $config.sre.keyVault.name
$vmAdminPassword = Resolve-KeyVaultSecret -VaultName $keyVault -SecretName $config.sre.dsvm.adminPasswordSecretName -DefaultLength 20
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $keyVault -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()


# Construct cloud-init YAML file
# ------------------------------
$cloudInitBasePath = Join-Path $PSScriptRoot ".." "cloud_init" -Resolve
$cloudInitFilePath = Join-Path $cloudInitBasePath "cloud-init-tier1.yaml"
$cloudInitYaml = Get-Content $cloudInitFilePath -Raw

# Create empty disk
# -----------------
$null = Deploy-ResourceGroup -Name $config.sre.dsvm.rg -Location $config.sre.location
$dataDisk = Deploy-ManagedDisk -Name "$vmName-DATA-DISK" -SizeGB $config.sre.dsvm.disks.scratch.sizeGb -Type $config.sre.dsvm.disks.scratch.type -ResourceGroupName $config.sre.dsvm.rg -Location $config.sre.location

# Deploy NIC and get public IP
# ----------------------------
$vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.sre.dsvm.rg -Subnet $subnet -Location $config.sre.location -PublicIpAddressAllocation Static
$vmPublicIpAddress = (Get-AzPublicIpAddress -Name "$vmName-NIC-PIP" -ResourceGroupName $config.sre.dsvm.rg).IpAddress
Add-LogMessage -Level Info -Message "VM public IP address: $($vmPublicIpAddress)"


# Create or retrieve SSH keys
# ---------------------------
$keySecretPrefix ="$($vmName)-KEY"
if (-not $(Get-AzKeyVaultSecret -Vaultname $keyVault -Name "$($keySecretPrefix)-PRIVATE")) {
    # Create SSH keys
    ssh-keygen -m PEM -t rsa -b 4096 -f "$($vmName).pem"

    # Upload keys to key vault
    $sshPublicKey = Get-Content "$($vmName).pem.pub" -Raw
    $null = Set-AzKeyVaultSecret -VaultName $keyVault -Name "$($keySecretPrefix)-PUBLIC" -SecretValue (ConvertTo-SecureString $sshPublicKey -AsPlainText -Force)
    $sshPrivateKey = Get-Content "$($vmName).pem" -Raw
    $null = Set-AzKeyVaultSecret -VaultName $keyVault -Name "$($keySecretPrefix)-PRIVATE" -SecretValue (ConvertTo-SecureString $sshPrivateKey -AsPlainText -Force)
} else {
    # Fetch private key from key vault
    $sshPublicKey = (Get-AzKeyVaultSecret -VaultName $keyVault -Name "$($keySecretPrefix)-PUBLIC").SecretValueText
    $sshPrivateKey = (Get-AzKeyVaultSecret -VaultName $keyVault -Name "$($keySecretPrefix)-PRIVATE").SecretValueText
    $sshPrivateKey | Set-Content -Path "$($vmName).pem"
    chmod 600 "$($vmName).pem"
}


# Deploy VM
# ---------
$null = Deploy-ResourceGroup -Name $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$params = @{
    Name                   = $vmName
    Size                   = $vmSize
    AdminPassword          = $vmAdminPassword
    AdminUsername          = $vmAdminUsername
    AdminPublicSshKey      = $sshPublicKey
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $cloudInitYaml
    location               = $config.sre.location
    NicId                  = $vmNic.Id
    OsDiskSizeGb           = $config.sre.dsvm.disks.os.sizeGb
    OsDiskType             = $config.sre.dsvm.disks.os.type
    ResourceGroupName      = $config.sre.dsvm.rg
    DataDiskIds            = @($dataDisk.Id)
    ImageSku               = "18.04-LTS"
    SkipWaitForCloudInit   = $true
}
$vm = Deploy-UbuntuVirtualMachine @params


try{
    pushd ../ansible


    # Configure hosts file
    # --------------------
    $hostsTemplate = Get-Content -Path "tier1-hosts.yaml"
    $hostsTemplate = $hostsTemplate.Replace("<tier1_host>", $vmPublicIpAddress)
    $hostsTemplate = $hostsTemplate.Replace("<tier1_admin>", $vmAdminUsername)
    $hostsTemplate = $hostsTemplate.Replace("<tier1_key>", "$($vmName).pem")
    $hostsTemplate | Set-Content -Path "hosts.yaml"


    # Configures users file
    # ---------------------
    if ($usersYAMLPath) {
        cp $usersYAMLPath "users.yaml"
    } else {
        "---
        users: []" | Set-Content -path "users.yaml"
    }


    # Run ansible playbook
    # --------------------
    ansible-playbook tier1-playbook.yaml -i hosts.yaml


    # Generate qr codes
    # -----------------
    ./generate_qr_codes.py


} finally {
    # Remove temporary files
    # ----------------------
    # rm -f hosts.yaml users.yaml "$($vmName).pem" "$($vmName).pem.pub"

    popd
}


# NB. to update for new users simply re-run this script
# We need to make sure that this allows us to remove users too


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
