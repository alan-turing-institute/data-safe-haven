#! /bin/bash

# Load common constants and options
source ${BASH_SOURCE%/*}/configs/images.sh
source ${BASH_SOURCE%/*}/configs/text.sh

# Options which are configurable at the command line
MACHINENAME="" # required

# Document usage for this script
print_usage_and_exit() {
    echo "usage: $0 [-h] -n machine_name [-s subscription] [-r resource_group_build] [-t resource_group_images]"
    echo "  -h                           display help"
    echo "  -n machine_name [required]   specify a machine name to turn into an image. Ensure that the build script has completely finished before running this [either this or source_image are required]."
    echo "  -s subscription              specify subscription for storing the VM images. (defaults to '${IMAGES_SUBSCRIPTION}')"
    echo "  -r resource_group_build      specify resource group where the machine already exists (defaults to '${RESOURCEGROUP_BUILD}')"
    echo "  -t resource_group_images     specify resource group where the image will be stored (defaults to '${RESOURCEGROUP_IMAGES}')"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "hn:r:s:t:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        n)
            MACHINENAME=$OPTARG
            ;;
        r)
            RESOURCEGROUP_BUILD=$OPTARG
            ;;
        s)
            IMAGES_SUBSCRIPTION=$OPTARG
            ;;
        t)
            RESOURCEGROUP_IMAGES=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done


# Check that machine name has been provided
# -----------------------------------------
if [ "$MACHINENAME" = "" ]; then
    echo -e "${RED}Machine name is a required argument!${END}"
    print_usage_and_exit
fi


# Check that a subscription has been provided and switch to it
# ------------------------------------------------------------
if [ "$IMAGES_SUBSCRIPTION" = "" ]; then
    echo -e "${RED}Subscription is a required argument!${END}"
    print_usage_and_exit
fi
az account set --subscription "$IMAGES_SUBSCRIPTION"


# Setup image resource group if it does not already exist
# -------------------------------------------------------
if [ $(az group exists --name $RESOURCEGROUP_IMAGES) != "true" ]; then
    echo -e "${BOLD}Creating resource group ${BLUE}$RESOURCEGROUP_IMAGES${END}"
    az group create --name $RESOURCEGROUP_IMAGES --location $IMAGES_LOCATION
fi


# Convert VM to image and clean up afterwards
# -------------------------------------------
if [ "$(az vm show --resource-group $RESOURCEGROUP_BUILD --name $MACHINENAME 2>/dev/null)" = "" ]; then
    echo -e "${RED}Could not find a machine called ${BLUE}${MACHINENAME}${RED} in resource group ${BLUE}${RESOURCEGROUP_BUILD}${END}"
    echo -e "${BOLD}Available machines are:${END}"
    az vm list --resource-group $RESOURCEGROUP_BUILD --query "[].name" -o table
    print_usage_and_exit
else
    # Deprovision the VM over SSH
    echo -e "${BOLD}Deprovisioning VM: ${BLUE}${MACHINENAME}${END}${BOLD}...${END}"
    MACHINE_IP=$(az vm list-ip-addresses -g $RESOURCEGROUP_BUILD -n $MACHINENAME --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv)
    echo -e "${BOLD}... preparing to send deprovisioning command over SSH to: ${BLUE}${MACHINE_IP}${END}${BOLD}...${END}"
    ssh ${BUILD_ADMIN_USERNAME}@${MACHINE_IP} 'sudo /installation/deprovision_vm.sh | sudo tee /installation/deprovision.log'
    echo -e "${BOLD}Waiting for deprovisioning to finish: ${BLUE}${MACHINENAME}${END}${BOLD}...${END}"
    az vm wait --name $MACHINENAME --resource-group $RESOURCEGROUP_BUILD --custom "instanceView.statuses[?code=='ProvisioningState/succeeded']"
    # Deallocate and generalize
    echo -e "${BOLD}Deallocating VM: ${BLUE}${MACHINENAME}${END}${BOLD}...${END}"
    az vm deallocate --name $MACHINENAME --resource-group $RESOURCEGROUP_BUILD
    echo -e "${BOLD}Generalizing VM: ${BLUE}${MACHINENAME}${END}${BOLD}...${END}"
    az vm generalize --name $MACHINENAME --resource-group $RESOURCEGROUP_BUILD
    # Create an image
    IMAGE="Image$(echo $MACHINENAME | sed 's/Candidate//')"
    echo -e "${BOLD}Creating an image from VM: ${BLUE}${MACHINENAME}${END}${BOLD}...${END}"
    MACHINE_ID=$(az vm show --resource-group $RESOURCEGROUP_BUILD --name $MACHINENAME --query "id" -o tsv)
    az image create --name $IMAGE --resource-group $RESOURCEGROUP_IMAGES --source $MACHINE_ID
    # If the image has been successfully created then remove build artifacts
    if [ "$(az image show --resource-group $RESOURCEGROUP_IMAGES --name $IMAGE --query 'id')" != "" ]; then
        echo -e "${BOLD}Removing residual artifacts of the build process from ${BLUE}${RESOURCEGROUP_BUILD}${END}"
        echo -e "${BOLD}... virtual machine: ${BLUE}${MACHINENAME}${END}"
        az vm delete --yes --name $MACHINENAME --resource-group $RESOURCEGROUP_BUILD
        echo -e "${BOLD}... hard disk: ${BLUE}${MACHINENAME}OSDISK${END}"
        az disk delete --yes --name "${MACHINENAME}OSDISK" --resource-group $RESOURCEGROUP_BUILD
        echo -e "${BOLD}... network card: ${BLUE}${MACHINENAME}VMNic${END}"
        az network nic delete --name "${MACHINENAME}VMNic" --resource-group $RESOURCEGROUP_BUILD
        echo -e "${BOLD}... public IP address: ${BLUE}${MACHINENAME}PublicIP${END}"
        az network public-ip delete --name "${MACHINENAME}PublicIP" --resource-group $RESOURCEGROUP_BUILD
    fi
    echo -e "${BOLD}Finished creating image ${BLUE}${IMAGE}${END}"
fi