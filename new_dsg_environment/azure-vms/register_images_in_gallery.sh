#! /bin/bash

# Options which are configurable at the command line
MACHINENAME="" # either this or SOURCEIMAGE must be provided
SOURCEIMAGE="" # either this or MACHINENAME must be provided
RESOURCEGROUP="RG_SH_IMAGEGALLERY"
SUBSCRIPTION=""
VERSIONSUFFIX=""

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# Other constants
SUPPORTEDIMAGES=("ComputeVM-DataScienceBase" "ComputeVM-Ubuntu1804Base" "ComputeVM-UbuntuTorch1804Base" "ComputeVM-DsgBase")
GALLERYNAME="SIG_SH_COMPUTE" # must be unique within this subscription
VERSIONMAJOR="0"
VERSIONMINOR="0"

# Document usage for this script
print_usage_and_exit() {
    echo "usage: $0 [-h] [-i source_image] [-n machine_name] [-s subscription] [-v version_suffix]"
    echo "  -h                  display help"
    echo "  -i source_image     specify an already existing image to add to the gallery."
    echo "  -n machine_name     specify a machine name to turn into an image. Ensure that the build script has completely finished before running this."
    echo "  -r resource_group   specify resource group - must match the one where the machine/image already exists (defaults to 'RG_SH_IMAGEGALLERY')"
    echo "  -s subscription     specify subscription for storing the VM images [required]. (Test using 'Safe Haven Management Testing')"
    echo "  -v version_suffix   this is needed if we build more than one image in a day. Defaults to next unused number. Must follow the pattern 01, 02, 03 etc."
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
        r)
            RESOURCEGROUP=$OPTARG
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
        # Determine lowest image version that has not already been used
        IMAGEVERSIONBASE=${VERSIONMAJOR}.${VERSIONMINOR}.$(date '+%Y%m%d')
        EXISTINGIMAGES=$(az sig image-version list --resource-group $RESOURCEGROUP --gallery-name $GALLERYNAME --gallery-image-definition $SUPPORTEDIMAGE --query "[].name" -o tsv | grep $IMAGEVERSIONBASE | sort)
        # Iterate through possible version suffices until finding one that has not been used
        if [ "$VERSIONSUFFIX" = "" ]; then
            for TESTVERSIONSUFFIX in $(seq -w 0 99); do
                IMAGEVERSION=${IMAGEVERSIONBASE}${TESTVERSIONSUFFIX}
                ALREADYUSED=0
                for EXISTINGIMAGE in $EXISTINGIMAGES; do
                    if [ "$IMAGEVERSION" = "$EXISTINGIMAGE" ]; then ALREADYUSED=1; fi
                done
                if [ $ALREADYUSED -eq 0 ]; then VERSIONSUFFIX=$TESTVERSIONSUFFIX; break; fi
            done
        fi
        echo -e "${BOLD}Preparing to replicate this image across 3 regions as version ${BLUE}${IMAGEVERSION}${END} ${BOLD}of ${BLUE}${SUPPORTEDIMAGE}${END}"
        echo -e "${RED}Please note, this may take more than 30 minutes to complete${END}"
        az sig image-version create \
            --resource-group $RESOURCEGROUP \
            --gallery-name $GALLERYNAME \
            --gallery-image-definition $SUPPORTEDIMAGE \
            --gallery-image-version "$IMAGEVERSION" \
            --target-regions "West Europe" "UK South" "UK West" \
            --managed-image $RESOURCEID
        echo -e "${BOLD}Result of replication...${END}"
        az sig image-version list --resource-group $RESOURCEGROUP --gallery-name $GALLERYNAME --gallery-image-definition $SUPPORTEDIMAGE
    fi
done