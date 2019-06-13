#! /bin/bash

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# Options which are configurable at the command line
RESOURCEGROUP="RG_SHM_PKG_MIRRORS"
SUBSCRIPTION="" # must be provided
MIRROR_TYPE="" # must be provided
TIER="2"

# Other constants
MACHINENAME_PREFIX_EXTERNAL="ExternalMirror"
VALID_MIRROR_TYPES="'PyPI', 'CRAN'"


# Document usage for this script
# ------------------------------
print_usage_and_exit() {
    echo "usage: $0 [-h] -s subscription [-i vnet_ip] [-k keyvault_name] [-r resource_group] [-t tier]"
    echo "  -h                           display help"
    echo "  -s subscription [required]   specify subscription where the mirror servers should be deployed. (Test using 'Safe Haven Management Testing')"
    echo "  -m mirror_type [required]    specify which type of mirror to remove (options are ${VALID_MIRROR_TYPES})"
    echo "  -r resource_group            specify resource group - will be created if it does not already exist (defaults to '${RESOURCEGROUP}')"
    echo "  -t tier                      specify which tier these mirrors will belong to, either '2' or '3' (defaults to '${TIER}')"
    exit 1
}


# Read command line arguments, overriding defaults where necessary
# ----------------------------------------------------------------
while getopts "hm:r:s:t:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        m)
            MIRROR_TYPE=$OPTARG
            ;;
        r)
            RESOURCEGROUP=$OPTARG
            ;;
        s)
            SUBSCRIPTION=$OPTARG
            ;;
        t)
            TIER=$OPTARG
            ;;
        \?)
            print_usage_and_exit
            ;;
    esac
done


# Check that a subscription has been provided and switch to it
# ------------------------------------------------------------
if [ "$SUBSCRIPTION" = "" ]; then
    echo -e "${RED}Subscription is a required argument!${END}"
    print_usage_and_exit
fi
az account set --subscription "$SUBSCRIPTION"


# Check that a valid mirror type has been provided
# ------------------------------------------
if [ "$MIRROR_TYPE" != "PyPI" ] && [ "$MIRROR_TYPE" != "CRAN" ]; then
    echo -e "${RED}Mirror type ${BLUE}$MIRROR_TYPE${RED} was not recognised. Valid types are: $VALID_MIRROR_TYPES${END}"
    print_usage_and_exit
fi


# Check that Tier is either 2 or 3
# --------------------------------
if [ "$TIER" != "2" ] && [ "$TIER" != "3" ]; then
    echo -e "${RED}Tier must be either '2' or '3'${END}"
    print_usage_and_exit
fi


# Check that resource group exists
# --------------------------------
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo -e "${RED}Resource group ${BLUE}$RESOURCEGROUP${RED} does not exist!${END}"
    print_usage_and_exit
fi


# Set machine names to remove
# ---------------------------
MACHINENAME_EXTERNAL="Tier${TIER}${MACHINENAME_PREFIX_EXTERNAL}${MIRROR_TYPE}"
MACHINENAME_INTERNAL="$(echo $MACHINENAME_EXTERNAL | sed 's/External/Internal/')"


# Remove external and internal mirrors
# ------------------------------------
if [ "$(az vm show --resource-group $RESOURCEGROUP --name $MACHINENAME_EXTERNAL 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}VM ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} does not exist in ${BLUE}$RESOURCEGROUP${END}"
else
    echo -e "${BOLD}Removing ${BLUE}Tier-$TIER $MIRROR_TYPE${END}${BOLD} mirrors from ${BLUE}$RESOURCEGROUP${END}"

    for MACHINENAME in $MACHINENAME_EXTERNAL $MACHINENAME_INTERNAL; do
        echo -e "${BOLD}Working on ${BLUE}${MACHINENAME}${END}"
        echo -e "${BOLD}... virtual machine: ${BLUE}${MACHINENAME}${END}"
        az vm delete --yes --resource-group $RESOURCEGROUP --name $MACHINENAME
        echo -e "${BOLD}... OS disk: ${BLUE}${MACHINENAME}_OSDISK${END}"
        az disk delete --yes --resource-group $RESOURCEGROUP --name "${MACHINENAME}_OSDISK"
        echo -e "${BOLD}... data disk: ${BLUE}${MACHINENAME}_DATADISK${END}"
        az disk delete --yes --resource-group $RESOURCEGROUP --name "${MACHINENAME}_DATADISK"
        echo -e "${BOLD}... network card: ${BLUE}${MACHINENAME}VMNic${END}"
        az network nic delete --resource-group $RESOURCEGROUP --name "${MACHINENAME}VMNic"
    done
fi
