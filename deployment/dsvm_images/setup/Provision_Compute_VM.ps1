param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $false, HelpMessage = "Source image (one of 'Ubuntu1804' [default], 'Ubuntu1810', 'Ubuntu1904', 'Ubuntu1910'")]
    [ValidateSet("Ubuntu1804", "Ubuntu2004")]
    [string]$sourceImage = "Ubuntu1804",
    [Parameter(Mandatory = $false, HelpMessage = "VM size to use (e.g. 'Standard_E4_v3'. Using 'default' will use the value from the configuration file)")]
    [ValidateSet("default", "Standard_D4_v3", "Standard_E2_v3", "Standard_E4_v3", "Standard_E8_v3", "Standard_F4s_v2", "Standard_F8s_v2", "Standard_H8")]
    [string]$vmSize = "default"
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
$null = Set-AzContext -SubscriptionId $config.dsvmImage.subscription


# Select which VM size to use
# ---------------------------
if ($vmSize -eq "default") { $vmSize = $config.dsvmImage.build.vmSize }
# Standard_E2_v3  => 2 cores; 16GB RAM; £0.1163/hr; 2.3 GHz :: build 15h33m56s => £1.81
# Standard_F4s_v2 => 4 cores;  8GB RAM; £0.1506/hr; 3.7 GHz :: build 12h22m17s => £1.86
# Standard_D4_v3  => 4 cores; 16GB RAM; £0.1730/hr; 2.4 GHz :: build 16h41m13s => £2.88
# Standard_E4_v3  => 4 cores; 32GB RAM; £0.2326/hr; 2.3 GHz :: build 16h40m9s  => £3.88
# Standard_H8     => 8 cores; 56GB RAM; £0.4271/hr; 3.6 GHz :: build 12h56m6s  => £5.52
# Standard_E8_v3  => 8 cores; 64GB RAM; £0.4651/hr; 2.3 GHz :: build 17h8m17s  => £7.97


# Select which source URN to base the build on
# --------------------------------------------
if ($sourceImage -eq "Ubuntu1804") {
    $baseImageSku = "18.04-LTS"
    $buildVmName = "ComputeVM-Ubuntu1804Base"
} elseif ($sourceImage -eq "Ubuntu2004") {
    # $baseImageSku = "20.04-LTS"
    # $buildVmName = "ComputeVM-Ubuntu2004Base"
    Add-LogMessage -Level Fatal "Source image '$sourceImage' is not yet available but it will be shortly!"
} else {
    Add-LogMessage -Level Fatal "Did not recognise source image '$sourceImage'!"
}
$cloudInitTemplate = Get-Content (Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-buildimage-ubuntu.yaml") -Raw


# Create resource groups if they do not exist
# -------------------------------------------
$null = Deploy-ResourceGroup -Name $config.dsvmImage.build.rg -Location $config.dsvmImage.location
$null = Deploy-ResourceGroup -Name $config.dsvmImage.bootdiagnostics.rg -Location $config.dsvmImage.location
$null = Deploy-ResourceGroup -Name $config.dsvmImage.network.rg -Location $config.dsvmImage.location
$null = Deploy-ResourceGroup -Name $config.dsvmImage.keyVault.rg -Location $config.dsvmImage.location


# Ensure the keyvault exists and set its access policies
# ------------------------------------------------------
$null = Deploy-KeyVault -Name $config.dsvmImage.keyVault.name -ResourceGroupName $config.dsvmImage.keyVault.rg -Location $config.dsvmImage.location
Set-KeyVaultPermissions -Name $config.dsvmImage.keyVault.name -GroupName $config.azureAdminGroupName


# Ensure that VNET and subnet exist
# ---------------------------------
$vnet = Deploy-VirtualNetwork -Name $config.dsvmImage.build.vnet.name -ResourceGroupName $config.dsvmImage.network.rg -AddressPrefix $config.dsvmImage.build.vnet.cidr -Location $config.dsvmImage.location
$subnet = Deploy-Subnet -Name $config.dsvmImage.build.subnet.name -VirtualNetwork $vnet -AddressPrefix $config.dsvmImage.build.subnet.cidr


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
                             -SourceAddressPrefix 193.60.220.240, 193.60.220.253 `
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
$null = Set-SubnetNetworkSecurityGroup -VirtualNetwork $vnet -Subnet $subnet -NetworkSecurityGroup $buildNsg


# Insert scripts into the cloud-init template
# -------------------------------------------
$indent = "      "
foreach ($scriptName in @("analyse_build.py",
                          "dbeaver_drivers_config.xml",
                          "deprovision_vm.sh",
                          "download_and_install_deb.sh",
                          "download_and_install_tar.sh",
                          "install_python_version.sh")) {
    $raw_script = Get-Content (Join-Path $PSScriptRoot ".." "cloud_init" "scripts" $scriptName) -Raw
    $indented_script = $raw_script -split "`n" | ForEach-Object { "${indent}$_" } | Join-String -Separator "`n"
    $cloudInitTemplate = $cloudInitTemplate.Replace("${indent}<$scriptName>", $indented_script)
}


# Insert apt packages into the cloud-init template
# ------------------------------------------------
$indent = "  - "
$raw_script = Get-Content (Join-Path $PSScriptRoot ".." "packages" "packages-apt.list") -Raw
$indented_script = $raw_script -split "`n" | Where-Object { $_ } | ForEach-Object { "${indent}$_" } | Join-String -Separator "`n"
$cloudInitTemplate = $cloudInitTemplate.Replace("${indent}<apt packages>", $indented_script)


# Insert Julia package details into the cloud-init template
# ---------------------------------------------------------
$juliaPackages = Get-Content (Join-Path $PSScriptRoot ".." "packages" "packages-julia.list")
$juliaPackageText = "- JULIA_PACKAGES='[$($juliaPackages | Join-String -DoubleQuote -Separator ', ')]'"
$cloudInitTemplate = $cloudInitTemplate.Replace("- <Julia package list>", $juliaPackageText)


# Insert PyPI package lists (plus versions) into cloud-init template
# ------------------------------------------------------------------
$packageVersions = Get-Content (Join-Path $PSScriptRoot ".." "packages" "python-requirements.json") | ConvertFrom-Json -AsHashtable
foreach ($pythonVersion in @("27", "36", "37")) {
    $packageListFileName = "packages-python-pypi-${pythonVersion}.list"
    $pythonPackageNames = Get-Content (Join-Path $PSScriptRoot ".." "packages" $packageListFileName)
    $pythonPackageVersions = $pythonPackageNames | ForEach-Object { if ($packageVersions["py${pythonVersion}"].Keys.Contains($_)) { "$_$($packageVersions["py${pythonVersion}"][$_])" } else { "$_" } }
    $indent = $cloudInitTemplate -split "`n" | Where-Object { $_ -match "<python-requirements-py${pythonVersion}.txt>" } | ForEach-Object { $_.Split("<")[0] } | Select-Object -First 1
    $indentedContent = $pythonPackageVersions | ForEach-Object { "${indent}$_" } | Join-String -Separator "`n"
    $cloudInitTemplate = $cloudInitTemplate.Replace("${indent}<python-requirements-py${pythonVersion}.txt>", $indentedContent)
}


# Insert R package details into the cloud-init template
# -----------------------------------------------------
$cranPackages = Get-Content (Join-Path $PSScriptRoot ".." "packages" "packages-r-cran.list")
$bioconductorPackages = Get-Content (Join-Path $PSScriptRoot ".." "packages" "packages-r-bioconductor.list")
$rPackages = "- export CRAN_PACKAGES=`"$($cranPackages | Join-String -SingleQuote -Separator ', ')`"" + "`n  " + `
             "- export BIOCONDUCTOR_PACKAGES=`"$($bioconductorPackages | Join-String -SingleQuote -Separator ', ')`""
$cloudInitTemplate = $cloudInitTemplate.Replace("- <R package list>", $rPackages)


# Construct build VM parameters
# -----------------------------
$buildVmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.dsvmImage.keyVault.name -SecretName $config.keyVault.secretNames.buildImageAdminUsername -DefaultValue "dsvmbuildadmin"
$buildVmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.dsvmImage.keyVault.name -SecretName $config.keyVault.secretNames.buildImageAdminPassword -DefaultLength 20
$buildVmBootDiagnosticsAccount = Deploy-StorageAccount -Name $config.dsvmImage.bootdiagnostics.accountName -ResourceGroupName $config.dsvmImage.bootdiagnostics.rg -Location $config.dsvmImage.location
$buildVmName = "Candidate${buildVmName}-$(Get-Date -Format "yyyyMMddHHmm")"
$buildVmNic = Deploy-VirtualMachineNIC -Name "$buildVmName-NIC" -ResourceGroupName $config.dsvmImage.build.rg -Subnet $subnet -PublicIpAddressAllocation "Static" -Location $config.dsvmImage.location


# Deploy the VM
# -------------
Add-LogMessage -Level Info "Provisioning a new VM image in $($config.dsvmImage.build.rg) [$($config.dsvmImage.subscription)]..."
Add-LogMessage -Level Info "  VM name: $buildVmName"
Add-LogMessage -Level Info "  VM size: $vmSize"
Add-LogMessage -Level Info "  Base image: Ubuntu $baseImageSku"
$params = @{
    Name                   = $buildVmName
    Size                   = $vmSize
    AdminPassword          = $buildVmAdminPassword
    AdminUsername          = $buildVmAdminUsername
    BootDiagnosticsAccount = $buildVmBootDiagnosticsAccount
    CloudInitYaml          = $cloudInitTemplate
    location               = $config.dsvmImage.location
    NicId                  = $buildVmNic.Id
    OsDiskSizeGb           = 128
    OsDiskType             = "Standard_LRS"
    ResourceGroupName      = $config.dsvmImage.build.rg
    ImageSku               = $baseImageSku
}
$null = Deploy-UbuntuVirtualMachine @params -NoWait


# Log connection details for monitoring this build
# ------------------------------------------------
$publicIp = (Get-AzPublicIpAddress -ResourceGroupName $config.dsvmImage.build.rg | Where-Object { $_.Id -Like "*${buildVmName}-NIC-PIP" }).IpAddress
Add-LogMessage -Level Info "This process will take several hours to complete."
Add-LogMessage -Level Info "  You can monitor installation progress using: ssh $buildVmAdminUsername@$publicIp"
Add-LogMessage -Level Info "  The password for this account can be found in the '$($config.keyVault.secretNames.buildImageAdminPassword)' secret in the Azure Key Vault at:"
Add-LogMessage -Level Info "  $($config.dsvmImage.subscription) > $($config.dsvmImage.keyVault.rg) > $($config.dsvmImage.keyVault.name)"
Add-LogMessage -Level Info "  Once logged in, check the installation progress with: /opt/verification/analyse_build.py"
Add-LogMessage -Level Info "  The full log file can be viewed with: tail -f -n+1 /var/log/cloud-init-output.log"


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
