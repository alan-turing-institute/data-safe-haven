param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId,
  [Parameter(Position=1, HelpMessage = "Enter VM size to use (or leave empty to use default)")]
  [string]$vmSize = (Read-Host -prompt "Enter VM size to use (or leave empty to use default)"),
  [Parameter(Position=2, Mandatory = $true, HelpMessage = "Last octet of IP address")]
  [string]$ipLastOctet = (Read-Host -prompt "Last octet of IP address")
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force


# Get SRE config
# --------------
$config = Get-SreConfig($sreId);
$originalContext = Get-AzContext

# Set common variables
# --------------------
$imagesResourceGroup = "RG_SH_IMAGE_GALLERY"
$imagesGallery = "SAFE_HAVEN_COMPUTE_IMAGES"


# Switch to SRE subscription
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName;

# Set default VM size if no argument is provided
if (!$vmSize) { $vmSize = $config.dsg.dsvm.vmSizeDefault }

# Set IP address if we have a fixed IP
$vmIpAddress = $null
if ($ipLastOctet) { $vmIpAddress = $config.dsg.network.subnets.data.prefix + "." + $ipLastOctet }

# Set machine name
$vmName = "DSVM-SRE-" + (Get-Date -UFormat "%Y%m%d%H%M")
if ($ipLastOctet) { $vmName = $vmName + "-" + $ipLastOctet }

# Retrieve passwords from the keyvault
# ------------------------------------
Write-Host -ForegroundColor DarkCyan "Creating/retrieving secrets from '$($config.dsg.keyVault.name)' KeyVault..."
# $vmAdminPasswordSecretName = $config.dsg.keyVault.secretNames.dsvmAdminPassword
$_ = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dsvmLdapPassword
$_ = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dsvmAdminPassword

$deployScriptDir = Join-Path (Get-Item $PSScriptRoot).Parent.Parent "azure-vms" -Resolve
$cloudInitDir = Join-Path $PSScriptRoot ".." ".." "dsg_configs" "cloud_init" -Resolve

if($config.dsg.mirrors.cran.ip) {
    $mirrorUrlCran = "http://$($config.dsg.mirrors.cran.ip)"
} else {
    $mirrorUrlCran = "https://cran.r-project.org"
}
if($config.dsg.mirrors.pypi.ip) {
    $mirrorUrlPypi = "http://$($config.dsg.mirrors.pypi.ip):3128"
} else {
    $mirrorUrlPypi = "https://pypi.org"
}
# Read additional parameters that will be passed to the bash script from the config file
$adDcName = $config.shm.dc.hostname
$cloudInitYaml = "$cloudInitDir/cloud-init-compute-vm-DSG-" + $config.dsg.id + ".yaml"
$domainName = $config.shm.domain.fqdn
$ldapBaseDn = $config.shm.domain.userOuPath
$ldapBindDn = "CN=" + $config.dsg.users.ldap.dsvm.name + "," + $config.shm.domain.serviceOuPath
$ldapFilter = "(&(objectClass=user)(memberOf=CN=" + $config.dsg.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + "))"
# $ldapSecretName = $config.dsg.users.ldap.dsvm.passwordSecretName
$ldapUserName = $config.dsg.users.ldap.dsvm.samAccountName
$managementKeyvault = $config.dsg.keyVault.name
$managementSubnetIpRange = $config.shm.network.subnets.identity.cidr
$sourceImage = $config.dsg.dsvm.vmImageType
$sourceImageVersion = $config.dsg.dsvm.vmImageVersion
$subscriptionSource = $config.dsg.dsvm.vmImageSubscription
$subscriptionTarget = $config.dsg.subscriptionName
$targetNsgName = $config.dsg.network.nsg.data.name
$targetRg = $config.dsg.dsvm.rg
$targetSubnet = $config.dsg.network.subnets.data.name
$targetVnet = $config.dsg.network.vnet.name

# If there is no custom cloud-init YAML file then use the default
if (-Not (Test-Path -Path $cloudInitYaml)) {
  $cloudInitYaml = Join-Path $cloudInitDir "cloud-init-compute-vm-DEFAULT.yaml" -Resolve
}
Write-Output "Using cloud-init from '$cloudInitYaml'"

# Convert arguments into the format expected by deploy_azure_dsg_vm.sh
$arguments = "-s '$subscriptionSource' \
              -t '$subscriptionTarget' \
              -i $sourceImage \
              -x $sourceImageVersion \
              -g $targetNsgName \
              -r $targetRg \
              -v $targetVnet \
              -w $targetSubnet \
              -b '$ldapBaseDn' \
              -c '$ldapBindDn' \
              -f '$ldapFilter' \
              -j $ldapUserName \
              -l $($config.dsg.keyVault.secretNames.dsvmLdapPassword) \
              -m $managementKeyvault \
              -e $managementSubnetIpRange \
              -d $domainName \
              -a $adDcName \
              -p $($config.dsg.keyVault.secretNames.dsvmAdminPassword) \
              -n $vmName \
              -y $cloudInitYaml \
              -z $vmSize"

# Add additional arguments if needed
if ($vmIpAddress) { $arguments = $arguments + " -q $vmIpAddress" }
if ($mirrorUrlCran) { $arguments = $arguments + " -o $mirrorUrlCran" }
if ($mirrorUrlPypi) { $arguments = $arguments + " -k $mirrorUrlPypi" }

# Write-Host $arguments
# $cmd =  "$deployScriptDir/deploy_azure_compute_vm.sh $arguments"
# bash -c $cmd

# Write-Host "Configuring Postgres shared admin, write and read users"
# $_ = Invoke-Expression -Command "$PSScriptRoot\Create_Postgres_Roles.ps1 -sreId $sreId -ipLastOctet $ipLastOctet"
# Write-Host "VM deployment done."


# Get list of image versions
# --------------------------
Write-Host -ForegroundColor DarkCyan "Getting image type from gallery..."
$_ = Set-AzContext -Subscription $config.dsg.dsvm.vmImageSubscription
if ($config.dsg.dsvm.vmImageType -eq "Ubuntu") {
    $imageDefinition = "ComputeVM-Ubuntu1804Base"
} elseif ($config.dsg.dsvm.vmImageType -eq "UbuntuTorch") {
    $imageDefinition = "ComputeVM-UbuntuTorch1804Base"
} elseif ($config.dsg.dsvm.vmImageType -eq "DataScience") {
    $imageDefinition = "ComputeVM-DataScienceBase"
} elseif ($config.dsg.dsvm.vmImageType -eq "DSG") {
    $imageDefinition = "ComputeVM-DsgBase"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Could not interpret $($config.dsg.dsvm.vmImageType) as an image type!"
    throw "Could not interpret $($config.dsg.dsvm.vmImageType) as an image type!"
}
Write-Host -ForegroundColor DarkGreen " [o] Using image type $imageDefinition"


# Check that this is a valid version and then get the image ID
# ------------------------------------------------------------
$imageVersion = $config.dsg.dsvm.vmImageVersion
Write-Host -ForegroundColor DarkCyan "Finding ID for image $imageDefinition version $imageVersion..."
try {
    $image = Get-AzGalleryImageVersion -ResourceGroup $imagesResourceGroup -GalleryName $imagesGallery -GalleryImageDefinitionName $imageDefinition -GalleryImageVersionName $imageVersion -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
    $versions = Get-AzGalleryImageVersion -ResourceGroup $imagesResourceGroup -GalleryName $imagesGallery -GalleryImageDefinitionName $imageDefinition | Sort-Object Name | % {$_.Name} #Select-Object -Last 1
    Write-Host -ForegroundColor DarkRed " [x] Image version '$imageVersion' is invalid. Available versions are: $versions"
    $imageVersion = $versions | Select-Object -Last 1
    $userVersion = Read-Host -Prompt "Enter the version you would like to use (or leave empty to accept the default: '$imageVersion')"
    if ($versions.Contains($userVersion)) {
        $imageVersion = $userVersion
    }
    $image = Get-AzGalleryImageVersion -ResourceGroup $imagesResourceGroup -GalleryName $imagesGallery -GalleryImageDefinitionName $imageDefinition -GalleryImageVersionName $imageVersion -ErrorAction Stop
}
$imageVersion = $image.Name
Write-Host -ForegroundColor DarkCyan "Using image $imageDefinition version $imageVersion"
# '$($image.Id)'


# Setup resource group if it does not already exist
# -------------------------------------------------
$_ = New-AzResourceGroup -Name $config.dsg.dsvm.rg -Location $config.dsg.location -Force


# Check that secure NSG exists
# ----------------------------
# DSG_NSG_RG=""
# DSG_NSG_ID=""
# for RG in $(az group list --query "[].name" -o tsv); do
#     if [ "$(az network nsg show --resource-group $RG --name $DSG_NSG 2> /dev/null)" != "" ]; then
#         DSG_NSG_RG=$RG;
#         DSG_NSG_ID=$(az network nsg show --resource-group $RG --name $DSG_NSG --query 'id' | xargs)
#     fi
# done
# if [ "$DSG_NSG_RG" = "" ]; then
#     echo -e "${RED}Could not find NSG ${BLUE}$DSG_NSG${END} ${RED}in any resource group${END}"
#     print_usage_and_exit
# else
#     echo -e "${BOLD}Found NSG ${BLUE}$DSG_NSG${END} ${BOLD}in resource group ${BLUE}$DSG_NSG_RG${END}"
# fi