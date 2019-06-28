#! /bin/bash

# Load common constants and options
source ${BASH_SOURCE%/*}/configs/images.sh
source ${BASH_SOURCE%/*}/configs/text.sh

SOURCEIMAGE="Ubuntu"
VMSIZE="Standard_E16s_v3"

# Other constants
ADMIN_USERNAME="atiadmin"
MACHINENAME="ComputeVM"
NSGNAME="NSG_IMAGE_BUILD"
VNETNAME="VNET_IMAGE_BUILD"
SUBNETNAME="SUBNET_IMAGE_BUILD"
IP_RANGE="10.48.0.0/16" # ensure that this avoids clashes with other deployments

# Document usage for this script
print_usage_and_exit() {
    echo "usage: $0 [-h] -s subscription [-i source_image] [-r resource_group] [-z vm_size]"
    echo "  -h                           display help"
    echo "  -s subscription              specify subscription for storing the VM images. (defaults to '${SUBSCRIPTION}')"
    echo "  -i source_image              specify source image: either 'Ubuntu' (default) or 'UbuntuTorch' (as 'Ubuntu' but with Torch included)"
    echo "  -r resource_group            specify resource group - will be created if it does not already exist (defaults to '${RESOURCEGROUP_BUILD}')"
    echo "  -z vm_size                   size of the VM to use for build (defaults to '${VMSIZE}')"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "hi:r:s:z:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        i)
            SOURCEIMAGE=$OPTARG
            ;;
        r)
            RESOURCEGROUP_BUILD=$OPTARG
            ;;
        s)
            SUBSCRIPTION=$OPTARG
            ;;
        z)
            VMSIZE=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done

# Check that source image is "Ubuntu"
if [ "$SOURCEIMAGE" != "Ubuntu" ]; then
    echo -e "${RED}At the moment we only support building the Ubuntu Compute VM${END}"
    print_usage_and_exit
fi

# Check that a subscription has been provided and switch to it
if [ "$SUBSCRIPTION" = "" ]; then
    echo -e "${RED}Subscription is a required argument!${END}"
    print_usage_and_exit
fi
az account set --subscription "$SUBSCRIPTION"

# Setup building resource group if it does not already exist
# - have to build in West Europe in order to use Shared Image Gallery
if [ $(az group exists --name $RESOURCEGROUP_BUILD) != "true" ]; then
    echo -e "${BOLD}Creating resource group ${BLUE}$RESOURCEGROUP_BUILD${END}"
    az group create --name $RESOURCEGROUP_BUILD --location $LOCATION
fi

# Setup networking resource group if it does not already exist
# - have to build in West Europe in order to use Shared Image Gallery
if [ $(az group exists --name $RESOURCEGROUP_NETWORK) != "true" ]; then
    echo -e "${BOLD}Creating resource group ${BLUE}$RESOURCEGROUP_NETWORK${END}"
    az group create --name $RESOURCEGROUP_NETWORK --location $LOCATION
fi

# Ensure required features for shared image galleries are enabled for this subscription
FEATURE="GalleryPreview"
NAMESPACE="Microsoft.Compute"
FEATURE_STATE="$(az feature show --namespace $NAMESPACE --name $FEATURE --query 'properties.state' | xargs)"
RESOURCE="galleries/images/versions"
RESOURCE_METADATA_QUERY="resourceTypes[?resourceType=='$RESOURCE']"
RESOURCE_METADATA="$(az provider show --namespace $NAMESPACE --query $RESOURCE_METADATA_QUERY)"
# Print out current status
echo -e "${BOLD}Ensuring namespace ${BLUE}$NAMESPACE${END} ${BOLD}contains ${BLUE}$FEATURE${END} ${BOLD}feature and ${BLUE}$RESOURCE${END} ${BOLD}(this may take some time).${END}"
echo -e "${BOLD}Current ${BLUE}$FEATURE${END} ${BOLD}feature state is ${BLUE}$FEATURE_STATE.${END}"
if [ "$RESOURCE_METADATA" = "[]" ]; then
    echo -e "${BOLD}Resource ${BLUE}$RESOURCE${END} ${BOLD}is ${RED}not${END} ${BOLD}present.${END}"
else
    echo -e "${BOLD}Resource ${BLUE}$RESOURCE${END} ${BOLD}is present.${END}"
fi
# Loop until features are present
while [ "$FEATURE_STATE" != "Registered"  -o  "$RESOURCE_METADATA" = "[]" ]; do
    if [ "$FEATURE_STATE" = "NotRegistered" ]; then
        # Register feature
        echo -e "${BOLD}Registering ${BLUE}$FEATURE${END} ${BOLD}for ${BLUE}$SUBSCRIPTION${END}"
        az feature register --namespace Microsoft.Compute --name "$FEATURE" --subscription "$SUBSCRIPTION"
        az provider register --namespace Microsoft.Compute
    elif [ "$FEATURE_STATE" = "Pending"  -o  "$FEATURE_STATE" = "Registering" -o "$RESOURCE_METADATA" = "[]" ]; then
        echo -ne "."
        sleep 30
    else
        echo -e "${RED}$FEATURE state or $RESOURCE resource could not be found. Try updating Azure CLI.${END}"
        exit 1
    fi
    FEATURE_STATE="$(az feature show --namespace $NAMESPACE --name $FEATURE --query 'properties.state' | xargs)"
    RESOURCE_METADATA="$(az provider show --namespace $NAMESPACE --query $RESOURCE_METADATA_QUERY)"
done

# Create a VNet and subnet for the deployment
if [ "$(az network vnet list --resource-group $RESOURCEGROUP_NETWORK | grep $VNETNAME 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating VNet for image building: ${BLUE}$VNETNAME${END}"
    az network vnet create --resource-group $RESOURCEGROUP_NETWORK --name $VNETNAME --address-prefixes $IP_RANGE
fi
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP_NETWORK --vnet-name $VNETNAME | grep $SUBNETNAME 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating subnet for image building: ${BLUE}$SUBNETNAME${END}"
    az network vnet subnet create --name $SUBNETNAME --resource-group $RESOURCEGROUP_NETWORK --vnet-name $VNETNAME --address-prefixes $IP_RANGE
fi

# Add an NSG group to deny inbound connections except Turing-based SSH
if [ "$(az network nsg show --resource-group $RESOURCEGROUP_NETWORK --name $NSGNAME 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating NSG for image build: ${BLUE}$NSGNAME${END}"
    az network nsg create --resource-group $RESOURCEGROUP_NETWORK --name $NSGNAME
    az network nsg rule create \
        --description "Allow port 22 for management over ssh" \
        --destination-address-prefixes "*" \
        --destination-port-ranges 22 \
        --direction Inbound \
        --name TuringSSH \
        --nsg-name $NSGNAME \
        --priority 100 \
        --protocol TCP \
        --resource-group $RESOURCEGROUP_NETWORK \
        --source-address-prefixes 193.60.220.240 193.60.220.253 \
        --source-port-ranges "*"
    az network nsg rule create \
        --access "Deny" \
        --description "Deny all" \
        --destination-address-prefixes "*" \
        --destination-port-ranges "*" \
        --direction Inbound \
        --name DenyAll \
        --nsg-name $NSGNAME \
        --priority 3000 \
        --protocol "*" \
        --resource-group $RESOURCEGROUP_NETWORK \
        --source-address-prefixes "*" \
        --source-port-ranges "*"
fi

# Select source image - either Ubuntu 18.04 or Ubuntu 18.04 plus Torch
# If anything else is requested then print usage message and exit.
TMP_CLOUD_CONFIG_YAML="$(mktemp).yaml"
if [ "$SOURCEIMAGE" = "Ubuntu" -o "$SOURCEIMAGE" = "UbuntuTorch" ]; then
    if [ "$SOURCEIMAGE" = "UbuntuTorch" ]; then
        echo -e "${BOLD}Enabling ${BLUE}Torch${END}${BOLD} compilation${END}"
        # Make a temporary config file with the Torch lines uncommented
        sed "s/#IF_TORCH_ENABLED //" cloud-init-buildimage-ubuntu.yaml > $TMP_CLOUD_CONFIG_YAML
        MACHINENAME="${MACHINENAME}-UbuntuTorch1804Base"
    else
        MACHINENAME="${MACHINENAME}-Ubuntu1804Base"
        cp cloud-init-buildimage-ubuntu.yaml $TMP_CLOUD_CONFIG_YAML
    fi
    SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"
    DISKSIZEGB="60"
else
    echo -e "${RED}Did not recognise image name: $SOURCEIMAGE!${END}"
    print_usage_and_exit
fi

# Append timestamp to allow unique naming
TIMESTAMP="$(date '+%Y%m%d%H%M')"
BASENAME="Generalized${MACHINENAME}-${TIMESTAMP}"

# Build python package lists
cd package_lists && source generate_python_package_specs.sh > ../python_package_specs.yaml && cd ..
sed -i -e '/# === AUTOGENERATED ANACONDA PACKAGES START HERE ===/r./python_package_specs.yaml' $TMP_CLOUD_CONFIG_YAML
rm python_package_specs.yaml

# Build R package lists
cd package_lists && source generate_r_package_specs.sh > ../r_package_specs.yaml && cd ..
sed -i -e '/# === AUTOGENERATED R PACKAGES START HERE ===/r./r_package_specs.yaml' $TMP_CLOUD_CONFIG_YAML
rm r_package_specs.yaml

# Create the VM based off the selected source image
echo -e "${BOLD}Provisioning a new VM image in ${BLUE}$RESOURCEGROUP_BUILD${END} ${BOLD}as part of ${BLUE}$SUBSCRIPTION${END}"
echo -e "${BOLD}  VM name: ${BLUE}$BASENAME${END}"
echo -e "${BOLD}  Base image: ${BLUE}$SOURCEIMAGE${END}"

az vm create \
  --admin-username $ADMIN_USERNAME \
  --custom-data $TMP_CLOUD_CONFIG_YAML \
  --generate-ssh-keys \
  --image $SOURCEIMAGE \
  --name $BASENAME \
  --nsg $NSGNAME \
  --os-disk-name "${BASENAME}OSDISK" \
  --os-disk-size-gb $DISKSIZEGB \
  --resource-group $RESOURCEGROUP_BUILD \
  --size $VMSIZE \
  --subnet $SUBNETNAME \
  --vnet-name $VNETNAME

# --generate-ssh-keys will use ~/.ssh/id_rsa if available and otherwise generate a new key
# the key will be removed from the build machine at the end of VM creation

# Remove temporary init file if it exists
rm $TMP_CLOUD_CONFIG_YAML 2> /dev/null

# Get public IP address for this machine. Piping to echo removes the quotemarks around the address
PUBLICIP=$(az vm list-ip-addresses --resource-group $RESOURCEGROUP_BUILD --name $BASENAME --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" | xargs echo)
echo -e "${BOLD}This process will take several hours to complete.${END}"
echo -e "  ${BOLD}You can monitor installation progress using... ${BLUE}ssh atiadmin@${PUBLICIP}${END}."
echo -e "  ${BOLD}Once logged in, check the installation progress with: ${BLUE}tail -f -n+1 /var/log/cloud-init-output.log${END}"