#! /bin/bash

# Load common constants and options
source ${BASH_SOURCE%/*}/configs/images.sh
source ${BASH_SOURCE%/*}/configs/text.sh

# Options which are configurable at the command line
SOURCEIMAGE="" # required
VERSIONOVERRIDE=""

# Other constants
SUPPORTEDIMAGES=("ComputeVM-Ubuntu1804Base" "ComputeVM-UbuntuTorch1804Base")
VERSIONMAJOR="0"
VERSIONMINOR="1"


# Document usage for this script
# ------------------------------
print_usage_and_exit() {
    echo "usage: $0 [-h] -n source_image [-s subscription] [-v version_override]"
    echo "  -h                           display help"
    echo "  -n source_image [required]   specify an already existing image to add to the gallery."
    echo "  -s subscription              specify subscription for storing the VM images. (defaults to '${IMAGES_SUBSCRIPTION}')"
    echo "  -v version_override          Override the automatically determined version number. Use with caution."
    exit 1
}


# Read command line arguments, overriding defaults where necessary
# ----------------------------------------------------------------
while getopts "hn:s:v:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        n)
            SOURCEIMAGE=$OPTARG
            ;;
        s)
            IMAGES_SUBSCRIPTION=$OPTARG
            ;;
        v)
            VERSIONOVERRIDE=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done


# Check that a subscription has been provided and switch to it
# ------------------------------------------------------------
if [ "$IMAGES_SUBSCRIPTION" = "" ]; then
    echo -e "${RED}Subscription is a required argument!${END}"
    print_usage_and_exit
fi
az account set --subscription "$IMAGES_SUBSCRIPTION"


# Check that resource group exists
# --------------------------------------------------------
if [ $(az group exists --name $RESOURCEGROUP_IMAGES) != "true" ]; then
    echo -e "${RED}Resource group ${BLUE}$RESOURCEGROUP_IMAGES${END} does not exist!${END}"
    print_usage_and_exit
fi

# Ensure required features for shared image galleries are enabled for this subscription
# -------------------------------------------------------------------------------------
ensure_image_galleries_enabled


# Setup gallery resource group if it does not already exist
# ---------------------------------------------------------
if [ $(az group exists --name $RESOURCEGROUP_GALLERY) != "true" ]; then
    echo -e "${BOLD}Creating resource group ${BLUE}$RESOURCEGROUP_GALLERY${END}"
    az group create --name $RESOURCEGROUP_GALLERY --location $IMAGES_LOCATION
fi


# Create image gallery if it doesn't already exist
# ------------------------------------------------
if [ "$(az sig list --resource-group $RESOURCEGROUP_GALLERY | grep 'name' | grep $IMAGES_GALLERY)" = "" ]; then
    echo -e "${BOLD}Creating image gallery ${BLUE}$IMAGES_GALLERY${END} ${BOLD}as part of ${BLUE}$RESOURCEGROUP_GALLERY${END}"
    az sig create --resource-group $RESOURCEGROUP_GALLERY --gallery-name "$IMAGES_GALLERY"
fi


# Set up list of gallery images we want to support
# ------------------------------------------------
for SUPPORTEDIMAGE in ${SUPPORTEDIMAGES[@]}; do
    IMAGE_TYPE=$(echo $SUPPORTEDIMAGE | cut -d'-' -f1)
    SKU=$(echo $SUPPORTEDIMAGE | cut -d'-' -f2)
    if [ "$(az sig image-definition show --resource-group $RESOURCEGROUP_GALLERY --gallery-name $IMAGES_GALLERY --gallery-image-definition $SUPPORTEDIMAGE 2>&1 | grep 'not found')" != "" ]; then
        echo -e "${BOLD}Ensuring that ${BLUE}${SUPPORTEDIMAGE}${END} ${BOLD}is correctly registered in the image gallery${END}"
        az sig image-definition create \
            --resource-group $RESOURCEGROUP_GALLERY \
            --gallery-name $IMAGES_GALLERY \
            --gallery-image-definition $SUPPORTEDIMAGE \
            --publisher Turing \
            --offer $IMAGE_TYPE \
            --sku $SKU \
            --os-type "Linux"
    fi
done


# Ensure that image exists in the image resource group
# ----------------------------------------------------
if [ "$(az image show --resource-group $RESOURCEGROUP_IMAGES --name $SOURCEIMAGE 2>&1 | grep 'not found')" != "" ]; then
    echo -e "${RED}Image ${BLUE}${SOURCEIMAGE}${RED} could not be found in resource group ${BLUE}${RESOURCEGROUP_IMAGES}${END}"
    echo -e "${BOLD}Available images are:${END}"
    az image list --resource-group ${RESOURCEGROUP_IMAGES} --query "[].name" -o table
    exit 1
fi


# Check which image definition to use
# -----------------------------------
echo -e "${BOLD}Checking whether ${BLUE}$SOURCEIMAGE${END} ${BOLD}is a supported image...${END}"
IMAGE_DEFINITION=""
for SUPPORTEDIMAGE in ${SUPPORTEDIMAGES[@]}; do
    if [[ "$SOURCEIMAGE" = *"$SUPPORTEDIMAGE"* ]]; then
        echo -e "${BOLD}Identified ${BLUE}${SOURCEIMAGE}${END} ${BOLD}as an instance of ${BLUE}${SUPPORTEDIMAGE}${END}"

        IMAGE_DEFINITION=$SUPPORTEDIMAGE
    fi
done
if [ "${IMAGE_DEFINITION}" = "" ]; then
    echo -e "${BLUE}${SOURCEIMAGE}${END} ${RED}could not be identified as a supported image${END}"
    print_usage_and_exit
fi


# Find the appropriate image version
# ----------------------------------
if [ "${VERSIONOVERRIDE}" = "" ]; then
    IMAGE_TYPE=$(echo $IMAGE_DEFINITION | cut -d'-' -f1)
    SKU=$(echo $IMAGE_DEFINITION | cut -d'-' -f2)
    # Determine lowest image version that has not already been used
    IMAGE_VERSION_BASE=${VERSIONMAJOR}.${VERSIONMINOR}.$(date '+%Y%m%d')
    EXISTINGIMAGES=$(az sig image-version list --resource-group $RESOURCEGROUP_GALLERY --gallery-name $IMAGES_GALLERY --gallery-image-definition $IMAGE_DEFINITION --query "[].name" -o tsv | grep $IMAGE_VERSION_BASE | sort)
    # Iterate through possible version suffices until finding one that has not been used
    if [ "$VERSIONSUFFIX" = "" ]; then
        for TESTVERSIONSUFFIX in $(seq -w 0 99); do
            IMAGE_VERSION=${IMAGE_VERSION_BASE}${TESTVERSIONSUFFIX}
            ALREADYUSED=0
            for EXISTINGIMAGE in $EXISTINGIMAGES; do
                if [ "$IMAGE_VERSION" = "$EXISTINGIMAGE" ]; then ALREADYUSED=1; fi
            done
            if [ $ALREADYUSED -eq 0 ]; then VERSIONSUFFIX=$TESTVERSIONSUFFIX; break; fi
        done
    fi
else
    echo -e "${BOLD}Overriding image version determination${END}"
    IMAGE_VERSION=$VERSIONOVERRIDE
fi


# Create the image as a new version of the appropriate existing registered version
# --------------------------------------------------------------------------------
echo -e "${BOLD}Preparing to replicate this image across 3 regions as version ${BLUE}${IMAGE_VERSION}${END} ${BOLD}of ${BLUE}${IMAGE_DEFINITION}${END}"
echo -e "${BOLD}Please note, this may take about 1 hour to complete${END}"
echo -e "${BOLD}Starting image replication at $(date)${END}"
STARTTIME=$(date +%s)
RESOURCEID="$(az image show --resource-group $RESOURCEGROUP_IMAGES --name $SOURCEIMAGE --query 'id' -o tsv 2> /dev/null)"

az sig image-version create \
    --resource-group $RESOURCEGROUP_GALLERY \
    --gallery-name $IMAGES_GALLERY \
    --gallery-image-definition $IMAGE_DEFINITION \
    --gallery-image-version "$IMAGE_VERSION" \
    --target-regions "West Europe" "UK South" "UK West" \
    --managed-image $RESOURCEID
echo -e "${BOLD}Result of replication...${END}"
az sig image-version list --resource-group $RESOURCEGROUP_GALLERY --gallery-name $IMAGES_GALLERY --gallery-image-definition $IMAGE_DEFINITION

# Final message
ELAPSED=$(date -u -r $(($(date +%s) - $STARTTIME)) +"%H:%M:%S") # OSX
echo -e "${BOLD}Image replication finished in $ELAPSED${END}"
