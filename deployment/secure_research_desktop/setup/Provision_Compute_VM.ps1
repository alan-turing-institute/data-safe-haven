param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $false, HelpMessage = "Source image (one of 'Ubuntu1804' or 'Ubuntu2004' [default]")]
    [ValidateSet("Ubuntu1804", "Ubuntu2004")]
    [string]$sourceImage = "Ubuntu2004",
    [Parameter(Mandatory = $false, HelpMessage = "VM size to use (e.g. 'Standard_E4_v3'. Using 'default' will use the value from the configuration file)")]
    [ValidateSet("default", "Standard_D4_v3", "Standard_E2_v3", "Standard_E4_v3", "Standard_E8_v3", "Standard_F4s_v2", "Standard_F8s_v2", "Standard_H8")]
    [string]$vmSize = "default"
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.srdImage.subscription -ErrorAction Stop


# Select which VM size to use
# ---------------------------
if ($vmSize -eq "default") { $vmSize = $config.srdImage.build.vm.size }


# Select which source URN to base the build on
# --------------------------------------------
if ($sourceImage -eq "Ubuntu1804") {
    $baseImageSku = "18.04-LTS"
    $shortVersion = "1804"
    Add-LogMessage -Level Warning "Note that '$sourceImage' is out-of-date. Please consider using a newer base Ubuntu version."
} elseif ($sourceImage -eq "Ubuntu2004") {
    $baseImageSku = "20.04-LTS"
    $shortVersion = "2004"
} else {
    Add-LogMessage -Level Fatal "Did not recognise source image '$sourceImage'!"
}
$buildVmName = "SecureResearchDesktop-Ubuntu${shortVersion}"
$cloudInitTemplate = Get-Content (Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-buildimage-ubuntu-${shortVersion}.mustache.yaml") -Raw


# Create resource groups if they do not exist
# -------------------------------------------
$null = Deploy-ResourceGroup -Name $config.srdImage.build.rg -Location $config.srdImage.location
$null = Deploy-ResourceGroup -Name $config.srdImage.bootdiagnostics.rg -Location $config.srdImage.location
$null = Deploy-ResourceGroup -Name $config.srdImage.network.rg -Location $config.srdImage.location
$null = Deploy-ResourceGroup -Name $config.srdImage.keyVault.rg -Location $config.srdImage.location


# Ensure the Key Vault exists and set its access policies
# -------------------------------------------------------
$null = Deploy-KeyVault -Name $config.srdImage.keyVault.name -ResourceGroupName $config.srdImage.keyVault.rg -Location $config.srdImage.location
Set-KeyVaultPermissions -Name $config.srdImage.keyVault.name -GroupName $config.azureAdminGroupName


# Ensure that VNET and subnet exist
# ---------------------------------
$vnet = Deploy-VirtualNetwork -Name $config.srdImage.build.vnet.name -ResourceGroupName $config.srdImage.network.rg -AddressPrefix $config.srdImage.build.vnet.cidr -Location $config.srdImage.location
$subnet = Deploy-Subnet -Name $config.srdImage.build.subnet.name -VirtualNetwork $vnet -AddressPrefix $config.srdImage.build.subnet.cidr


# Ensure that build NSG exists with correct rules and attach it to the build subnet
# ---------------------------------------------------------------------------------
Add-LogMessage -Level Info "Ensure that build NSG '$($config.srdImage.build.nsg.name)' exists..."
$buildNsg = Deploy-NetworkSecurityGroup -Name $config.srdImage.build.nsg.name -ResourceGroupName $config.srdImage.network.rg -Location $config.srdImage.location
# Get list of IP addresses which are allowed to connect to the VM candidates
$existingRule = Get-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $buildNsg | Where-Object { $_.Name -eq "AllowBuildAdminSshInbound" }
$allowedIpAddresses = @($config.srdImage.build.nsg.allowedIpAddresses)
$allowedIpAddresses += $existingRule ? @($existingRule.SourceAddressPrefix) : @()
$config["buildAdminIpAddresses"] = $allowedIpAddresses | Where-Object { $_ } | Sort-Object | Get-Unique
# Update the NSG and ensure it is connected to the correct subnet
$rules = Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $config.srdImage.build.nsg.rules) -Parameters $config -AsHashtable
$null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $buildNsg -Rules $rules
$subnet = Set-SubnetNetworkSecurityGroup -Subnet $subnet -NetworkSecurityGroup $buildNsg


# Load the cloud-init template then add resources and expand mustache placeholders
# --------------------------------------------------------------------------------
$config["dbeaver"] = @{
    drivers = $(Get-Content -Raw -Path "../packages/dbeaver-driver-versions.json" | ConvertFrom-Json -AsHashtable)
}
$cloudInitTemplate = Expand-CloudInitResources -Template $cloudInitTemplate -ResourcePath (Join-Path $PSScriptRoot ".." "cloud_init" "resources")
$cloudInitTemplate = Expand-CloudInitResources -Template $cloudInitTemplate -ResourcePath (Join-Path $PSScriptRoot ".." "packages")
$cloudInitTemplate = Expand-MustacheTemplate -Template $cloudInitTemplate -Parameters $config


# Construct build VM parameters
# -----------------------------
$buildVmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.srdImage.keyVault.name -SecretName $config.keyVault.secretNames.buildImageAdminUsername -DefaultValue "srdbuildadmin" -AsPlaintext
$buildVmBootDiagnosticsAccount = Deploy-StorageAccount -Name $config.srdImage.bootdiagnostics.accountName -ResourceGroupName $config.srdImage.bootdiagnostics.rg -Location $config.srdImage.location
$buildVmName = "Candidate${buildVmName}-$(Get-Date -Format "yyyyMMddHHmm")"
$buildVmNic = Deploy-VirtualMachineNIC -Name "$buildVmName-NIC" -ResourceGroupName $config.srdImage.build.rg -Subnet $subnet -PublicIpAddressAllocation "Static" -Location $config.srdImage.location
$adminPasswordName = "$($config.keyVault.secretNames.buildImageAdminPassword)-${buildVmName}"


# Check cloud-init size
# ---------------------
$CloudInitEncodedLength = ($cloudInitTemplate | ConvertTo-Base64).Length
if ($CloudInitEncodedLength / 87380 -gt 0.9) {
    Add-LogMessage -Level Warning "The current cloud-init size ($CloudInitEncodedLength Base64 characters) is more than 90% of the limit of 87380 characters!"
}


# Deploy the VM
# -------------
Add-LogMessage -Level Info "Provisioning a new VM image in $($config.srdImage.build.rg) '$($config.srdImage.subscription)'..."
Add-LogMessage -Level Info "  VM name: $buildVmName"
Add-LogMessage -Level Info "  VM size: $vmSize"
Add-LogMessage -Level Info "  Base image: Ubuntu $baseImageSku"
$params = @{
    Name                   = $buildVmName
    Size                   = $vmSize
    AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.srdImage.keyVault.name -SecretName $adminPasswordName -DefaultLength 20)
    AdminUsername          = $buildVmAdminUsername
    BootDiagnosticsAccount = $buildVmBootDiagnosticsAccount
    CloudInitYaml          = $cloudInitTemplate
    Location               = $config.srdImage.location
    NicId                  = $buildVmNic.Id
    OsDiskSizeGb           = $config.srdImage.build.vm.diskSizeGb
    OsDiskType             = "Standard_LRS"
    ResourceGroupName      = $config.srdImage.build.rg
    ImageSku               = $baseImageSku
}
$vm = Deploy-UbuntuVirtualMachine @params -NoWait


# Tag the VM with the git commit hash
# -----------------------------------
$null = New-AzTag -ResourceId $vm.Id -Tag @{"Build commit hash" = $(git rev-parse --verify HEAD) }


# Log connection details for monitoring this build
# ------------------------------------------------
$publicIp = (Get-AzPublicIpAddress -ResourceGroupName $config.srdImage.build.rg | Where-Object { $_.Id -Like "*${buildVmName}-NIC-PIP" }).IpAddress
Add-LogMessage -Level Info "This process will take several hours to complete."
Add-LogMessage -Level Info "  You can monitor installation progress using: ssh $buildVmAdminUsername@$publicIp"
Add-LogMessage -Level Info "  The password for this account can be found in the '${adminPasswordName}' secret in the Azure Key Vault at:"
Add-LogMessage -Level Info "  $($config.srdImage.subscription) > $($config.srdImage.keyVault.rg) > $($config.srdImage.keyVault.name)"
Add-LogMessage -Level Info "  Once logged in, check the installation progress with: /opt/monitoring/analyse_build.py"
Add-LogMessage -Level Info "  The full log file can be viewed with: tail -f -n+1 /var/log/cloud-init-output.log"


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
