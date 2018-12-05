#! /bin/bash

# Options which are configurable at the command line
SOURCEIMAGE="Ubuntu"
RESOURCEGROUP="RG_SH_IMAGEGALLERY"
SUBSCRIPTION="" # must be provided

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# Other constants
MACHINENAME="ComputeVM"
LOCATION="westeurope" # have to build in West Europe in order to use Shared Image Gallery

# Document usage for this script
print_usage_and_exit() {
    echo "usage: $0 [-h] [-i source_image] [-n machine_name] [-r resource_group] -s subscription"
    echo "  -h                 display help"
    echo "  -i source_image    specify source_image: either 'Ubuntu' (default) 'UbuntuTorch' (as default but with Torch included) or 'DataScience'"
    echo "  -r resource_group  specify resource group - will be created if it does not already exist (defaults to 'RG_SH_IMAGEGALLERY')"
    echo "  -s subscription    specify subscription for storing the VM images [required]. (Test using 'Safe Haven Management Testing')"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "hi:r:s:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        i)
            SOURCEIMAGE=$OPTARG
            ;;
        r)
            RESOURCEGROUP=$OPTARG
            ;;
        s)
            SUBSCRIPTION=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done

# Check that a subscription has been provided
if [ "$SUBSCRIPTION" = "" ]; then
    echo -e "${RED}Subscription is a required argument!${END}"
    print_usage_and_exit
fi

# Switch subscription and setup resource group if it does not already exist
# - have to build in West Europe in order to use Shared Image Gallery
az account set --subscription "$SUBSCRIPTION"
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo -e "${BOLD}Creating resource group ${BLUE}$RESOURCEGROUP${END}"
    az group create --name $RESOURCEGROUP --location $LOCATION
fi


# Ensure required features for shared image galleries are enabled for this subscription
FEATURE="GalleryPreview"
NAMESPACE="Microsoft.Compute"
FEATURE_STATE="$(az feature show --namespace $NAMESPACE --name $FEATURE --query 'properties.state' | xargs)"
RESOURCE="galleries/images/versions"
RESOURCE_METADATA_QUERY="resourceTypes[?resourceType=='$RESOURCE']"
RESOURCE_METADATA="$(az provider show --namespace $NAMESPACE --query $RESOURCE_METADATA_QUERY)"

echo "Ensuring $FEATURE feature is registered and $RESOURCE resource is present in namespace $NAMESPACE (this may take some time)."
echo "Current $FEATURE feature state is $FEATURE_STATE."
if [ "$RESOURCE_METADATA" = "[]" ]; then
    echo "Resource $RESOURCE is not present."
else
    echo "Resource $RESOURCE is present."
fi

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

# Add an NSG group to deny inbound connections except Turing-based SSH
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name NSG_IMAGE_BUILD 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating NSG for image build: ${BLUE}NSG_IMAGE_BUILD${END}"
    az network nsg create --resource-group $RESOURCEGROUP --name NSG_IMAGE_BUILD
    az network nsg rule create \
        --resource-group $RESOURCEGROUP \
        --nsg-name NSG_IMAGE_BUILD \
        --direction Inbound \
        --name ManualConfigSSH \
        --description "Allow port 22 for management over ssh" \
        --source-address-prefixes 193.60.220.253 \
        --source-port-ranges "*" \
        --destination-address-prefixes "*" \
        --destination-port-ranges 22 \
        --protocol TCP \
        --priority 100
    az network nsg rule create \
        --resource-group $RESOURCEGROUP \
        --nsg-name NSG_IMAGE_BUILD \
        --direction Inbound \
        --name DenyAll \
        --description "Deny all" \
        --access "Deny" \
        --source-address-prefixes "*" \
        --source-port-ranges "*" \
        --destination-address-prefixes "*" \
        --destination-port-ranges "*" \
        --protocol "*" \
        --priority 3000
fi

# Select source image - either Ubuntu 18.04 or Microsoft Data Science (based on Ubuntu 16.04).
# If anything else is requested then print usage message and exit.
# If using the Data Science VM then the terms will be automatically accepted.
if [[ "$SOURCEIMAGE" = *"Ubuntu"* ]]; then
    if [ "$SOURCEIMAGE" = "UbuntuTorch" ]; then
        echo -e "${BOLD}Enabling ${BLUE}Torch ${BOLD}compilation${END}"
        # Make a temporary config file with the Torch lines uncommented
        TMP_CLOUD_CONFIG_PREFIX=$(mktemp)
        TMP_CLOUD_CONFIG_YAML=$(mktemp "${TMP_CLOUD_CONFIG_PREFIX}.yaml")
        rm $TMP_CLOUD_CONFIG_PREFIX
        sed "s/#IF_TORCH_ENABLED //" cloud-init-buildimage-ubuntu.yaml > $TMP_CLOUD_CONFIG_YAML
        MACHINENAME="${MACHINENAME}-UbuntuTorch1804Base"
        INITSCRIPT="$TMP_CLOUD_CONFIG_YAML"
    else
        MACHINENAME="${MACHINENAME}-Ubuntu1804Base"
        INITSCRIPT="cloud-init-buildimage-ubuntu.yaml"
    fi
    SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"
    DISKSIZEGB="40"
elif [ "$SOURCEIMAGE" = "DataScience" ]; then
    MACHINENAME="${MACHINENAME}-DataScienceBase"
    SOURCEIMAGE="microsoft-ads:linux-data-science-vm-ubuntu:linuxdsvmubuntubyol:18.08.00"
    INITSCRIPT="cloud-init-buildimage-datascience.yaml"
    DISKSIZEGB="60"
    echo -e "${BLUE}Auto-accepting licence terms for the Data Science VM${END}"
    az vm image accept-terms --urn $SOURCEIMAGE
else
    echo -e "${RED}Did not recognise image name: $SOURCEIMAGE!${END}"
    print_usage_and_exit
fi

# Append timestamp to allow unique naming
TIMESTAMP="$(date '+%Y%m%d%H%M')"
BASENAME="Generalized${MACHINENAME}-${TIMESTAMP}"

# Create the VM based off the selected source image
echo -e "${BOLD}Provisioning a new VM image in ${BLUE}$RESOURCEGROUP${END} ${BOLD}as part of ${BLUE}$SUBSCRIPTION${END}"
echo -e "${BOLD}  VM name: ${BLUE}$BASENAME${END}"
echo -e "${BOLD}  Base image: ${BLUE}$SOURCEIMAGE${END}"
STARTTIME=$(date +%s)
az vm create \
  --resource-group $RESOURCEGROUP \
  --name $BASENAME \
  --image $SOURCEIMAGE \
  --os-disk-size-gb $DISKSIZEGB \
  --custom-data $INITSCRIPT \
  --nsg NSG_IMAGE_BUILD \
  --size Standard_DS2_v2 \
  --admin-username atiadmin \
  --generate-ssh-keys # will use ~/.ssh/id_rsa if available and otherwise generate a new key
                      # the key will be removed from the build machine at the end of VM creation

# Remove temporary init file if it exists
rm $TMP_CLOUD_CONFIG_YAML 2> /dev/null

# Get public IP address for this machine. Piping to echo removes the quotemarks around the address
PUBLICIP=$(az vm list-ip-addresses --resource-group $RESOURCEGROUP --name $BASENAME --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" | xargs echo)
echo -e "${RED}This process will take several hours to complete.${END}"
echo -e "  ${BOLD}You can monitor installation progress using... ${BLUE}ssh atiadmin@${PUBLICIP}${END}."
echo -e "  ${BOLD}Once logged in, check the installation progress with: ${BLUE}tail -f -n+1 /var/log/cloud-init-output.log${END}"