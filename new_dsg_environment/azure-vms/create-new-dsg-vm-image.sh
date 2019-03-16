#!/usr/bin/env bash

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# Options which are configurable at the command line
SUBSCRIPTION="" # must be provided
SOURCEIMAGE="Ubuntu"
VERSION=""
RESOURCEGROUP="RG_SH_IMAGEGALLERY"
USERNAME="atiadmin"

# Other constants
IMAGES_GALLERY="SIG_SH_COMPUTE"
VM_SIZE="Standard_DS2_v2"
LOCATION="westeurope" # have to build in West Europe in order to use Shared Image Gallery
NSGNAME="NSG_IMAGE_BUILD"

# Document usage for this script
print_usage_and_exit() {
    echo "usage: $0 [-h] -s subscription [-i source_image] [-x source_image_version] [-r resource_group] [-u user_name]"
    echo "  -s subscription [required]   specify subscription to use"
    echo "  -h                           display help"
    echo "  -i source_image              specify source_image: either 'Ubuntu' (default) 'UbuntuTorch' (as default but with Torch included) or 'DataScience' (the Microsoft Azure DSVM) or 'DSG' (the current base image for Data Study Groups)"
    echo "  -x source_image_version      specify the version of the source image to use (defaults to prompting to select from available versions)"
    echo "  -r resource_group            specify resource group for deploying the VM image - will be created if it does not already exist (defaults to '${RESOURCEGROUP}')"
    echo "  -u user_name                 specify a username for the admin account (defaults to '${USERNAME}')"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "g:hi:x:r:u:s:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        i)
            SOURCEIMAGE=$OPTARG
            ;;
        x)
            VERSION=$OPTARG
            ;;
        r)
            RESOURCEGROUP=$OPTARG
            ;;
        u)
            USERNAME=$OPTARG
            ;;
        s)
            SUBSCRIPTION=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done

# Set default machine name
if [ "$MACHINENAME" = "" ]; then
    MACHINENAME="ComputeVM-DSGBase"
fi

# Check that a source subscription has been provided
if [ "$SUBSCRIPTION" = "" ]; then
    echo -e "${RED}Subscription is a required argument!${END}"
    print_usage_and_exit
fi

# Look up specified image definition
az account set --subscription "$SUBSCRIPTION"
if [ "$SOURCEIMAGE" = "Ubuntu" ]; then
    IMAGE_DEFINITION="ComputeVM-Ubuntu1804Base"
elif [ "$SOURCEIMAGE" = "UbuntuTorch" ]; then
    IMAGE_DEFINITION="ComputeVM-UbuntuTorch1804Base"
elif [ "$SOURCEIMAGE" = "DataScience" ]; then
    IMAGE_DEFINITION="ComputeVM-DataScienceBase"
elif [ "$SOURCEIMAGE" = "DSG" ]; then
    IMAGE_DEFINITION="ComputeVM-DsgBase"
else
    echo -e "${RED}Could not interpret ${BLUE}${SOURCEIMAGE}${END} as an image type${END}"
    print_usage_and_exit
fi

# Prompt user to select version if not already supplied
if [ "$VERSION" = "" ]; then
    # List available versions and set the last one in the list as default
    echo -e "${BOLD}Found the following versions of ${BLUE}$IMAGE_DEFINITION${END}"
    VERSIONS=$(az sig image-version list \
                --resource-group $RESOURCEGROUP \
                --gallery-name $IMAGES_GALLERY \
                --gallery-image-definition $IMAGE_DEFINITION \
                --query "[].name" -o table)
    echo -e "$VERSIONS"
    DEFAULT_VERSION=$(echo -e "$VERSIONS" | tail -n1)
    echo -e "${BOLD}Please type the version you would like to use, followed by [ENTER]. To accept the default ${BLUE}$DEFAULT_VERSION${END} ${BOLD}simply press [ENTER]${END}"
    read VERSION
    if [ "$VERSION" = "" ]; then VERSION=$DEFAULT_VERSION; fi
fi

# Check that this is a valid version and then get the image ID
echo -e "${BOLD}Finding ID for image ${BLUE}${IMAGE_DEFINITION}${END} version ${BLUE}${VERSION}${END}${BOLD}...${END}"
if [ "$(az sig image-version show --resource-group $RESOURCEGROUP --gallery-name $IMAGES_GALLERY --gallery-image-definition $IMAGE_DEFINITION --gallery-image-version $VERSION 2>&1 | grep 'not found')" != "" ]; then
    echo -e "${RED}Version $VERSION could not be found.${END}"
    print_usage_and_exit
fi
IMAGE_ID=$(az sig image-version show --resource-group $RESOURCEGROUP --gallery-name $IMAGES_GALLERY --gallery-image-definition $IMAGE_DEFINITION --gallery-image-version $VERSION --query "id" | xargs)

# Switch subscription and setup resource groups if they do not already exist
# --------------------------------------------------------------------------
az account set --subscription "$SUBSCRIPTION"
if [ "$(az group exists --name $RESOURCEGROUP)" != "true" ]; then
    echo -e "${BOLD}Creating resource group ${BLUE}$RESOURCEGROUP${END} ${BOLD}in ${BLUE}$SUBSCRIPTIONTARGET${END}"
    az group create --name $RESOURCEGROUP --location $LOCATION
fi

# If using the Data Science VM then the terms must be added before creating the VM
PLANDETAILS=""
if [[ "$SOURCEIMAGE" == *"DataScienceBase"* ]]; then
    PLANDETAILS="--plan-name linuxdsvmubuntubyol --plan-publisher microsoft-ads --plan-product linux-data-science-vm-ubuntu"
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
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSGNAME 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating NSG for image build: ${BLUE}$NSGNAME${END}"
    az network nsg create --resource-group $RESOURCEGROUP --name $NSGNAME
    az network nsg rule create \
        --resource-group $RESOURCEGROUP \
        --nsg-name $NSGNAME \
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
        --nsg-name $NSGNAME \
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

# Create the VM based off the selected source image
# Append timestamp to allow unique naming
DISKSIZEGB=60
BASENAME="Generalized${MACHINENAME}-$(date '+%Y%m%d%H%M')"
echo -e "${BOLD}Provisioning a new VM image in ${BLUE}$RESOURCEGROUP${END} ${BOLD}as part of ${BLUE}$SUBSCRIPTION${END}"
echo -e "${BOLD}  VM name: ${BLUE}$BASENAME${END}"
echo -e "${BOLD}  Base image: ${BLUE}$SOURCEIMAGE${END} ($IMAGE_ID)"
STARTTIME=$(date +%s)

az vm create \
  --resource-group $RESOURCEGROUP \
  --name $BASENAME \
  --image $IMAGE_ID \
  --os-disk-size-gb $DISKSIZEGB \
  --nsg $NSGNAME \
  --size $VM_SIZE \
  --admin-username $USERNAME \
  --generate-ssh-keys

