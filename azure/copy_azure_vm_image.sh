#! /bin/bash
SOURCE_IMAGE="ImageDSGComputeMachineVM-DataScienceBase-201811281323"
SOURCE_SUBSCRIPTION="Safe Haven Management Testing"
SOURCE_RESOURCE_GROUP="DataSafeHavenImages"
TARGET_SUBSCRIPTION="Data Study Group Testing"
TARGET_RESOURCE_GROUP="RG_DSG_LINUX"

# Document usage for this script
usage() {  
    echo "usage: $0 [-h] [-i source_image] [-r resource_group] [-n machine_name]"
    echo "  -h                 display help"
    echo "  -i source_image    specify source_image: for example 'ImageDSGComputeMachineVM-DataScienceBase-201811281323'"
    echo "  -r resource_group  specify target resource group: for example 'RG_DSG_LINUX'"
    echo "  -s subscription    specify target subscription: for example 'Data Study Group Testing'"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "h:i:r:n:" opt; do
    case $opt in
        h)
            usage
            ;;
        i)
            SOURCE_IMAGE=$OPTARG
            ;;
        r)
            TARGET_RESOURCE_GROUP=$OPTARG
            ;;
        s)
            TARGET_SUBSCRIPTION=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done


# Switch to management subscription and setup resource group if it does not already exist
az account set --subscription "$SOURCE_SUBSCRIPTION"

# Copy image to target subscription
az extension add --name image-copy-extension
az image copy \
    --source-object-name $SOURCE_IMAGE \
    --source-resource-group $SOURCE_RESOURCE_GROUP \
    --target-resource_group $TARGET_RESOURCE_GROUP \
    --target-subscription "$TARGET_SUBSCRIPTION" \
    --target-location uksouth