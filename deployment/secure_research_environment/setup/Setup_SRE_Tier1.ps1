param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Mandatory = $false, HelpMessage = "Enter VM size to use (or leave empty to use default)")]
    [string]$vmSize = "",
    [Parameter(Mandatory = $false, HelpMessage = "Path to the users file for the Tier1 VM.")]
    [string]$usersYAMLPath = ""
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


# Get absolute path of users file
# -------------------------------
if ($usersYAMLPath) { $usersYAMLPath = (Resolve-Path -Path $usersYAMLPath).Path }


# Get VM size
# -----------
if (!$vmSize) { $vmSize = $config.sre.dsvm.vmSizeDefault }


# Generate VM name
# ----------------
$vmName = "SRE-$($config.sre.id)-TIER1-VM".ToUpper()


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
                             -Name "InboundAllowSSH" `
                             -Description "Inbound allow SSH" `
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


# Construct cloud-init YAML file
# ------------------------------
$cloudInitYaml = Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-compute-vm-tier1.yaml" | Get-Item | Get-Content -Raw


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
$publicKeySecretName ="${vmName}-KEY-PUBLIC"
$privateKeySecretName ="${vmName}-KEY-PRIVATE"
if (-not ((Get-AzKeyVaultSecret -VaultName $keyVault -Name "$publicKeySecretName") -and (Get-AzKeyVaultSecret -VaultName $keyVault -Name $privateKeySecretName))) {
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


# Deploy a storage account for
$dataStorage = Deploy-StorageAccount -Name "testtier1storage" -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location


# Get list of image definitions
# -----------------------------
Add-LogMessage -Level Info "Getting image type from gallery..."
if ($config.sre.dsvm.vmImage.type -eq "Ubuntu") {
    $imageDefinition = "ComputeVM-Ubuntu1804Base"
} elseif ($config.sre.dsvm.vmImage.type -eq "UbuntuTorch") {
    $imageDefinition = "ComputeVM-UbuntuTorch1804Base"
} elseif ($config.sre.dsvm.vmImage.type -eq "DataScience") {
    $imageDefinition = "ComputeVM-DataScienceBase"
} elseif ($config.sre.dsvm.vmImage.type -eq "DSG") {
    $imageDefinition = "ComputeVM-DsgBase"
} else {
    Add-LogMessage -Level Fatal "Could not interpret $($config.sre.dsvm.vmImage.type) as an image type!"
}
Add-LogMessage -Level Success "Using image type $imageDefinition"


# Check that this is a valid image version and get its ID
# -------------------------------------------------------
$null = Set-AzContext -Subscription $config.sre.dsvm.vmImage.subscription
$imageVersion = $config.sre.dsvm.vmImage.version
Add-LogMessage -Level Info "Looking for image $imageDefinition version $imageVersion..."
try {
    $image = Get-AzGalleryImageVersion -ResourceGroup $config.sre.dsvm.vmImage.rg -GalleryName $config.sre.dsvm.vmImage.gallery -GalleryImageDefinitionName $imageDefinition -GalleryImageVersionName $imageVersion -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
    $versions = Get-AzGalleryImageVersion -ResourceGroup $config.sre.dsvm.vmImage.rg -GalleryName $config.sre.dsvm.vmImage.gallery -GalleryImageDefinitionName $imageDefinition | Sort-Object Name | ForEach-Object { $_.Name } #Select-Object -Last 1
    Add-LogMessage -Level Error "Image version '$imageVersion' is invalid. Available versions are: $versions"
    $imageVersion = $versions | Select-Object -Last 1
    $userVersion = Read-Host -Prompt "Enter the version you would like to use (or leave empty to accept the default: '$imageVersion')"
    if ($versions.Contains($userVersion)) {
        $imageVersion = $userVersion
    }
    $image = Get-AzGalleryImageVersion -ResourceGroup $config.sre.dsvm.vmImage.rg -GalleryName $config.sre.dsvm.vmImage.gallery -GalleryImageDefinitionName $imageDefinition -GalleryImageVersionName $imageVersion -ErrorAction Stop
}
Add-LogMessage -Level Success "Found image $imageDefinition version $($image.Name) in gallery"
$null = Set-AzContext -Subscription $config.sre.subscriptionName


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
