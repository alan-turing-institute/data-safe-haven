#! /bin/bash

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# Options which are configurable at the command line
SUBSCRIPTION_COMPUTE="" # must be provided
SUBSCRIPTION_MIRROR="" # must be provided
RESOURCE_GROUP_COMPUTE="RG_DSG_VNET"
RESOURCE_GROUP_MIRROR="RG_SH_PKG_MIRRORS"
VNET_NAME_COMPUTE="DSG_DSGROUPTEST_VNet1"
VNET_NAME_MIRROR="VNET_SH_PKG_MIRRORS"


# Document usage for this script
# ------------------------------
print_usage_and_exit() {
    echo "usage: $0 [-h] -s subscription_compute -t subscription_mirror [-g resource_group_compute] [-h resource_group_mirror] [-n vnet_name_compute] [-m vnet_name_mirror]"
    echo "  -h                                   display help"
    echo "  -s subscription_compute [required]   specify subscription where the compute VNet is deployed. (typically this will be 'Data Study Group Testing')"
    echo "  -t subscription_mirror [required]    specify subscription where the mirror VNet is deployed. (typically this will be 'Safe Haven Management Testing')"
    echo "  -c resource_group_compute            specify resource group where the compute VNet is deployed (defaults to '${RESOURCE_GROUP_COMPUTE}')"
    echo "  -m resource_group_mirror             specify resource group where the mirror VNet is deployed (defaults to '${RESOURCE_GROUP_MIRROR}')"
    echo "  -v vnet_name_compute                 specify name of the compute VNet (defaults to '${VNET_NAME_COMPUTE}')"
    echo "  -w vnet_name_mirror                  specify name of the mirror VNet (defaults to '${VNET_NAME_MIRROR}')"
    exit 1
}


# Read command line arguments, overriding defaults where necessary
# ----------------------------------------------------------------
while getopts "hs:t:c:m:v:w:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        s)
            SUBSCRIPTION_COMPUTE=$OPTARG
            ;;
        t)
            SUBSCRIPTION_MIRROR=$OPTARG
            ;;
        c)
            RESOURCE_GROUP_COMPUTE=$OPTARG
            ;;
        m)
            RESOURCE_GROUP_MIRROR=$OPTARG
            ;;
        v)
            VNET_NAME_COMPUTE=$OPTARG
            ;;
        w)
            VNET_NAME_MIRROR=$OPTARG
            ;;
        \?)
            print_usage_and_exit
            ;;
    esac
done

# Check that subscriptions have been provided
# -------------------------------------------
if [ "$SUBSCRIPTION_COMPUTE" = "" ]; then
    echo -e "${RED}Compute subscription is a required argument!${END}"
    print_usage_and_exit
fi
if [ "$SUBSCRIPTION_MIRROR" = "" ]; then
    echo -e "${RED}Mirror subscription is a required argument!${END}"
    print_usage_and_exit
fi

# Get VNet IDs
COMPUTE_VNET_ID=$(az network vnet show --resource-group $RESOURCE_GROUP_COMPUTE --name $VNET_NAME_COMPUTE --subscription "$SUBSCRIPTION_COMPUTE" --query id --out tsv)
MIRROR_VNET_ID=$(az network vnet show --resource-group $RESOURCE_GROUP_MIRROR --name $VNET_NAME_MIRROR --subscription "$SUBSCRIPTION_MIRROR" --query id --out tsv)

# Create peerings
echo -e "${BOLD}Peering ${BLUE}$VNET_NAME_COMPUTE${END}${BOLD} to ${BLUE}$VNET_NAME_MIRROR${END}"
az account set --subscription "$SUBSCRIPTION_COMPUTE"
az network vnet peering create --name PEER_${VNET_NAME_COMPUTE}_TO_${VNET_NAME_MIRROR} \
                               --resource-group $RESOURCE_GROUP_COMPUTE \
                               --vnet-name $VNET_NAME_COMPUTE \
                               --remote-vnet $MIRROR_VNET_ID \
                               --allow-vnet-access

echo -e "${BOLD}Peering ${BLUE}$VNET_NAME_MIRROR${END}${BOLD} to ${BLUE}$VNET_NAME_COMPUTE${END}"
az account set --subscription "$SUBSCRIPTION_MIRROR"
az network vnet peering create --name PEER_${VNET_NAME_MIRROR}_TO_${VNET_NAME_COMPUTE} \
                               --resource-group $RESOURCE_GROUP_MIRROR \
                               --vnet-name $VNET_NAME_MIRROR \
                               --remote-vnet $COMPUTE_VNET_ID \
                               --allow-vnet-access
