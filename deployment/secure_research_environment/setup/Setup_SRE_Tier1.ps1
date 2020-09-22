param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Mandatory = $false, HelpMessage = "Enter VM size to use (or leave empty to use default)")]
    [string]$vmSize = "",
    [Parameter(Mandatory = $false, HelpMessage = "Path to the users file for the Tier1 VM.")]
    [string]$usersYAMLPath = ""
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/DataStructures.psm1 -Force
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Get absolute path to users file
# -------------------------------
if ($usersYAMLPath) { $usersYAMLPath = (Resolve-Path -Path $usersYAMLPath).Path }


# Get VM size and name
# --------------------
if (!$vmSize) { $vmSize = $config.sre.dsvm.vmSizeDefault }
$vmName = "SRE-$($config.sre.id)-$($config.sre.dsvm.vmImage.version)-TIER1-VM".ToUpper()


# Create VNet resource group if it does not exist
# -----------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.network.vnet.rg -Location $config.sre.location
$sreVnet = Deploy-VirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -AddressPrefix $config.sre.network.vnet.cidr -Location $config.sre.location
$subnet = Deploy-Subnet -Name $config.sre.network.vnet.subnets.data.name -VirtualNetwork $sreVnet -AddressPrefix $config.sre.network.vnet.subnets.data.cidr


# Ensure that NSG exists
# ----------------------
$nsg = Deploy-NetworkSecurityGroup -Name $config.sre.dsvm.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                             -Name "OutboundInternetAccess" `
                             -Description "Outbound internet access" `
                             -Priority 2000 `
                             -Direction Outbound `
                             -Access Allow `
                             -Protocol * `
                             -SourceAddressPrefix * `
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
                             -Name "InboundSSHAccess" `
                             -Description "Inbound SSH access" `
                             -Priority 2000 `
                             -Direction Inbound `
                             -Access Allow `
                             -Protocol TCP `
                             -SourceAddressPrefix * `
                             -SourcePortRange * `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange 22
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

# Apply NSG to subnet
# -------------------
$null = Set-SubnetNetworkSecurityGroup -Subnet $subnet -VirtualNetwork $sreVnet -NetworkSecurityGroup $nsg


# Retrieve credentials from the keyvault
# --------------------------------------
$keyVault = $config.sre.keyVault.name
$vmAdminPassword = Resolve-KeyVaultSecret -VaultName $keyVault -SecretName $config.sre.dsvm.adminPasswordSecretName -DefaultLength 20
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $keyVault -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()


# Ensure that the storage resource group exists
# ---------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.dataserver.rg -Location $config.sre.location


# Deploy a storage account for data ingress
# -----------------------------------------
$ingressdataStorage = Deploy-StorageAccount -Name $config.sre.storage.data.ingress.accountName -ResourceGroupName $config.sre.dataserver.rg -Location $config.sre.location
$null = Deploy-StorageShare -Name $config.sre.storage.data.ingress.containerName -StorageAccount $ingressdataStorage
$ingressSharePassword = (Get-AzStorageAccountKey -ResourceGroupName $config.sre.dataserver.rg -Name $config.sre.storage.data.ingress.accountName | Where-Object {$_.KeyName -eq "key1"}).Value


# Deploy a storage account for data egress
# ----------------------------------------
$egressdataStorage = Deploy-StorageAccount -Name $config.sre.storage.data.egress.accountName -ResourceGroupName $config.sre.dataserver.rg -Location $config.sre.location
$null = Deploy-StorageShare -Name $config.sre.storage.data.egress.containerName -StorageAccount $egressdataStorage
$egressSharePassword = (Get-AzStorageAccountKey -ResourceGroupName $config.sre.dataserver.rg -Name $config.sre.storage.data.egress.accountName | Where-Object {$_.KeyName -eq "key1"}).Value


# Ensure that the DSVM resource group exists
# ------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.dsvm.rg -Location $config.sre.location


# Construct cloud-init YAML file
# ------------------------------
$cloudInitYaml = Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-compute-vm-tier1.yaml" | Get-Item | Get-Content -Raw
$cloudInitYaml = $cloudInitYaml.Replace("<ingress-share-username>", $config.sre.storage.data.ingress.accountName).
                                Replace("<ingress-share-password>", $ingressSharePassword).
                                Replace("<ingress-container-name>", $config.sre.storage.data.ingress.containerName).
                                Replace("<egress-share-username>", $config.sre.storage.data.egress.accountName).
                                Replace("<egress-share-password>", $egressSharePassword).
                                Replace("<egress-container-name>", $config.sre.storage.data.egress.containerName)


# Deploy data disk, NIC and public IP
# -----------------------------------
$dataDisk = Deploy-ManagedDisk -Name "${vmName}-DATA-DISK" -SizeGB $config.sre.dsvm.disks.scratch.sizeGb -Type $config.sre.dsvm.disks.scratch.type -ResourceGroupName $config.sre.dsvm.rg -Location $config.sre.location
$vmNic = Deploy-VirtualMachineNIC -Name "${vmName}-NIC" -ResourceGroupName $config.sre.dsvm.rg -Subnet $subnet -Location $config.sre.location -PublicIpAddressAllocation Static
$vmPublicIpAddress = (Get-AzPublicIpAddress -Name "${vmName}-NIC-PIP" -ResourceGroupName $config.sre.dsvm.rg).IpAddress


# Ensure that SSH keys exist in the key vault
# -------------------------------------------
$publicKeySecretName = "sre-tier1-key-public"
$privateKeySecretName = "sre-tier1-key-private"
if (-not ((Get-AzKeyVaultSecret -VaultName $keyVault -Name $publicKeySecretName) -and (Get-AzKeyVaultSecret -VaultName $keyVault -Name $privateKeySecretName))) {
    # Remove existing keys if they do not both exist
    if (Get-AzKeyVaultSecret -VaultName $keyVault -Name $publicKeySecretName) {
        Add-LogMessage -Level Info "[ ] Removing outdated public key '$publicKeySecretName'"
        Remove-AzKeyVaultSecret -VaultName $keyVault -Name $publicKeySecretName -Force
        if ($?) {
            Add-LogMessage -Level Success "Removed outdated public key '$publicKeySecretName'"
        } else {
            Add-LogMessage -Level Fatal "Failed to remove outdated public key '$publicKeySecretName'!"
        }
    }
    if (Get-AzKeyVaultSecret -VaultName $keyVault -Name $privateKeySecretName) {
        Add-LogMessage -Level Info "[ ] Removing outdated private key '$privateKeySecretName'"
        Remove-AzKeyVaultSecret -VaultName $keyVault -Name $privateKeySecretName -Force
        if ($?) {
            Add-LogMessage -Level Success "Removed outdated private key '$privateKeySecretName'"
        } else {
            Add-LogMessage -Level Fatal "Failed to remove outdated private key '$privateKeySecretName'!"
        }
    }

    # Create new SSH keys
    try {
        Add-LogMessage -Level Info "[ ] Generating SSH key pair for use by Ansible..."
        ssh-keygen -m PEM -t rsa -b 4096 -f "${vmName}.pem" -q -N '""'  # NB. we need the nested quotes here to stop Powershell expanding the empty string to nothing
        if ($?) {
            Add-LogMessage -Level Success "Created new Ansible SSH key pair"
        } else {
            Add-LogMessage -Level Fatal "Failed to create new Ansible SSH key pair!"
        }
        # Upload keys to key vault
        $null = Resolve-KeyVaultSecret -SecretName $publicKeySecretName -VaultName $keyVault -DefaultValue $(Get-Content "$($vmName).pem.pub" -Raw)
        $success = $?
        $null = Resolve-KeyVaultSecret -SecretName $privateKeySecretName -VaultName $keyVault -DefaultValue $(Get-Content "$($vmName).pem" -Raw)
        $success = $success -and $?
        if ($success) {
            Add-LogMessage -Level Success "Uploaded Ansible SSH keys to '$keyVault'"
        } else {
            Add-LogMessage -Level Fatal "Failed to upload Ansible SSH keys to '$keyVault'!"
        }
    } finally {
        # Delete the SSH key files
        Remove-Item "${vmName}.pem*" -Force -ErrorAction SilentlyContinue
    }
}
# Fetch SSH keys from key vault
Add-LogMessage -Level Info "Retrieving SSH keys from key vault"
$sshPublicKey = Resolve-KeyVaultSecret -SecretName $publicKeySecretName -VaultName $keyVault
$sshPrivateKey = Resolve-KeyVaultSecret -SecretName $privateKeySecretName -VaultName $keyVault


# Get list of image definitions
# -----------------------------
$imageDefinition = Get-ImageDefinition -Type $config.sre.dsvm.vmImage.type
$image = Get-ImageFromGallery -ImageVersion $config.sre.dsvm.vmImage.version -ImageDefinition $imageDefinition -GalleryName $config.sre.dsvm.vmImage.gallery -ResourceGroup $config.sre.dsvm.vmImage.rg -Subscription $config.sre.dsvm.vmImage.subscription


# Set the OS disk size for this image
# -----------------------------------
$osDiskSizeGB = $config.sre.dsvm.disks.os.sizeGb
if ($osDiskSizeGB -eq "default") { $osDiskSizeGB = 2 * [int]$image.StorageProfile.OsDiskImage.SizeInGB }
if ([int]$osDiskSizeGB -lt [int]$image.StorageProfile.OsDiskImage.SizeInGB) {
    Add-LogMessage -Level Fatal "Image $imageVersion needs an OS disk of at least $($image.StorageProfile.OsDiskImage.SizeInGB) GB!"
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
    OsDiskSizeGb           = $osDiskSizeGB
    OsDiskType             = $config.sre.dsvm.disks.os.type
    ResourceGroupName      = $config.sre.dsvm.rg
    DataDiskIds            = @($dataDisk.Id)
    ImageId                = $image.Id
    NoWait                 = $true
}
$null = Deploy-UbuntuVirtualMachine @params
Start-Sleep -Seconds 60


try {
    # Write private key
    # -----------------
    $sshPrivateKey | Set-Content -Path "${privateKeySecretName}.key"
    chmod 600 "${privateKeySecretName}.key"


    # Configures users file
    # ---------------------
    if ($usersYAMLPath) {
        Copy-Item -Path $usersYAMLPath -Destination "users.yaml"
    } else {
        "---
        users: []" | Set-Content -Path "users.yaml"
    }


    # Run ansible playbook and create totp_hashes.txt
    # -----------------------------------------------
    ansible-playbook (Join-Path $PSScriptRoot ".." "ansible" "tier1-playbook.yaml" | Resolve-Path).Path `
        -i "$($vmPublicIpAddress)," `
        -u $vmAdminUsername `
        --private-key "${privateKeySecretName}.key" `
        -e "fqdn=$($config.sre.domain.fqdn)"

    # Generate qr codes
    # -----------------
    if ($usersYAMLPath) {
        Add-LogMessage -Level Info "Generating QR codes"
        python3 $(Join-Path $PSScriptRoot ".." "ansible" "scripts" "generate_qr_codes.py") `
                --totp-hashes (Join-Path $PSScriptRoot "totp_hashes.txt") `
                --qr-codes (Join-Path $HOME "qrcodes" $config.sre.id) `
                --host-name $config.sre.domain.fqdn
        Add-LogMessage -Level Warning "You will need to send each of the $HOME/qrcodes/<sreid>/<name>.png QR codes to the appropriate user in order for them to initialise their MFA"
    }


} finally {
    # Remove temporary files
    @("users.yaml", "${privateKeySecretName}.key", "totp_hashes.txt") | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
}


# Add DNS records for tier-1 VM
# -----------------------------
Add-LogMessage -Level Info "Adding DNS record for SSH connection"
$null = Deploy-DNSRecords -SubscriptionName $config.shm.dns.subscriptionName -ResourceGroupName $config.shm.dns.rg -ZoneName $config.sre.domain.fqdn -PublicIpAddress $vmPublicIpAddress


# Give connection information
# ---------------------------
Add-LogMessage -Level Info -Message `
@"
To connect to this VM please do the following:
  ssh <username>@$($config.sre.domain.fqdn) -L<local-port>:localhost:<remote-port>
For example, to use CoCalc on port 443 you could do the following
  ssh <username>@$($config.sre.domain.fqdn) -L8443:localhost:443
You can then open a browser locally and go to https://localhost:8443
"@


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
