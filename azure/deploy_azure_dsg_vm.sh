#! /bin/bash

# Options which are configurable at the command line
SOURCEIMAGE="Ubuntu"
MACHINENAME="DSGComputeMachineVM"
RESOURCEGROUP="RS_DSG_TEST"
SUBSCRIPTION="Data Study Group Testing"
USERNAME="atiadmin"

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;34m"
END="\033[0m"

# Other constants
MANAGEMENT_SUBSCRIPTION="Safe Haven Management Testing"
RESOURCEGROUP_IMAGES="RG_DSG_IMAGEGALLERY"
GALLERY_IMAGES="SIG_DSG_COMPUTE"
RESOURCEGROUP_PKG_MIRRORS="RS_DSG_PKG_MIRRORS"
VNETNAME_PKG_MIRRORS="VN_DSG_PKG_MIRRORS"
LOCATION="uksouth"
IPRANGE="10.0.2.0/24"

# Document usage for this script
usage() {
    echo "usage: $0 [-h] [-i source_image] [-n machine_name] [-r resource_group] [-s subscription] [-u user_name]"
    echo "  -h                 display help"
    echo "  -i source_image    specify source_image: either 'Ubuntu' (default) or 'DataScience'"
    echo "  -n machine_name    specify machine name (defaults to 'DSGComputeMachineVM')"
    echo "  -r resource_group  specify resource group - will be created if it does not already exist (defaults to 'RS_DSG_TEST')"
    echo "  -s subscription    specify subscription for this DSG (defaults to 'Data Study Group Testing')"
    echo "  -u user_name       specify a username for the admin account (defaults to 'atiadmin')"
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
        n)
            MACHINENAME=$OPTARG
            ;;
        r)
            RESOURCEGROUP=$OPTARG
            ;;
        s)
            SUBSCRIPTION=$OPTARG
            ;;
        u)
            USERNAME=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done

# Search for available images and prompt user to select one
az account set --subscription "$MANAGEMENT_SUBSCRIPTION"
if [ "$SOURCEIMAGE" = "Ubuntu" ]; then
    IMAGE_DEFINITION="ComputeVM-Ubuntu1804Base"
elif [ "$SOURCEIMAGE" = "DataScience" ]; then
    IMAGE_DEFINITION="ComputeVM-DataScienceBase"
else
    echo -e "${RED}Could not interpret ${BLUE}${SOURCEIMAGE}${END} as an image type${END}"
    usage
fi

# List available versions
echo -e "Found the following versions of ${BLUE}$IMAGE_DEFINITION${END}"
az sig image-version list \
    --resource-group $RESOURCEGROUP_IMAGES \
    --gallery-name $GALLERY_IMAGES \
    --gallery-image-definition $IMAGE_DEFINITION \
    --query "[].name" -o table
echo "Please type the version you would like to use, followed by [ENTER]"
read VERSION

# Check that this is a valid version and then get the image ID
if [ "$(az sig image-version show --resource-group $RESOURCEGROUP_IMAGES --gallery-name $GALLERY_IMAGES --gallery-image-definition $IMAGE_DEFINITION --gallery-image-version $VERSION 2>&1 | grep 'not found')" != "" ]; then
    echo "Version $VERSION could not be found."
fi
IMAGE_ID=$(az sig image-version show --resource-group $RESOURCEGROUP_IMAGES --gallery-name $GALLERY_IMAGES --gallery-image-definition $IMAGE_DEFINITION --gallery-image-version $VERSION --query "id" | xargs)

echo "Admin username will be: ${USERNAME}" 
read -s -p "Enter password for this user: " PASSWORD
echo ""

# Switch subscription and setup resource group if it does not already exist
# -------------------------------------------------------------------------
az account set --subscription "$SUBSCRIPTION"
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo "Creating resource group $RESOURCEGROUP"
    az group create --name $RESOURCEGROUP --location $LOCATION
fi
# Set up the NSG if it does not already exist
NSGNAME="NSG_$(echo $RESOURCEGROUP | sed 's/RS_//')"
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSGNAME 2> /dev/null)" = "" ]; then
    echo "Creating NSG $NSGNAME for resource group $RESOURCEGROUP"
    az network nsg create --resource-group $RESOURCEGROUP --name $NSGNAME
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSGNAME --direction Outbound --name AllowVNetHttp --description "Allow 80 and 8080 outbound to Azure" --protocol "*" --source-address-prefixes VirtualNetwork --source-port-ranges "*" --destination-address-prefixes VirtualNetwork --destination-port-ranges 80 8080 --priority 500
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSGNAME --direction Outbound --access Deny --name DenyInternet --description "Deny outbound internet connections" --protocol "*" --source-address-prefixes VirtualNetwork --source-port-ranges "*" --destination-address-prefixes "Internet" --destination-port-ranges "*" --priority 3000
fi
# Create vnet and subnet if they do not already exist
VNETNAME="VN_$(echo $RESOURCEGROUP | sed 's/RS_//')"
if [ "$(az network vnet list --resource-group $RESOURCEGROUP | grep $VNETNAME)" = "" ]; then
    echo "Creating VNet $VNETNAME"
    az network vnet create --resource-group $RESOURCEGROUP -n $VNETNAME
fi
SUBNETNAME="SBNT_$(echo $RESOURCEGROUP | sed 's/RS_//')"
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNETNAME | grep $SUBNETNAME)" = "" ]; then
    echo "Creating subnet $SUBNETNAME"
    az network vnet subnet create --resource-group $RESOURCEGROUP --vnet-name $VNETNAME --network-security-group $NSGNAME --address-prefixes $IPRANGE --name $SUBNETNAME
fi


# If using the Data Science VM then the terms must be added here
PLANDETAILS=""
if [[ "$SOURCEIMAGE" == *"DataScienceBase"* ]]; then
    PLANDETAILS="--plan-name linuxdsvmubuntubyol --plan-publisher microsoft-ads --plan-product linux-data-science-vm-ubuntu"
fi

# Set appropriate username
cp cloud-init-compute-vm.yaml cloud-init-compute-vm-specific.yaml
sed -i -e 's/USERNAME/'${USERNAME}'/g' cloud-init-compute-vm-specific.yaml

# Create the VM based off the selected source image
echo -e "Creating VM ${BLUE}$MACHINENAME${END} as part of ${BLUE}$RESOURCEGROUP${END}"
echo -e "This will use the ${BLUE}$SOURCEIMAGE${END}-based compute machine image"
STARTTIME=$(date +%s)
az vm create ${PLANDETAILS} \
  --resource-group $RESOURCEGROUP \
  --name $MACHINENAME \
  --image $IMAGE_ID \
  --vnet-name $VNETNAME \
  --subnet $SUBNETNAME \
  --custom-data cloud-init-compute-vm-specific.yaml \
  --size Standard_DS2_v2 \
  --admin-username $USERNAME \
  --admin-password $PASSWORD
rm cloud-init-compute-vm-specific.yaml*

# allow some time for the system to finish initialising
sleep 30

# Open RDP port on the VM
echo -e "Opening ${BLUE}RDP port${END}"
az vm open-port --resource-group $RESOURCEGROUP --name $MACHINENAME --port 3389

# Peer this VNet to the one containing the package mirrors
echo -e "Peering VNet with ${BLUE}$VNETNAME_PKG_MIRRORS${END}"

# Get VNet IDs
az account set --subscription "$MANAGEMENT_SUBSCRIPTION"
VNET_PKG_MIRROR_ID="$(az network vnet show --resource-group $RESOURCEGROUP_PKG_MIRRORS --name $VNETNAME_PKG_MIRRORS --query id | xargs)"
az account set --subscription "$SUBSCRIPTION"
VNET_ID="$(az network vnet show --resource-group $RESOURCEGROUP --name $VNETNAME --query id | xargs)"
# Peer VNets in both directions
az account set --subscription "$MANAGEMENT_SUBSCRIPTION"
az network vnet peering create --resource-group $RESOURCEGROUP_PKG_MIRRORS --name "PEER_${VNETNAME}" --vnet-name $VNETNAME_PKG_MIRRORS --remote-vnet $VNET_ID
az account set --subscription "$SUBSCRIPTION"
az network vnet peering create --resource-group $RESOURCEGROUP --name "PEER_${VNETNAME_PKG_MIRRORS}" --vnet-name $VNETNAME --remote-vnet $VNET_PKG_MIRROR_ID 

# Get public IP address for this machine. Piping to echo removes the quotemarks around the address
PUBLICIP=$(az vm list-ip-addresses --resource-group $RESOURCEGROUP --name $MACHINENAME --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" | xargs echo)

echo -e "This new VM can be accessed with remote desktop at ${BLUE}${PUBLICIP}${END}"
echo -e "See https://docs.microsoft.com/en-us/azure/virtual-machines/linux/use-remote-desktop for more details"
