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


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Get absolute path of users file
# -------------------------------
if ($usersYAMLPath) { $usersYAMLPath = (Resolve-Path -Path $usersYAMLPath).Path }


# Get VM size
# -----------
if (!$vmSize) { $vmSize = $config.sre.dsvm.vmSizeDefault }


# Generate VM name
# ----------------
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


# Deploy a storage account for data ingress
# -----------------------------------------
$sreStorageSuffix = New-RandomLetters -SeedPhrase "$($config.sre.subscriptionName)$($config.sre.id)"
$ingressStorgageName = "sre$($config.sre.id)ingress${sreStorageSuffix}".ToLower() | Limit-StringLength 24 -Silent
$null = Deploy-ResourceGroup -Name $config.sre.dataserver.rg -Location $config.sre.location
$dataStorage = Deploy-StorageAccount -Name $ingressStorgageName -ResourceGroupName $config.sre.dataserver.rg -Location $config.sre.location
$share = Deploy-StorageShare -Name "ingress" -StorageAccount $dataStorage
$sharePassword = (Get-AzStorageAccountKey -ResourceGroupName $config.sre.dataserver.rg -Name $ingressStorgageName | Where-Object {$_.KeyName -eq "key1"}).Value


# Construct cloud-init YAML file
# ------------------------------
$cloudInitYaml = Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-compute-vm-tier1.yaml" | Get-Item | Get-Content -Raw
$cloudInitYaml = $cloudInitYaml.Replace("<datamount-username>", $ingressStorgageName)
$cloudInitYaml = $cloudInitYaml.Replace("<datamount-password>", $sharePassword)


# Create empty disk
# -----------------
$null = Deploy-ResourceGroup -Name $config.sre.dsvm.rg -Location $config.sre.location
$dataDisk = Deploy-ManagedDisk -Name "$vmName-DATA-DISK" -SizeGB $config.sre.dsvm.disks.scratch.sizeGb -Type $config.sre.dsvm.disks.scratch.type -ResourceGroupName $config.sre.dsvm.rg -Location $config.sre.location


# Deploy NIC and get public IP
# ----------------------------
$vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.sre.dsvm.rg -Subnet $subnet -Location $config.sre.location -PublicIpAddressAllocation Static
$vmPublicIpAddress = (Get-AzPublicIpAddress -Name "$vmName-NIC-PIP" -ResourceGroupName $config.sre.dsvm.rg).IpAddress


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
            Add-LogMessage -Level Success "Created new SSH key pair"
        } else {
            Add-LogMessage -Level Fatal "Failed to create new SSH key pair!"
        }
        # Upload keys to key vault
        $sshPublicKey = Get-Content "$($vmName).pem.pub" -Raw
        $null = Resolve-KeyVaultSecret -SecretName $publicKeySecretName -VaultName $keyVault -DefaultValue $sshPublicKey
        $sshPrivateKey = Get-Content "$($vmName).pem" -Raw
        $null = Resolve-KeyVaultSecret -SecretName $privateKeySecretName -VaultName $keyVault -DefaultValue $sshPrivateKey
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
    ansible-playbook ../ansible/tier1-playbook.yaml `
        -i "$($vmPublicIpAddress)," `
        -u $vmAdminUsername `
        --private-key "${privateKeySecretName}.key"


    # Generate qr codes
    # -----------------
    if ($usersYAMLPath) {
        Add-LogMessage -Level Info "Generating QR codes"
        ./generate_qr_codes.py
    }


} finally {
    # Remove temporary files
    # ----------------------
    @("users.yaml", "${privateKeySecretName}.key", "totp_hashes.txt") | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
}


# Give connection information
# ---------------------------
Add-LogMessage -Level Info -Message `
@"
To connect to this VM please do the following:
  ssh <username>@${vmPublicIpAddress} -L<local-port>:localhost:<remote-port>
For example, to use CoCalc on port 443 you could do the following
  ssh <username>@${vmPublicIpAddress} -L8443:localhost:443
You can then open a browser locally and go to https://localhost:8443
"@


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
