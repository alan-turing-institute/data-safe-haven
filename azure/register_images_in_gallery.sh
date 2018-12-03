#! /bin/bash

# Constants for colourised output
RED="\033[0;31m"
BLUE="\033[0;34m"
END="\033[0m"

# Set default names
SUPPORTEDIMAGES=("ComputeVM-DataScienceBase" "ComputeVM-Ubuntu1804Base")
SUBSCRIPTION="Safe Haven Management Testing"
RESOURCEGROUP="RG_DSG_IMAGEGALLERY"
GALLERYNAME="SIG_DSG_COMPUTE"
MACHINENAME=""
SOURCEIMAGE=""
VERSIONMAJOR="0"
VERSIONMINOR="0"
VERSIONSUFFIX="00"

# Document usage for this script
usage() {
    echo "usage: $0 [-h] [-i source_image] [-n machine_name] [-v version_suffix]"
    echo "  -h                  display help"
    echo "  -i source_image     specify an already existing image to add to the gallery."
    echo "  -n machine_name     specify a machine name to turn into an image. Ensure that the build script has completely finished before running this."
    echo "  -v version_suffix   this is needed if we build more than one image in a day. Defaults to '00' and should follow the pattern 01, 02, 03 etc."
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "hi:r:n:v:" opt; do
    case $opt in
        h)
            usage
            ;;
        n)
            MACHINENAME=$OPTARG
            ;;
        i)
            SOURCEIMAGE=$OPTARG
            ;;
        v)
            VERSIONSUFFIX=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done

# Switch subscription and setup resource group if it does not already exist
# - have to use West Europe in order to use Shared Image Gallery
az account set --subscription "$SUBSCRIPTION"
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo "Creating resource group $RESOURCEGROUP"
    az group create --name $RESOURCEGROUP --location westeurope
fi

# Create image gallery if it doesn't already exist
if [ "$(az sig list --resource-group $RESOURCEGROUP | grep 'name' | grep $GALLERYNAME)" = "" ]; then
    echo -e "Creating image gallery ${BLUE}$GALLERYNAME${END} as part of ${BLUE}$RESOURCEGROUP${END}"
    az sig create --resource-group $RESOURCEGROUP --gallery-name "$GALLERYNAME"
fi

# Set up list of gallery images we want to support
for SUPPORTEDIMAGE in ${SUPPORTEDIMAGES[@]}; do
    IMAGETYPE=$(echo $SUPPORTEDIMAGE | cut -d'-' -f1)
    SKU=$(echo $SUPPORTEDIMAGE | cut -d'-' -f2)
    if [ "$(az sig image-definition show --resource-group $RESOURCEGROUP --gallery-name $GALLERYNAME --gallery-image-definition $SUPPORTEDIMAGE 2>&1 | grep 'not found')" != "" ]; then
        echo -e "Ensuring that ${BLUE}$SUPPORTEDIMAGE${END} is correctly registered in the image gallery"
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
    usage
elif [ "$MACHINENAME" != "" ] && [ "$SOURCEIMAGE" != "" ]; then
    echo -e "${RED}You must specify EITHER an image name OR a machine name, not both${END}"
    usage
elif [ "$MACHINENAME" != "" ]; then
    if [ "$(az vm show --resource-group $RESOURCEGROUP --name $MACHINENAME)" = "" ]; then
        echo -e "${RED}Could not find a machine called ${BLUE}$MACHINENAME${RED} in resource group $RESOURCEGROUP${END}"
        usage
    else
        # Deallocate and generalize
        echo -e "Deallocating and generalizing VM: ${BLUE}${MACHINENAME}${END}"
        az vm deallocate --resource-group $RESOURCEGROUP --name $MACHINENAME
        az vm generalize --resource-group $RESOURCEGROUP --name $MACHINENAME
        # Create an image
        SOURCEIMAGE="Image$(echo $MACHINENAME | sed 's/Generalized//')"
        echo -e "Creating an image from VM: ${BLUE}${MACHINENAME}${END}"
        az image create --resource-group $RESOURCEGROUP --name $SOURCEIMAGE --source $MACHINENAME
    fi
fi

# By this point we've either been provided with an image name, or we've made a new image and we know its name
if [ "$(az image show --resource-group $RESOURCEGROUP --name $SOURCEIMAGE 2>&1 | grep 'not found')" != "" ]; then
    echo -e "${RED}Image ${BLUE}${SOURCEIMAGE}${RED} could not be found in resource group ${BLUE}${RESOURCEGROUP}${END}"
    exit 1
fi

# Create the image as a new version of the appropriate existing registered version
echo -e "Trying to identify ${BLUE}$SOURCEIMAGE${END} as a supported image..."
for SUPPORTEDIMAGE in ${SUPPORTEDIMAGES[@]}; do
    if [[ "$SOURCEIMAGE" = *"$SUPPORTEDIMAGE"* ]]; then
        echo -e "Identified ${BLUE}$SOURCEIMAGE${END} as an instance of ${BLUE}$SUPPORTEDIMAGE${END}"
        IMAGETYPE=$(echo $SUPPORTEDIMAGE | cut -d'-' -f1)
        SKU=$(echo $SUPPORTEDIMAGE | cut -d'-' -f2)
        RESOURCEID="$(az image show --resource-group $RESOURCEGROUP --name $SOURCEIMAGE --query 'id' | xargs)" # use xargs default echo to strip extraneous quotation marks
        IMAGEVERSION=${VERSIONMAJOR}.${VERSIONMINOR}.$(date '+%Y%m%d')${VERSIONSUFFIX}
        echo -e "Trying to replicate this image across 3 regions as version ${BLUE}$IMAGEVERSION${END} of ${BLUE}$SUPPORTEDIMAGE${END}"
        echo -e "${RED}Please note, this may take more than 30 minutes to complete${END}"
        az sig image-version create \
            --resource-group $RESOURCEGROUP \
            --gallery-name $GALLERYNAME \
            --gallery-image-definition $SUPPORTEDIMAGE \
            --gallery-image-version "$IMAGEVERSION" \
            --target-regions "West Europe" "UK South" "UK West" \
            --managed-image $RESOURCEID
        echo "${BLUE}Result of replication...${END}"
        az sig image-version list --resource-group $RESOURCEGROUP --gallery-name $GALLERYNAME --gallery-image-definition $SUPPORTEDIMAGE
    fi
done