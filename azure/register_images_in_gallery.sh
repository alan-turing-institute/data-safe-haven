#! /bin/bash

# Options which are configurable at the command line
MACHINENAME="" # either this or SOURCEIMAGE must be provided
SOURCEIMAGE="" # either this or MACHINENAME must be provided
RESOURCEGROUP="RG_SH_IMAGEGALLERY"
SUBSCRIPTION=""
VERSIONSUFFIX="00"

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# Other constants
SUPPORTEDIMAGES=("ComputeVM-DataScienceBase" "ComputeVM-Ubuntu1804Base")
GALLERYNAME="SIG_DSG_COMPUTE"
VERSIONMAJOR="0"
VERSIONMINOR="0"

# Document usage for this script
print_usage_and_exit() {
    echo "usage: $0 [-h] [-i source_image] [-n machine_name] [-s subscription] [-v version_suffix]"
    echo "  -h                  display help"
    echo "  -i source_image     specify an already existing image to add to the gallery."
    echo "  -n machine_name     specify a machine name to turn into an image. Ensure that the build script has completely finished before running this."
    echo "  -r resource_group   specify resource group - must match the one where the machine/image already exists (defaults to 'RG_DSG_IMAGEGALLERY')"
    echo "  -s subscription     specify subscription for storing the VM images [required]. (Test using 'Safe Haven Management Testing')"
    echo "  -v version_suffix   this is needed if we build more than one image in a day. Defaults to '00' and should follow the pattern 01, 02, 03 etc."
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "hi:n:r:s:v:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        i)
            SOURCEIMAGE=$OPTARG
            ;;
        n)
            MACHINENAME=$OPTARG
            ;;
        s)
            SUBSCRIPTION=$OPTARG
            ;;
        v)
            VERSIONSUFFIX=$OPTARG
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

# Switch subscription and check that resource group exists
az account set --subscription "$SUBSCRIPTION"
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo -e "${RED}Resource group ${BLUE}$RESOURCEGROUP${END} does not exist!${END}"
    print_usage_and_exit
fi

# Ensure image sharing is enabled from this subscription
SHARING_STATE="$(az feature show --namespace Microsoft.Compute --name UserImageSharing --query 'properties.state' | xargs)"
if [ "$SHARING_STATE" = "Registered" ]; then
    # Do nothing - feature already registered
    sleep 0
elif [ "$SHARING_STATE" = "NotRegistered" ]; then
    # Register feature
    echo -e "${BOLD}Registering ${BLUE}UserImageSharing${END} ${BOLD}for ${BLUE}$SUBSCRIPTION${END}"
    az feature register --namespace Microsoft.Compute --name "UserImageSharing" --subscription "$SUBSCRIPTION"
    az provider register --namespace Microsoft.Compute
else
    echo -e "${RED}UserImageSharing state could not be found. Try updating Azure CLI.${END}"
    exit 1
fi

# Create image gallery if it doesn't already exist
if [ "$(az sig list --resource-group $RESOURCEGROUP | grep 'name' | grep $GALLERYNAME)" = "" ]; then
    echo -e "${BOLD}Creating image gallery ${BLUE}$GALLERYNAME${END} ${BOLD}as part of ${BLUE}$RESOURCEGROUP${END}"
    az sig create --resource-group $RESOURCEGROUP --gallery-name "$GALLERYNAME"
fi

# Set up list of gallery images we want to support
for SUPPORTEDIMAGE in ${SUPPORTEDIMAGES[@]}; do
    IMAGETYPE=$(echo $SUPPORTEDIMAGE | cut -d'-' -f1)
    SKU=$(echo $SUPPORTEDIMAGE | cut -d'-' -f2)
    if [ "$(az sig image-definition show --resource-group $RESOURCEGROUP --gallery-name $GALLERYNAME --gallery-image-definition $SUPPORTEDIMAGE 2>&1 | grep 'not found')" != "" ]; then
        echo -e "${BOLD}Ensuring that ${BLUE}${SUPPORTEDIMAGE}${END} ${BOLD}is correctly registered in the image gallery${END}"
        az sig image-definition create \
            --resource-group $RESOURCEGROUP \
            --gallery-name $GALLERYNAME \
            --gallery-image-definition $SUPPORTEDIMAGE \
            --publisher Turing \
            --offer $IMAGETYPE \
            --sku $SKU \
            --os-type "Linux"
    fi
done

# Require exactly one image name or one machine name that must exist in this resource group
if [ "$MACHINENAME" = "" ] && [ "$SOURCEIMAGE" = "" ]; then
    echo -e "${RED}You must specify an image name (or a machine name that will be turned into an image) in order to add it to the gallery${END}"
    echo -e "${BOLD}Available machines are:${END}"
    az vm list --resource-group $RESOURCEGROUP --query "[].name" -o table
    echo -e "${BOLD}Available images are:${END}"
    az image list --resource-group RG_DSG_IMAGEGALLERY --query "[].name" -o table
    print_usage_and_exit
elif [ "$MACHINENAME" != "" ] && [ "$SOURCEIMAGE" != "" ]; then
    echo -e "${RED}You must specify EITHER an image name OR a machine name, not both${END}"
    print_usage_and_exit
elif [ "$MACHINENAME" != "" ]; then
    if [ "$(az vm show --resource-group $RESOURCEGROUP --name $MACHINENAME)" = "" ]; then
        echo -e "${RED}Could not find a machine called ${BLUE}${MACHINENAME}${RED} in resource group ${RESOURCEGROUP}${END}"
        echo -e "${BOLD}Available machines are:${END}"
        az vm list --resource-group $RESOURCEGROUP --query "[].name" -o table
        print_usage_and_exit
    else
        # Deallocate and generalize
        echo -e "${BOLD}Deallocating and generalizing VM: ${BLUE}${MACHINENAME}${END}"
        az vm deallocate --resource-group $RESOURCEGROUP --name $MACHINENAME
        az vm generalize --resource-group $RESOURCEGROUP --name $MACHINENAME
        # Create an image
        SOURCEIMAGE="Image$(echo $MACHINENAME | sed 's/Generalized//')"
        echo -e "${BOLD}Creating an image from VM: ${BLUE}${MACHINENAME}${END}"
        az image create --resource-group $RESOURCEGROUP --name $SOURCEIMAGE --source $MACHINENAME
        # echo "Residual artifacts of the build process (ie. anything starting with $MACHINENAME) can now be deleted from $RESOURCEGROUP."
    fi
fi

# By this point we've either been provided with an image name, or we've made a new image and we know its name
if [ "$(az image show --resource-group $RESOURCEGROUP --name $SOURCEIMAGE 2>&1 | grep 'not found')" != "" ]; then
    echo -e "${RED}Image ${BLUE}${SOURCEIMAGE}${RED} could not be found in resource group ${BLUE}${RESOURCEGROUP}${END}"
    echo -e "${BOLD}Available images are:${END}"
    az image list --resource-group RG_DSG_IMAGEGALLERY --query "[].name" -o table
    exit 1
fi

# Create the image as a new version of the appropriate existing registered version
echo -e "${BOLD}Trying to identify ${BLUE}$SOURCEIMAGE${END} ${BOLD}as a supported image...${END}"
for SUPPORTEDIMAGE in ${SUPPORTEDIMAGES[@]}; do
    if [[ "$SOURCEIMAGE" = *"$SUPPORTEDIMAGE"* ]]; then
        echo -e "${BOLD}Identified ${BLUE}${SOURCEIMAGE}${END} ${BOLD}as an instance of ${BLUE}${SUPPORTEDIMAGE}${END}"
        IMAGETYPE=$(echo $SUPPORTEDIMAGE | cut -d'-' -f1)
        SKU=$(echo $SUPPORTEDIMAGE | cut -d'-' -f2)
        RESOURCEID="$(az image show --resource-group $RESOURCEGROUP --name $SOURCEIMAGE --query 'id' | xargs)" # use xargs default echo to strip extraneous quotation marks
        IMAGEVERSION=${VERSIONMAJOR}.${VERSIONMINOR}.$(date '+%Y%m%d')${VERSIONSUFFIX}
        echo -e "${BOLD}Trying to replicate this image across 3 regions as version ${BLUE}${IMAGEVERSION}${END} ${BOLD}of ${BLUE}${SUPPORTEDIMAGE}${END}"
        echo -e "${RED}Please note, this may take more than 30 minutes to complete${END}"
        az sig image-version create \
            --resource-group $RESOURCEGROUP \
            --gallery-name $GALLERYNAME \
            --gallery-image-definition $SUPPORTEDIMAGE \
            --gallery-image-version "$IMAGEVERSION" \
            --target-regions "West Europe" "UK South" "UK West" \
            --managed-image $RESOURCEID
        echo "${BOLD}Result of replication...${END}"
        az sig image-version list --resource-group $RESOURCEGROUP --gallery-name $GALLERYNAME --gallery-image-definition $SUPPORTEDIMAGE
    fi
done