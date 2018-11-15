#! /bin/bash

# Constants for colourised output
RED="\033[0;31m"
BLUE="\033[0;34m"
END="\033[0m"

# Set default names
SOURCEIMAGE="DataScience"
RESOURCEGROUP="DataSafeHavenImageBuild"
MACHINENAME="DSGComputeMachineVM"

# Document usage for this script
usage() {  
    echo "usage: $0 [-h] [-i source_image] [-r resource_group] [-n machine_name]"
    echo "  -h                 display help"
    echo "  -i source_image    specify source_image: either 'Ubuntu' or 'DataScience' (default)"
    echo "  -r resource_group  specify resource group - will be created if it does not already exist (defaults to 'DataSafeHavenTest')"
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
        r)
            echo "Called r with $OPTARG"
            RESOURCEGROUP=$OPTARG
            ;;
        n)
            MACHINENAME=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done

# Select source image - either Ubuntu 18.04 or Microsoft Data Science (based on Ubuntu 16.04). Exit, printing usage, if anything else is requested.
# If using the Data Science VM then the terms will be automatically accepted
if [ "$SOURCEIMAGE" == "Ubuntu" ]; then
    SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"
    INITSCRIPT="cloud-init-ubuntu.yaml"
    DISKSIZEGB="40"
    PLANDETAILS=""
elif [ "$SOURCEIMAGE" == "DataScience" ]; then
    SOURCEIMAGE="microsoft-ads:linux-data-science-vm-ubuntu:linuxdsvmubuntubyol:18.08.00"
    INITSCRIPT="cloud-init-datascience.yaml"
    DISKSIZEGB="60"
    PLANDETAILS="--plan-name linuxdsvmubuntubyol --plan-publisher microsoft-ads --plan-product linux-data-science-vm-ubuntu"
    echo -e "${RED}Auto-accepting licence terms for the Data Science VM${END}"
    az vm image accept-terms --urn $SOURCEIMAGE
else
    usage
fi

# Append timestamp to allow unique naming
TIMESTAMP="$(date '+%Y%m%d%H%M')"
BASENAME="Provisioning${MACHINENAME}-${TIMESTAMP}"
IMAGENAME="Image${MACHINENAME}-${TIMESTAMP}"

# Create resource group if it does not already exist
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo "Creating resource group $RESOURCEGROUP"
    az group create --name $RESOURCEGROUP --location uksouth
fi

# Create the VM based off the selected source image
echo -e "${RED}Creating VM ${BLUE}$BASENAME ${RED}as part of ${BLUE}$RESOURCEGROUP${END}"
echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
STARTTIME=$(date +%s)
az vm create \
  --resource-group $RESOURCEGROUP \
  --name $BASENAME \
  --image $SOURCEIMAGE \
  --custom-data $INITSCRIPT \
  --os-disk-size-gb $DISKSIZEGB\
  --size Standard_DS2_v2 \
  --admin-username azureuser \
  --generate-ssh-keys 

sleep 20 # allow some time for the system to finish initialising or the connection might be refused

# Get public IP address for this machine. Piping to echo removes the quotemarks around the address
PUBLICIP=$(az vm list-ip-addresses --resource-group $RESOURCEGROUP --name $BASENAME --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" | xargs echo)

# ssh into the new VM calling the enclosed script to read output log
# Once installation is finished the loop will terminate and the ssh session will end
echo -e "${RED}Monitoring installation progress using... ${BLUE}ssh azureuser@${PUBLICIP}${END}"
ssh -o "StrictHostKeyChecking no" azureuser@${PUBLICIP} <<'ENDSSH'
log_file="/var/log/cloud-init-output.log"

tail -f -n +1 $log_file &
TAILPID=$(jobs -p)
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do
    sleep 1
done
kill $TAILPID
ENDSSH
ELAPSEDTIME=$(($(date +%s)-STARTTIME))
echo -e "${RED}Installation finished after $ELAPSEDTIME seconds${END}"
echo -e "Delete with ${BLUE}az vm delete --name $BASENAME --resource-group $RESOURCEGROUP${END}"

# Deallocate and generalize
echo -e "${RED}Deallocating and generalizing VM...${END}"
az vm deallocate --resource-group $RESOURCEGROUP --name $BASENAME
az vm generalize --resource-group $RESOURCEGROUP --name $BASENAME

# Create image and then list available images
echo -e "${RED}Creating an image from this VM...${END}"
az image create --resource-group $RESOURCEGROUP --name $IMAGENAME --source $BASENAME

echo -e "${RED}To make a new VM from this image do:${END}"
echo -e "${BLUE}az vm create --resource-group $RESOURCEGROUP --name <VMNAME> --image $IMAGENAME --admin-username azureuser --generate-ssh-keys ${PLANDETAILS}${END}"
echo -e "To use this new VM with remote desktop..."
echo -e "... port 3389 needs to be opened: ${BLUE}az vm open-port --resource-group $RESOURCEGROUP --name <VMNAME> --port 3389${END}"
echo -e "... a user account with a password is needed: ${BLUE}sudo passwd <USERNAME>${END}"
echo -e "... a default desktop is needed - eg. for xfce: ${BLUE}echo xfce4-session >~/.xsession${END}"
echo -e "See https://docs.microsoft.com/en-us/azure/virtual-machines/linux/use-remote-desktop for more details"

echo -e "${RED}To delete this image do:${END}"
echo -e "${BLUE}az image delete --resource-group $RESOURCEGROUP --name $IMAGENAME${END}"
