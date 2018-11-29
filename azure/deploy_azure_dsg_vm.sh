#! /bin/bash

# Constants for colourised output
RED="\033[0;31m"
BLUE="\033[0;34m"
END="\033[0m"

# Set default names
# SUBSCRIPTION="Data Study Group Testing"
# SOURCEIMAGE="ImageDSGComputeMachineVM-DataScienceBase-201811271331-ukwest"
# RESOURCEGROUP="DSGTest1"
SUBSCRIPTION="Safe Haven Management Testing"
SOURCEIMAGE="ImageDSGComputeMachineVM-DataScienceBase-201811281323"
RESOURCEGROUP="DataSafeHavenImages"
MACHINENAME="DSGTESTDSCPUv4"

# Document usage for this script
usage() {
    echo "usage: $0 [-h] [-i source_image] [-r resource_group] [-n machine_name]"
    echo "  -h                 display help"
    echo "  -i source_image    specify source_image: either 'Ubuntu' or 'DataScience' (default)"
    echo "  -n machine_name    specify machine name (defaults to 'DSGComputeMachineVM')"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "h:i:r:n:" opt; do
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
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done

# Switch subscription and setup resource group if it does not already exist
az account set --subscription "$SUBSCRIPTION"
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo "Creating resource group $RESOURCEGROUP"
    az group create --name $RESOURCEGROUP --location ukwest
fi

# Select source image by full name of image
# If using the Data Science VM then the terms will be automatically accepted
if [[ "$SOURCEIMAGE" == *"Ubuntu"* ]]; then
    PLANDETAILS=""
elif [[ "$SOURCEIMAGE" == *"DataScienceBase"* ]]; then
    PLANDETAILS="--plan-name linuxdsvmubuntubyol --plan-publisher microsoft-ads --plan-product linux-data-science-vm-ubuntu"
else
    usage
fi

# read -s -p "Enter VM password: " PASSWORD
# echo ""
PASSWORD="n00fn4gustL4zP07k7K5"

# Create the VM based off the selected source image
echo -e "Creating VM ${BLUE}$MACHINENAME${END} as part of ${BLUE}$RESOURCEGROUP${END}"
echo -e "This will be based off the ${BLUE}$SOURCEIMAGE${END} image"
STARTTIME=$(date +%s)
az vm create ${PLANDETAILS} \
  --resource-group $RESOURCEGROUP \
  --name $MACHINENAME \
  --image $SOURCEIMAGE \
  --custom-data cloud-init-compute-vm.yaml \
  --size Standard_DS2_v2 \
  --admin-username azureuser \
  --admin-password $PASSWORD

# allow some time for the system to finish initialising
sleep 30

# Open RDP port on the VM
echo -e "${BLUE}Opening RDP port${END}"
az vm open-port --resource-group $RESOURCEGROUP --name $MACHINENAME --port 3389


# Get public IP address for this machine. Piping to echo removes the quotemarks around the address
PUBLICIP=$(az vm list-ip-addresses --resource-group $RESOURCEGROUP --name $MACHINENAME --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" | xargs echo)

echo -e "This new VM can be accessed with remote desktop at ${BLUE}${PUBLICIP}${END}"
echo -e "See https://docs.microsoft.com/en-us/azure/virtual-machines/linux/use-remote-desktop for more details"