#! /bin/bash

# Options which are configurable at the command line
SUBSCRIPTION="Safe Haven Management Testing"
RESOURCEGROUP="RG_DSG_IMAGEGALLERY"
SOURCEIMAGE="Ubuntu"

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;34m"
END="\033[0m"

# Other constants
MACHINENAME="ComputeVM"
LOCATION="westeurope" # have to build in West Europe in order to use Shared Image Gallery

# Document usage for this script
usage() {
    echo "usage: $0 [-h] [-i source_image] [-n machine_name] [-r resource_group] [-s subscription]"
    echo "  -h                 display help"
    echo "  -i source_image    specify source_image: either 'Ubuntu' (default) or 'DataScience'"
    echo "  -r resource_group  specify resource group - will be created if it does not already exist (defaults to 'RG_DSG_IMAGEGALLERY')"
    echo "  -s subscription    specify subscription for storing the VM images (defaults to 'Safe Haven Management Testing')"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "hi:r:n:" opt; do
    case $opt in
        h)
            usage
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

# Switch subscription and setup resource group if it does not already exist
# - have to build in West Europe in order to use Shared Image Gallery
az account set --subscription "$SUBSCRIPTION"
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo "Creating resource group ${BLUE}$RESOURCEGROUP${END}"
    az group create --name $RESOURCEGROUP --location $LOCATION
fi

# Enable image sharing from this subscription
if [ "$(az provider show --namespace Microsoft.Compute -o table | grep "Registered")" = "" ]; then
    echo "Registering ${BLUE}UserImageSharing${END} for ${BLUE}$SUBSCRIPTION${END}"
    az feature register --namespace Microsoft.Compute --name "UserImageSharing" --subscription "$SUBSCRIPTION"
    az provider register --namespace Microsoft.Compute
fi

# Select source image - either Ubuntu 18.04 or Microsoft Data Science (based on Ubuntu 16.04). Exit, printing usage, if anything else is requested.
# If using the Data Science VM then the terms will be automatically accepted
if [ "$SOURCEIMAGE" == "Ubuntu" ]; then
    MACHINENAME="${MACHINENAME}-Ubuntu1804Base"
    SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"
    INITSCRIPT="cloud-init-buildimage-ubuntu.yaml"
    DISKSIZEGB="40"
    PLANDETAILS=""
elif [ "$SOURCEIMAGE" == "DataScience" ]; then
    MACHINENAME="${MACHINENAME}-DataScienceBase"
    SOURCEIMAGE="microsoft-ads:linux-data-science-vm-ubuntu:linuxdsvmubuntubyol:18.08.00"
    INITSCRIPT="cloud-init-buildimage-datascience.yaml"
    DISKSIZEGB="60"
    PLANDETAILS="--plan-name linuxdsvmubuntubyol --plan-publisher microsoft-ads --plan-product linux-data-science-vm-ubuntu"
    echo -e "${BLUE}Auto-accepting licence terms for the Data Science VM${END}"
    az vm image accept-terms --urn $SOURCEIMAGE
else
    usage
fi

# Append timestamp to allow unique naming
TIMESTAMP="$(date '+%Y%m%d%H%M')"
BASENAME="Generalized${MACHINENAME}-${TIMESTAMP}"
IMAGENAME="Image${MACHINENAME}-${TIMESTAMP}"

# Create the VM based off the selected source image
echo -e "Provisioning a new VM image in ${BLUE}$RESOURCEGROUP${END} as part of ${BLUE}$SUBSCRIPTION${END}"
echo -e "  VM name: ${BLUE}$BASENAME${END}"
echo -e "  Base image: ${BLUE}$SOURCEIMAGE${END}"
STARTTIME=$(date +%s)
az vm create \
  --resource-group $RESOURCEGROUP \
  --name $BASENAME \
  --image $SOURCEIMAGE \
  --os-disk-size-gb $DISKSIZEGB \
  --custom-data $INITSCRIPT \
  --size Standard_DS2_v2 \
  --admin-username azureuser \
  --generate-ssh-keys

# # Get public IP address for this machine. Piping to echo removes the quotemarks around the address
PUBLICIP=$(az vm list-ip-addresses --resource-group $RESOURCEGROUP --name $BASENAME --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" | xargs echo)
echo -e "${RED}This process will take several hours to complete.${END}"
echo -e "  You can monitor installation progress using... ${BLUE}ssh azureuser@${PUBLICIP}${END}."
echo -e "  Once logged in, check the installation progress with: ${BLUE}tail -f /var/log/cloud-init-output.log${END}"