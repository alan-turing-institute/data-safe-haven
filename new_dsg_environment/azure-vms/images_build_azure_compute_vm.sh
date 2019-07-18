#! /bin/bash

# Load common constants and options
source ${BASH_SOURCE%/*}/configs/images.sh
source ${BASH_SOURCE%/*}/configs/text.sh

# Other constants
SOURCEIMAGE="Ubuntu"

# Document usage for this script
print_usage_and_exit() {
    echo "usage: $0 [-h] [-s subscription] [-r resource_group] [-z vm_size]"
    echo "  -h                           display help"
    echo "  -s subscription              specify subscription for building the VM. (defaults to '${SUBSCRIPTION}')"
    echo "  -r resource_group            specify resource group - will be created if it does not already exist (defaults to '${RESOURCEGROUP_BUILD}')"
    echo "  -z vm_size                   size of the VM to use for build (defaults to '${BUILD_VMSIZE}')"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "hr:s:z:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        r)
            RESOURCEGROUP_BUILD=$OPTARG
            ;;
        s)
            SUBSCRIPTION=$OPTARG
            ;;
        z)
            BUILD_VMSIZE=$OPTARG
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

# Select source image - currently only Ubuntu 18.04 is supported
# If anything else is requested then print usage message and exit.
TMP_CLOUD_CONFIG_YAML="$(mktemp).yaml"
if [ "$SOURCEIMAGE" = "Ubuntu" ]; then
    SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"
    BUILD_MACHINE_NAME="${BUILD_MACHINE_NAME}-Ubuntu1804Base"
    cp cloud-init-buildimage-ubuntu.yaml $TMP_CLOUD_CONFIG_YAML
else
    echo -e "${RED}Did not recognise source image name: $SOURCEIMAGE. We only support building on top of Ubuntu.${END}"
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
ensure_image_galleries_enabled

# Create a VNet for the deployment
# --------------------------------
if [ "$(az network vnet list --resource-group $RESOURCEGROUP_NETWORK | grep $BUILD_VNET_NAME 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating VNet for image building: ${BLUE}$BUILD_VNET_NAME${END}"
    az network vnet create --resource-group $RESOURCEGROUP_NETWORK --name $BUILD_VNET_NAME --address-prefixes $BUILD_IP_RANGE
fi

# Create a subnet for the deployment
# ----------------------------------
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP_NETWORK --vnet-name $BUILD_VNET_NAME | grep $BUILD_SUBNET_NAME 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating subnet for image building: ${BLUE}$BUILD_SUBNET_NAME${END}"
    az network vnet subnet create --name $BUILD_SUBNET_NAME --resource-group $RESOURCEGROUP_NETWORK --vnet-name $BUILD_VNET_NAME --address-prefixes $BUILD_IP_RANGE
fi
SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCEGROUP_NETWORK --vnet $BUILD_VNET_NAME --name $BUILD_SUBNET_NAME --query "id" -o tsv)

# Add an NSG group to deny inbound connections except Turing-based SSH
# --------------------------------------------------------------------
if [ "$(az network nsg show --resource-group $RESOURCEGROUP_NETWORK --name $BUILD_NSG_NAME 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating NSG for image build: ${BLUE}$BUILD_NSG_NAME${END}"
    az network nsg create --resource-group $RESOURCEGROUP_NETWORK --name $BUILD_NSG_NAME
    az network nsg rule create \
        --description "Allow port 22 for management over ssh" \
        --destination-address-prefixes "*" \
        --destination-port-ranges 22 \
        --direction Inbound \
        --name TuringSSH \
        --nsg-name $BUILD_NSG_NAME \
        --priority 1000 \
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
        --nsg-name $BUILD_NSG_NAME \
        --priority 3000 \
        --protocol "*" \
        --resource-group $RESOURCEGROUP_NETWORK \
        --source-address-prefixes "*" \
        --source-port-ranges "*"
fi
NSG_ID=$(az network nsg show --resource-group $RESOURCEGROUP_NETWORK --name $BUILD_NSG_NAME --query "id" -o tsv)


# Append timestamp to allow unique naming
TIMESTAMP="$(date '+%Y%m%d%H%M')"
BASENAME="Candidate${BUILD_MACHINE_NAME}-${TIMESTAMP}"

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
  --admin-username $BUILD_ADMIN_USERNAME \
  --custom-data $TMP_CLOUD_CONFIG_YAML \
  --generate-ssh-keys \
  --image $SOURCEIMAGE \
  --name $BASENAME \
  --nsg $NSG_ID \
  --os-disk-name "${BASENAME}OSDISK" \
  --os-disk-size-gb $BUILD_DISKSIZEGB \
  --resource-group $RESOURCEGROUP_BUILD \
  --size $BUILD_VMSIZE \
  --subnet $SUBNET_ID

# --generate-ssh-keys will use ~/.ssh/id_rsa if available and otherwise generate a new key
# the key will be removed from the build machine at the end of VM creation

# Remove temporary init file if it exists
rm $TMP_CLOUD_CONFIG_YAML 2> /dev/null

# Get public IP address for this machine. Piping to echo removes the quotemarks around the address
PUBLICIP=$(az vm list-ip-addresses --resource-group $RESOURCEGROUP_BUILD --name $BASENAME --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" | xargs echo)
echo -e "${BOLD}This process will take several hours to complete.${END}"
echo -e "  ${BOLD}You can monitor installation progress using... ${BLUE}ssh ${BUILD_ADMIN_USERNAME}@${PUBLICIP}${END}."
echo -e "  ${BOLD}Once logged in, check the installation progress with: ${BLUE}tail -f -n+1 /var/log/cloud-init-output.log${END}"