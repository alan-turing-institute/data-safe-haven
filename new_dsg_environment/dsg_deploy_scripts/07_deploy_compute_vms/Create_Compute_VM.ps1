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
$deploymentNsgName = "NSG_IMAGE_DEPLOYMENT"
$secureNsgName = $config.dsg.network.nsg.data.name

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
Write-Host -ForegroundColor DarkCyan "Looking for image $imageDefinition version $imageVersion..."
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
Write-Host -ForegroundColor DarkGreen " [o] Found image $imageDefinition version $imageVersion in gallery"
# '$($image.Id)'


# Setup resource group if it does not already exist
# -------------------------------------------------
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName
$_ = New-AzResourceGroup -Name $config.dsg.dsvm.rg -Location $config.dsg.location -Force


# Check that secure NSG exists
# ----------------------------
Write-Host -ForegroundColor DarkCyan "Looking for secure NSG '$secureNsgName'..."
$secureNsg = $null
try {
    $secureNsg = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.network.vnet.rg -Name $secureNsgName  -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
    Write-Host -ForegroundColor DarkRed " [x] NSG '$($secureNsgName )' could not be found!"
    throw "NSG '$($secureNsgName )' could not be found!"
}
Write-Host -ForegroundColor DarkGreen " [o] Found secure NSG '$($secureNsg.Name)' in $($secureNsg.ResourceGroupName)"


# Check that deployment NSG exists
# --------------------------------
Write-Host -ForegroundColor DarkCyan "Looking for deployment NSG '$deploymentNsgName'..."
$deploymentNsg = $null
try {
    $deploymentNsg = Get-AzNetworkSecurityGroup -Name $deploymentNsgName -ResourceGroupName $config.dsg.network.vnet.rg -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Network.Common.NetworkCloudException] {
    Write-Host -ForegroundColor DarkCyan "Creating new NSG '$($deploymentNsgName)'"
    $managementSubnetIpRange = $config.shm.network.subnets.identity.cidr
    # Inbound: allow LDAP then deny all
    $ruleInbound1 = New-AzNetworkSecurityRuleConfig -Access "Allow" `
                                                    -Description "Inbound allow LDAP" `
                                                    -DestinationAddressPrefix "VirtualNetwork" `
                                                    -DestinationPortRange "*" `
                                                    -Direction "Inbound" `
                                                    -Name "InboundAllowLDAP" `
                                                    -Priority 2000 `
                                                    -Protocol "*" `
                                                    -SourceAddressPrefix $managementSubnetIpRange `
                                                    -SourcePortRange 88,389,636
    $ruleInbound2 = New-AzNetworkSecurityRuleConfig -Access "Deny" `
                                                    -Description "Inbound deny all" `
                                                    -DestinationAddressPrefix "*" `
                                                    -DestinationPortRange "*" `
                                                    -Direction "Inbound" `
                                                    -Name "InboundDenyAll" `
                                                    -Priority 3000 `
                                                    -Protocol "*" `
                                                    -SourceAddressPrefix "*" `
                                                    -SourcePortRange "*"
    # Outbound: allow LDAP then deny all Virtual Network
    $ruleOutbound1 = New-AzNetworkSecurityRuleConfig -Access "Allow" `
                                                     -Description "Outbound allow LDAP" `
                                                     -DestinationAddressPrefix $managementSubnetIpRange `
                                                     -DestinationPortRange "*" `
                                                     -Direction "Outbound" `
                                                     -Name "OutboundAllowLDAP" `
                                                     -Priority 2000 `
                                                     -Protocol "*" `
                                                     -SourceAddressPrefix "VirtualNetwork" `
                                                     -SourcePortRange "*"
    $ruleOutbound2 = New-AzNetworkSecurityRuleConfig -Access "Deny" `
                                                     -Description "Outbound deny virtual network" `
                                                     -DestinationAddressPrefix "VirtualNetwork" `
                                                     -DestinationPortRange "*" `
                                                     -Direction "Outbound" `
                                                     -Name "OutboundDenyVNet" `
                                                     -Priority 3000 `
                                                     -Protocol "*" `
                                                     -SourceAddressPrefix "*" `
                                                     -SourcePortRange "*"
    # Create deployment NSG
    $deploymentNsg = New-AzNetworkSecurityGroup -Name $deploymentNsgName -ResourceGroupName $config.dsg.network.vnet.rg -Location $config.dsg.location -SecurityRules $ruleInbound1,$ruleInbound2,$ruleOutbound1,$ruleOutbound2
} catch {
    Write-Host $_.Exception.GetType()
}
Write-Host -ForegroundColor DarkGreen " [o] Found deployment NSG '$($deploymentNsg.Name)' in $($deploymentNsg.ResourceGroupName)"
Write-Host $deploymentNsg


# Check that VNET and subnet exist
# --------------------------------

# DSG_SUBNET_RG=""
# DSG_SUBNET_ID=""
# for RG in $(az group list --query "[].name" -o tsv); do
#     # Check that VNET exists with subnet inside it
#     if [ "$(az network vnet subnet list --resource-group $RG --vnet-name $DSG_VNET 2> /dev/null | grep $DSG_SUBNET)" != "" ]; then
#         DSG_SUBNET_RG=$RG;
#         DSG_SUBNET_ID=$(az network vnet subnet list --resource-group $RG --vnet-name $DSG_VNET --query "[?name == '$DSG_SUBNET'].id | [0]" | xargs)
#     fi
# done
# if [ "$DSG_SUBNET_RG" = "" ]; then
#     echo -e "${RED}Could not find subnet ${BLUE}$DSG_SUBNET${END} ${RED}in vnet ${BLUE}$DSG_VNET${END} in ${RED}any resource group${END}"
#     print_usage_and_exit
# else
#     echo -e "${BOLD}Found subnet ${BLUE}$DSG_SUBNET${END} ${BOLD}as part of VNET ${BLUE}$DSG_VNET${END} ${BOLD}in resource group ${BLUE}$DSG_SUBNET_RG${END}"
# fi

# # If using the Data Science VM then the terms must be added before creating the VM
# PLANDETAILS=""
# if [[ "$SOURCEIMAGE" == *"DataScienceBase"* ]]; then
#     PLANDETAILS="--plan-name linuxdsvmubuntubyol --plan-publisher microsoft-ads --plan-product linux-data-science-vm-ubuntu"
# fi


# # Construct the cloud-init yaml file for the target subscription
# # --------------------------------------------------------------
# # Retrieve admin password from keyvault
# ADMIN_PASSWORD=$(az keyvault secret show --vault-name $MANAGEMENT_VAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

# # Get LDAP secret file with password in it (can't pass as a secret at VM creation)
# LDAP_SECRET_PLAINTEXT=$(az keyvault secret show --vault-name $MANAGEMENT_VAULT_NAME --name $LDAP_SECRET_NAME --query "value" | xargs)

# # Create a new config file with the appropriate username and LDAP password
# TMP_CLOUD_CONFIG_YAML="$(mktemp).yaml"
# DOMAIN_UPPER=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
# DOMAIN_LOWER=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]')
# AD_DC_NAME_UPPER=$(echo "$AD_DC_NAME" | tr '[:lower:]' '[:upper:]')
# AD_DC_NAME_LOWER=$(echo "$AD_DC_NAME" | tr '[:upper:]' '[:lower:]')

# # Define regexes
# USERNAME_REGEX="s/USERNAME/"${USERNAME}"/g"
# LDAP_SECRET_REGEX="s/LDAP_SECRET_PLAINTEXT/"${LDAP_SECRET_PLAINTEXT}"/g"
# MACHINE_NAME_REGEX="s/MACHINENAME/${MACHINENAME}/g"
# LDAP_USER_REGEX="s/LDAP_USER/${LDAP_USER}/g"
# DOMAIN_LOWER_REGEX="s/DOMAIN_LOWER/${DOMAIN_LOWER}/g"
# DOMAIN_UPPER_REGEX="s/DOMAIN_UPPER/${DOMAIN_UPPER}/g"
# LDAP_BASE_DN_REGEX="s/LDAP_BASE_DN/${LDAP_BASE_DN}/g"
# LDAP_BIND_DN_REGEX="s/LDAP_BIND_DN/${LDAP_BIND_DN}/g"
# # Escape ampersand in the LDAP filter as it is a special character for sed
# LDAP_FILTER_ESCAPED=${LDAP_FILTER/"&"/"\&"}
# LDAP_FILTER_REGEX="s/LDAP_FILTER/${LDAP_FILTER_ESCAPED}/g"
# AD_DC_NAME_UPPER_REGEX="s/AD_DC_NAME_UPPER/${AD_DC_NAME_UPPER}/g"
# AD_DC_NAME_LOWER_REGEX="s/AD_DC_NAME_LOWER/${AD_DC_NAME_LOWER}/g"
# PYPI_MIRROR_URL_REGEX="s|PYPI_MIRROR_URL|${PYPI_MIRROR_URL}|g"
# PYPI_MIRROR_HOST_REGEX="s|PYPI_MIRROR_HOST|${PYPI_MIRROR_HOST}|g"
# CRAN_MIRROR_URL_REGEX="s|CRAN_MIRROR_URL|${CRAN_MIRROR_URL}|g"

# # Substitute regexes
# sed -e "${USERNAME_REGEX}" -e "${LDAP_SECRET_REGEX}" -e "${MACHINE_NAME_REGEX}" -e "${LDAP_USER_REGEX}" -e "${DOMAIN_LOWER_REGEX}" -e "${DOMAIN_UPPER_REGEX}" -e "${LDAP_CN_REGEX}" -e "${LDAP_BASE_DN_REGEX}" -e "${LDAP_FILTER_REGEX}" -e "${LDAP_BIND_DN_REGEX}" -e  "${AD_DC_NAME_UPPER_REGEX}" -e "${AD_DC_NAME_LOWER_REGEX}" -e "${PYPI_MIRROR_URL_REGEX}" -e "${PYPI_MIRROR_HOST_REGEX}" -e "${CRAN_MIRROR_URL_REGEX}" $CLOUD_INIT_YAML > $TMP_CLOUD_CONFIG_YAML

# # Create the data disk
# echo -e "${BOLD}Creating ${BLUE}${DATA_DISK_SIZE_GB} GB${END}${BOLD} datadisk...${END}"
# DATA_DISK_NAME="${MACHINENAME}DATADISK"
# az disk create --resource-group $RESOURCEGROUP --name $DATA_DISK_NAME --location $LOCATION --sku $DATA_DISK_TYPE --size-gb $DATA_DISK_SIZE_GB --output none

# DEPLOYMENT_NSG_ID=$(az network nsg show --resource-group $DSG_NSG_RG --name $DEPLOYMENT_NSG --query 'id' | xargs)
# echo -e "${BOLD}Deploying into NSG ${BLUE}$DEPLOYMENT_NSG${END} ${BOLD}with outbound internet access to allow package installation. Will switch NSGs at end of deployment.${END}"

# # Create the VM based off the selected source image
# # -------------------------------------------------
# echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME${END} ${BOLD}as part of ${BLUE}$RESOURCEGROUP${END}"
# echo -e "${BOLD}This will use the ${BLUE}$SOURCEIMAGE${END}${BOLD}-based compute machine image${END}"
# echo -e "${BOLD}Starting deployment at $(date)${END}"
# STARTTIME=$(date +%s)

# if [ "$IP_ADDRESS" = "" ]; then
#     echo -e "${BOLD}Requesting a dynamic IP address${END}"
#     az vm create ${PLANDETAILS} \
#         --admin-password $ADMIN_PASSWORD \
#         --admin-username $USERNAME \
#         --attach-data-disks $DATA_DISK_NAME \
#         --custom-data $TMP_CLOUD_CONFIG_YAML \
#         --image $IMAGE_ID \
#         --name $MACHINENAME \
#         --nsg $DEPLOYMENT_NSG_ID \
#         --os-disk-name "${MACHINENAME}OSDISK" \
#         --os-disk-size-gb $OS_DISK_SIZE_GB \
#         --public-ip-address "" \
#         --resource-group $RESOURCEGROUP \
#         --size $VM_SIZE \
#         --storage-sku $OS_DISK_TYPE \
#         --subnet $DSG_SUBNET_ID \
#         --output none
# else
#     echo -e "${BOLD}Creating VM with static IP address ${BLUE}$IP_ADDRESS${END}"
#     az vm create ${PLANDETAILS} \
#         --admin-password $ADMIN_PASSWORD \
#         --admin-username $USERNAME \
#         --attach-data-disks $DATA_DISK_NAME \
#         --custom-data $TMP_CLOUD_CONFIG_YAML \
#         --image $IMAGE_ID \
#         --name $MACHINENAME \
#         --nsg $DEPLOYMENT_NSG_ID \
#         --os-disk-name "${MACHINENAME}OSDISK" \
#         --os-disk-size-gb $OS_DISK_SIZE_GB \
#         --private-ip-address $IP_ADDRESS \
#         --public-ip-address "" \
#         --resource-group $RESOURCEGROUP \
#         --size $VM_SIZE \
#         --storage-sku $OS_DISK_TYPE \
#         --subnet $DSG_SUBNET_ID \
#         --output none
# fi
# # Remove temporary init file if it exists
# rm $TMP_CLOUD_CONFIG_YAML 2> /dev/null
# echo -e "${BOLD}VM creation finished at $(date)${END}"
# echo -e "${BOLD}Running cloud-init for deployment...${END}"

# # allow some time for the system to finish initialising
# sleep 30

# # Poll VM to see whether it has finished running
# echo -e "${BOLD}Waiting for VM setup to finish (this will take 5+ minutes)...${END}"
# # Check that VM is down by requiring "PowerState/stopped" and "ProvisioningState/succeeded"
# az vm wait --name $MACHINENAME --resource-group $RESOURCEGROUP --custom "length((instanceView.statuses[].code)[?(contains(@, 'PowerState/stopped') || contains(@, 'ProvisioningState/succeeded'))]) == \`2\`"

# # VM must be off for us to switch NSG. Once done we restart
# echo -e "${BOLD}Switching to secure NSG ${BLUE}${DSG_NSG}${END} ${BOLD}at $(date)${END}"
# az network nic update --resource-group $RESOURCEGROUP --name "${MACHINENAME}VMNic" --network-security-group $DSG_NSG_ID --output none
# echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME}${END} ${BOLD}at $(date)${END}"
# az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME

# # Poll VM to see whether it has finished restarting
# echo -e "${BOLD}Waiting for VM to restart...${END}"
# # Check that VM is up by requiring "PowerState/running" and "ProvisioningState/succeeded"
# az vm wait --name $MACHINENAME --resource-group $RESOURCEGROUP --custom "length((instanceView.statuses[].code)[?(contains(@, 'PowerState/running') || contains(@, 'ProvisioningState/succeeded'))]) == \`2\`"

# # Get public IP address for this machine. Piping to echo removes the quotemarks around the address
# PRIVATEIP=$(az vm list-ip-addresses --resource-group $RESOURCEGROUP --name $MACHINENAME --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)
# echo -e "${BOLD}Deployment complete at $(date)${END}"
# echo -e "${BOLD}This new VM can be accessed with SSH or remote desktop at ${BLUE}${PRIVATEIP}${END}"
