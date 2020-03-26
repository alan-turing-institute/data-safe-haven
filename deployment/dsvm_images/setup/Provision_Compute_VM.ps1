param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $false, HelpMessage = "Source image (one of 'Ubuntu1804' [default], 'Ubuntu1810', 'Ubuntu1904', 'Ubuntu1910'")]
    [ValidateSet("Ubuntu1804", "Ubuntu1810", "Ubuntu1904", "Ubuntu1910")]
    [string]$sourceImage = "Ubuntu1804"
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig($shmId)
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsvmImage.subscription


# Select which source URN to base the build on
# --------------------------------------------
if ($sourceImage -eq "Ubuntu1804") {
    $baseImageSku = "18.04-LTS"
    $buildVmName = "DSVM-Ubuntu1804Base"
} elseif ($sourceImage -eq "Ubuntu1810") {
    Add-LogMessage -Level Fatal "Ubuntu 18.10 is no longer available on Azure!"
} elseif ($sourceImage -eq "Ubuntu1904") {
    $baseImageSku = "19.04"
    $buildVmName = "DSVM-Ubuntu1904Base"
} elseif ($sourceImage -eq "Ubuntu1910") {
    $baseImageSku = "19_10-daily-gen2"
    $buildVmName = "DSVM-Ubuntu1910Base"
} else {
    Add-LogMessage -Level Fatal "Did not recognise source image '$sourceImage'!"
}
$cloudInitTemplate = Get-Content (Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-buildimage-ubuntu.yaml") -Raw


# Create resource groups if they do not exist
# -------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.dsvmImage.build.rg -Location $config.dsvmImage.location
$_ = Deploy-ResourceGroup -Name $config.dsvmImage.bootdiagnostics.rg -Location $config.dsvmImage.location
$_ = Deploy-ResourceGroup -Name $config.dsvmImage.network.rg -Location $config.dsvmImage.location
$_ = Deploy-ResourceGroup -Name $config.dsvmImage.keyVault.rg -Location $config.dsvmImage.location


# Ensure the keyvault exists and set its access policies
# ------------------------------------------------------
$_ = Deploy-KeyVault -Name $config.dsvmImage.keyVault.name -ResourceGroupName $config.dsvmImage.keyVault.rg -Location $config.dsvmImage.location
Set-KeyVaultPermissions -Name $config.dsvmImage.keyVault.name -GroupName $config.adminSecurityGroupName


# Check that VNET and subnet exist
# --------------------------------
Add-LogMessage -Level Info "Looking for virtual network '$($config.dsvmImage.network.vnet.name)'..."
try {
    $vnet = Get-AzVirtualNetwork -Name $config.dsvmImage.build.vnet.name -ResourceGroupName $config.dsvmImage.network.rg -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException]{
    Add-LogMessage -Level Fatal "Virtual network '$($config.dsvmImage.build.vnet.name)' could not be found!"
}
Add-LogMessage -Level Success "Found virtual network '$($vnet.Name)' in $($vnet.ResourceGroupName)"
# Subnet
Add-LogMessage -Level Info "Looking for subnet network '$($config.dsvmImage.build.subnet.name)'..."
$subnet = $vnet.subnets | Where-Object { $_.Name -eq $config.dsvmImage.build.subnet.name }
if ($null -eq $subnet) {
    Add-LogMessage -Level Fatal "Subnet '$($config.dsvmImage.build.subnet.name)' could not be found in virtual network '$($vnet.Name)'!"
}
Add-LogMessage -Level Success "Found subnet '$($subnet.Name)' in $($vnet.Name)"


# Set up the build NSG
# --------------------
Add-LogMessage -Level Info "Ensure that build NSG '$($config.dsvmImage.build.nsg.name)' exists..."
$buildNsg = Deploy-NetworkSecurityGroup -Name $config.dsvmImage.build.nsg.name -ResourceGroupName $config.dsvmImage.network.rg -Location $config.dsvmImage.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $buildNsg `
                             -Access Allow `
                             -Name "AllowTuringSSH" `
                             -Description "Allow port 22 for management over ssh" `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange 22 `
                             -Direction Inbound `
                             -Priority 1000 `
                             -Protocol TCP `
                             -SourceAddressPrefix 193.60.220.240,193.60.220.253 `
                             -SourcePortRange *
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $buildNsg `
                             -Access Deny `
                             -Name "DenyAll" `
                             -Description "Inbound deny all" `
                             -DestinationAddressPrefix * `
                             -DestinationPortRange * `
                             -Direction Inbound `
                             -Priority 3000 `
                             -Protocol * `
                             -SourceAddressPrefix * `
                             -SourcePortRange *

# Insert python package details into the cloud-init template
$python27AllPackages = Get-Content (Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists" "python27-packages.list")
$python27PipPackages = Get-Content (Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists" "python27-not-installable-with-conda.list")
$python27CondaPackages = $python27AllPackages | Where-Object { $python27PipPackages -notcontains $_ }
$python36AllPackages = Get-Content (Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists" "python36-packages.list")
$python36PipPackages = Get-Content (Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists" "python36-not-installable-with-conda.list")
$python36CondaPackages = $python36AllPackages | Where-Object { $python36PipPackages -notcontains $_ }
$python37AllPackages = Get-Content (Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists" "python37-packages.list")
$python37PipPackages = Get-Content (Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists" "python37-not-installable-with-conda.list")
$python37CondaPackages = $python37AllPackages | Where-Object { $python37PipPackages -notcontains $_ }
$pythonPackages = "- export PYTHON27_CONDA_PACKAGES=`"${python27CondaPackages}`"" + "`n  " + `
                  "- export PYTHON27_PIP_PACKAGES=`"${python27PipPackages}`"" + "`n  " + `
                  "- export PYTHON36_CONDA_PACKAGES=`"${python36CondaPackages}`"" + "`n  " + `
                  "- export PYTHON36_PIP_PACKAGES=`"${python36PipPackages}`"" + "`n  " + `
                  "- export PYTHON37_CONDA_PACKAGES=`"${python37CondaPackages}`"" + "`n  " + `
                  "- export PYTHON37_PIP_PACKAGES=`"${python37PipPackages}`""
$cloudInitTemplate = $cloudInitTemplate.Replace("# === AUTOGENERATED ANACONDA PACKAGES START HERE ===", $pythonPackages)

# Insert R package details into the cloud-init template
$cranPackages = Get-Content (Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists" "cran.list")
$bioconductorPackages = Get-Content (Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists" "bioconductor.list")
$rPackages = "- export CRAN_PACKAGES=`"$($cranPackages | Join-String -SingleQuote -Separator ', ')`"" + "`n  " + `
             "- export BIOCONDUCTOR_PACKAGES=`"$($bioconductorPackages | Join-String -SingleQuote -Separator ', ')`""
$cloudInitTemplate = $cloudInitTemplate.Replace("# === AUTOGENERATED R PACKAGES START HERE ===", $rPackages)


# Construct build VM parameters
# -----------------------------
$buildVmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.dsvmImage.keyVault.name -SecretName $config.keyVault.secretNames.buildImageAdminUsername -defaultValue "dsvmbuildadmin"
$buildVmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.dsvmImage.keyVault.name -SecretName $config.keyVault.secretNames.buildImageAdminPassword
$buildVmBootDiagnosticsAccount = Deploy-StorageAccount -Name $config.dsvmImage.bootdiagnostics.accountName -ResourceGroupName $config.dsvmImage.bootdiagnostics.rg -Location $config.dsvmImage.location
$buildVmName = "Candidate${buildVmName}-$(Get-Date -Format "yyyMMddHHmm")"
$buildVmNic = Deploy-VirtualMachineNIC -Name "$buildVmName-NIC" -ResourceGroupName $config.dsvmImage.build.rg -Subnet $subnet -PublicIpAddressAllocation "Static" -Location $config.dsvmImage.location
$buildVmSize = "Standard_E16s_v3"


# Deploy the VM
# -------------
Add-LogMessage -Level Info "Provisioning a new VM image in $($config.dsvmImage.build.rg) [$($config.dsvmImage.subscription)]..."
Add-LogMessage -Level Info "  VM name: $buildVmName"
Add-LogMessage -Level Info "  Base image: Ubuntu $baseImageSku"
$params = @{
    Name = $buildVmName
    Size = $buildVmSize
    AdminPassword = $buildVmAdminPassword
    AdminUsername = $buildVmAdminUsername
    BootDiagnosticsAccount = $buildVmBootDiagnosticsAccount
    CloudInitYaml = $cloudInitTemplate
    location = $config.dsvmImage.location
    NicId = $buildVmNic.Id
    OsDiskSizeGb = 80
    OsDiskType = "Standard_LRS"
    ResourceGroupName = $config.dsvmImage.build.rg
    ImageSku = $baseImageSku
}
$_ = Deploy-UbuntuVirtualMachine @params


# Log connection details for monitoring this build
# ------------------------------------------------
$publicIp = (Get-AzPublicIpAddress -ResourceGroupName $config.dsvmImage.build.rg | Where-Object { $_.Id -Like "*${buildVmName}-NIC-PIP" }).IpAddress
Add-LogMessage -Level Info "This process will take several hours to complete."
Add-LogMessage -Level Info "  You can monitor installation progress using: ssh $buildVmAdminUsername@$publicIp"
Add-LogMessage -Level Info "  The password for this account is in the '$($config.keyVault.secretNames.buildImageAdminPassword)' secret in the '$($config.dsvmImage.keyVault.Name)' key vault"
Add-LogMessage -Level Info "  Once logged in, check the installation progress with: tail -f -n+1 /var/log/cloud-init-output.log"


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
