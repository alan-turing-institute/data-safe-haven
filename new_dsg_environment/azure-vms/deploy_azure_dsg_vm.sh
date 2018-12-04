#! /bin/bash

# Options which are configurable at the command line
SOURCEIMAGE="Ubuntu"
MACHINENAME="DSGComputeMachineVM"
RESOURCEGROUP="RS_DSG_TEST"
SUBSCRIPTIONSOURCE="" # must be provided
SUBSCRIPTIONTARGET="" # must be provided
USERNAME="atiadmin"
DSG_NSG="NSG_Linux_Servers"
DSG_VNET="DSG_DSGROUPTEST_VNet1"
DSG_SUBNET="Subnet-Data"
VM_SIZE="Standard_DS2_v2"

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# Other constants
RESOURCEGROUP_IMAGES="RG_DSG_IMAGEGALLERY"
GALLERY_IMAGES="SIG_DSG_COMPUTE"
RESOURCEGROUP_PKG_MIRRORS="RS_DSG_PKG_MIRRORS"
VNETNAME_PKG_MIRRORS="VN_DSG_PKG_MIRRORS"
LOCATION="uksouth"

# Document usage for this script
print_usage_and_exit() {
    echo "usage: $0 -s subscription_source -t subscription_target [-h] [-g nsg_name] [-i source_image] [-n machine_name] [-r resource_group] [-u user_name]"
    echo "  -h                        display help"
    echo "  -g nsg_name               specify which NSG to connect to (defaults to 'NSG_Linux_Servers')"
    echo "  -i source_image           specify source_image: either 'Ubuntu' (default) or 'DataScience'"
    echo "  -n machine_name           specify name of created VM, which must be unique in this resource group (defaults to 'DSGComputeMachineVM')"
    echo "  -r resource_group         specify resource group for deploying the VM image - will be created if it does not already exist (defaults to 'RS_DSG_TEST')"
    echo "  -u user_name              specify a username for the admin account (defaults to 'atiadmin')"
    echo "  -s subscription_source    specify source subscription that images are taken from [required]. (Test using 'Safe Haven Management Testing')"
    echo "  -t subscription_target    specify target subscription for deploying the VM image [required]. (Test using 'Data Study Group Testing')"
    echo "  -v vnet_name              specify a VNET to connect to (defaults to 'DSG_DSGROUPTEST_VNet1')"
    echo "  -w subnet_name            specify a subnet to connect to (defaults to 'Subnet-Data')"
    echo "  -z vm_size                specify a VM size to use (defaults to 'Standard_DS2_v2')"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "g:hi:n:r:u:s:t:v:w:z:" opt; do
    case $opt in
        g)
            DSG_NSG=$OPTARG
            ;;
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
        u)
            USERNAME=$OPTARG
            ;;
        s)
            SUBSCRIPTIONSOURCE=$OPTARG
            ;;
        t)
            SUBSCRIPTIONTARGET=$OPTARG
            ;;
        v)
            DSG_VNET=$OPTARG
            ;;
        w)
            DSG_SUBNET=$OPTARG
            ;;
        z)
            VM_SIZE=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done

# Check that a source subscription has been provided
if [ "$SUBSCRIPTIONSOURCE" = "" ]; then
    echo -e "${RED}Source subscription is a required argument!${END}"
    print_usage_and_exit
fi
# Check that a target subscription has been provided
if [ "$SUBSCRIPTIONTARGET" = "" ]; then
    echo -e "${RED}Target subscription is a required argument!${END}"
    print_usage_and_exit
fi

# Search for available images and prompt user to select one
az account set --subscription "$SUBSCRIPTIONSOURCE"
if [ "$SOURCEIMAGE" = "Ubuntu" ]; then
    IMAGE_DEFINITION="ComputeVM-Ubuntu1804Base"
elif [ "$SOURCEIMAGE" = "DataScience" ]; then
    IMAGE_DEFINITION="ComputeVM-DataScienceBase"
else
    echo -e "${RED}Could not interpret ${BLUE}${SOURCEIMAGE}${END} as an image type${END}"
    print_usage_and_exit
fi

# List available versions
echo -e "${BOLD}Found the following versions of ${BLUE}$IMAGE_DEFINITION${END}"
az sig image-version list \
    --resource-group $RESOURCEGROUP_IMAGES \
    --gallery-name $GALLERY_IMAGES \
    --gallery-image-definition $IMAGE_DEFINITION \
    --query "[].name" -o table
echo -e "${BOLD}Please type the version you would like to use, followed by [ENTER]${END}"
read VERSION

# Check that this is a valid version and then get the image ID
if [ "$(az sig image-version show --resource-group $RESOURCEGROUP_IMAGES --gallery-name $GALLERY_IMAGES --gallery-image-definition $IMAGE_DEFINITION --gallery-image-version $VERSION 2>&1 | grep 'not found')" != "" ]; then
    echo -e "${RED}Version $VERSION could not be found.${END}"
    print_usage_and_exit
fi
IMAGE_ID=$(az sig image-version show --resource-group $RESOURCEGROUP_IMAGES --gallery-name $GALLERY_IMAGES --gallery-image-definition $IMAGE_DEFINITION --gallery-image-version $VERSION --query "id" | xargs)

echo -e "${BOLD}Admin username will be: ${BLUE}${USERNAME}${END}"
read -s -p "Enter password for this user: " PASSWORD
echo ""

# Switch subscription and setup resource group if it does not already exist
# -------------------------------------------------------------------------
az account set --subscription "$SUBSCRIPTIONTARGET"
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo -e "${BOLD}Creating resource group ${BLUE}$RESOURCEGROUP${END}"
    az group create --name $RESOURCEGROUP --location $LOCATION
fi

# Check that NSG exists
# ---------------------
DSG_NSG_RG=""
DSG_NSG_ID=""
for RG in $(az group list --query "[].name" -o tsv); do
    if [ "$(az network nsg show --resource-group $RG --name $DSG_NSG 2> /dev/null)" != "" ]; then
        DSG_NSG_RG=$RG;
        DSG_NSG_ID=$(az network nsg show --resource-group $RG --name $DSG_NSG --query 'id' | xargs)
    fi
done
if [ "$DSG_NSG_RG" = "" ]; then
    echo -e "${RED}Could not find NSG ${BLUE}$DSG_NSG ${RED}in any resource group${END}"
    print_usage_and_exit
else
    echo -e "${BOLD}Found NSG ${BLUE}$DSG_NSG${END} ${BOLD}in resource group ${BLUE}$DSG_NSG_RG${END}"
fi

# Check that VNET and subnet exist
# --------------------------------
DSG_SUBNET_RG=""
DSG_SUBNET_ID=""
for RG in $(az group list --query "[].name" -o tsv); do
    # Check that VNET exists with subnet inside it
    if [ "$(az network vnet subnet list --resource-group $RG --vnet-name $DSG_VNET 2> /dev/null | grep $DSG_SUBNET)" != "" ]; then
        DSG_SUBNET_RG=$RG;
        DSG_SUBNET_ID=$(az network vnet subnet list --resource-group $RG --vnet-name $DSG_VNET --query "[?name == '$DSG_SUBNET'].id | [0]" | xargs)
    fi
done
if [ "$DSG_SUBNET_RG" = "" ]; then
    echo -e "${RED}Could not find subnet ${BLUE}$DSG_SUBNET${END} ${RED}in any resource group${END}"
    print_usage_and_exit
else
    echo -e "${BOLD}Found subnet ${BLUE}$DSG_SUBNET${END} ${BOLD}as part of VNET ${BLUE}$DSG_VNET${END} ${BOLD}in resource group ${BLUE}$DSG_SUBNET_RG${END}"
fi

# If using the Data Science VM then the terms must be added before creating the VM
PLANDETAILS=""
if [[ "$SOURCEIMAGE" == *"DataScienceBase"* ]]; then
    PLANDETAILS="--plan-name linuxdsvmubuntubyol --plan-publisher microsoft-ads --plan-product linux-data-science-vm-ubuntu"
fi

# Set appropriate username
cp cloud-init-compute-vm.yaml cloud-init-compute-vm-specific.yaml
# cp cloud-init-simpleubuntu.yaml cloud-init-compute-vm-specific.yaml
sed -i -e 's/USERNAME/'${USERNAME}'/g' cloud-init-compute-vm-specific.yaml

# Create the VM based off the selected source image
# -------------------------------------------------
echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME${END} ${BOLD}as part of ${BLUE}$RESOURCEGROUP${END}"
echo -e "${BOLD}This will use the ${BLUE}$SOURCEIMAGE${END}${BOLD}-based compute machine image"
STARTTIME=$(date +%s)
az vm create ${PLANDETAILS} \
  --resource-group $RESOURCEGROUP \
  --name $MACHINENAME \
  --image $IMAGE_ID \
  --subnet $DSG_SUBNET_ID \
  --nsg $DSG_NSG_ID \
  --public-ip-address "" \
  --custom-data cloud-init-compute-vm-specific.yaml \
  --size Standard_DS2_v2 \
  --admin-username $USERNAME \
  --admin-password $PASSWORD
rm cloud-init-compute-vm-specific.yaml*

# az vm create ${PLANDETAILS} \
#   --resource-group $RESOURCEGROUP \
#   --name $MACHINENAME \
#   --image Canonical:UbuntuServer:18.04-LTS:latest \
#   --subnet $DSG_SUBNET_ID \
#   --nsg $DSG_NSG_ID \
#   --public-ip-address "" \
#   --custom-data cloud-init-compute-vm-specific.yaml \
#   --size Standard_DS2_v2 \
#   --admin-username $USERNAME \
#   --admin-password $PASSWORD
# rm cloud-init-compute-vm-specific.yaml*



# allow some time for the system to finish initialising
sleep 30

# # Open RDP port on the VM - TODO should be done at NSG-level
# echo -e "Opening ${BLUE}RDP port${END}"
# az vm open-port --resource-group $RESOURCEGROUP --name $MACHINENAME --port 3389

# # Peer this VNet to the one containing the package mirrors
# # --------------------------------------------------------
# echo -e "Peering VNet with ${BLUE}$VNETNAME_PKG_MIRRORS${END}"
# # Get VNet IDs
# az account set --subscription "$SUBSCRIPTIONSOURCE"
# VNET_PKG_MIRROR_ID="$(az network vnet show --resource-group $RESOURCEGROUP_PKG_MIRRORS --name $VNETNAME_PKG_MIRRORS --query id | xargs)"
# az account set --subscription "$SUBSCRIPTIONTARGET"
# VNET_ID="$(az network vnet show --resource-group $RESOURCEGROUP --name $VNETNAME --query id | xargs)"
# # Peer VNets in both directions
# az account set --subscription "$SUBSCRIPTIONSOURCE"
# az network vnet peering create --resource-group $RESOURCEGROUP_PKG_MIRRORS --name "PEER_${VNETNAME}" --vnet-name $VNETNAME_PKG_MIRRORS --remote-vnet $VNET_ID
# az account set --subscription "$SUBSCRIPTIONTARGET"
# az network vnet peering create --resource-group $RESOURCEGROUP --name "PEER_${VNETNAME_PKG_MIRRORS}" --vnet-name $VNETNAME --remote-vnet $VNET_PKG_MIRROR_ID

# Get public IP address for this machine. Piping to echo removes the quotemarks around the address
PUBLICIP=$(az vm list-ip-addresses --resource-group $RESOURCEGROUP --name $MACHINENAME --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" | xargs echo)

echo -e "${BOLD}This new VM can be accessed with remote desktop at ${BLUE}${PUBLICIP}${END}"
# echo -e "See https://docs.microsoft.com/en-us/azure/virtual-machines/linux/use-remote-desktop for more details"



# if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSGNAME 2> /dev/null)" = "" ]; then
#     echo -e "${RED}Could not find NSG ${BLUE}$DSG_NSG ${RED}in resource group ${BLUE}$RESOURCEGROUP${END}"
#     print_usage_and_exit
#     # az network nsg create --resource-group $RESOURCEGROUP --name $NSGNAME
#     # az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSGNAME --direction Outbound --name AllowVNetHttp --description "Allow 80 and 8080 outbound to Azure" --protocol "*" --source-address-prefixes VirtualNetwork --source-port-ranges "*" --destination-address-prefixes VirtualNetwork --destination-port-ranges 80 8080 --priority 500
#     # az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSGNAME --direction Outbound --access Deny --name DenyInternet --description "Deny outbound internet connections" --protocol "*" --source-address-prefixes VirtualNetwork --source-port-ranges "*" --destination-address-prefixes "Internet" --destination-port-ranges "*" --priority 3000
# fi


# # Check that VNET and subnet already exist
# # ----------------------------------------
# if [ "$(az network vnet list --resource-group $RESOURCEGROUP | grep $DSG_VNET)" = "" ]; then
#     echo -e "${RED}Could not find VNET ${BLUE}$DSG_VNET ${RED}in resource group ${BLUE}$RESOURCEGROUP${END}"
#     print_usage_and_exit
#     # echo "Creating VNet $VNETNAME"
#     # az network vnet create --resource-group $RESOURCEGROUP -n $VNETNAME
# fi
# if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $DSG_VNET | grep $DSG_SUBNET)" = "" ]; then
#     echo -e "${RED}Could not find subnet ${BLUE}$DSG_SUBNET ${RED}in VNET ${BLUE}$DSG_VNET${END}"
#     print_usage_and_exit
#     # echo "Creating subnet $SUBNETNAME"
#     # az network vnet subnet create --resource-group $RESOURCEGROUP --vnet-name $VNETNAME --network-security-group $NSGNAME --address-prefixes $IPRANGE --name $SUBNETNAME
# fi