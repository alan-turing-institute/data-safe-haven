#! /bin/bash

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# # Options which are configurable at the command line
SUBSCRIPTION="" # must be provided
RESOURCEGROUP="RG_SHM_DEPLOYMENT_POOL"
# SUBSCRIPTIONTARGET="" # must be provided
# LDAP_SECRET_NAME=""
# LDAP_USER=""
# ADMIN_PASSWORD_SECRET_NAME=""
# DOMAIN=""
# AD_DC_NAME=""
# IP_ADDRESS=""
# DSG_NSG="NSG_Linux_Servers" # NB. this will disallow internet connection during deployment
# SOURCEIMAGE="Ubuntu"
# VERSION=""
MACHINENUMBER="" # must be provided
# DSG_VNET="DSG_DSGROUPTEST_VNet1"
# DSG_SUBNET="Subnet-Data"
# VM_SIZE="Standard_DS2_v2"
# CLOUD_INIT_YAML="cloud-init-compute-vm.yaml"
# PYPI_MIRROR_IP=""
# CRAN_MIRROR_IP=""

# Other constants
MACHINENAMEPREFIX="VM-DEPLOYMENT-POOL"
ADMIN_USERNAME="atiadmin"
# KEYVAULT_NAME="kv-shm-deployment" # must be globally unique
LOCATION="westeurope"
KEYVAULT_RG="RG_DSG_SECRETS"
VNET_NAME="VNET_SHM_DEPLOYMENT_POOL"
VNET_IPRANGE="10.0.0.0/24"
SUBNET_NAME="SUBNET_SHM_DEPLOYMENT_POOL"
NSG_NAME="NSG_SHM_DEPLOYMENT_POOL"
SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"


# IMAGES_RESOURCEGROUP="RG_SH_IMAGEGALLERY"
# IMAGES_GALLERY="SIG_SH_COMPUTE"
# LOCATION="uksouth"
# LDAP_RESOURCEGROUP="RG_SH_LDAP"
# DEPLOYMENT_NSG="NSG_IMAGE_DEPLOYMENT" # NB. this will *allow* internet connection during deployment


# Document usage for this script
print_usage_and_exit() {
    echo "usage: $0 [-h] -s subscription -n machine_number [-r resource_group]"
    echo "  -h                                    display help"
    echo "  -s subscription [required]            specify subscription to deploy into. (Test using 'Safe Haven Management Testing')"
    echo "  -i shm_id [required]                  specify the short ID for the Safe Haven Management segment (e.g. prod, test etc)"
    echo "  -n machine_number [required]          specify number of created VM, which must be unique in this resource group (VM will be called '${MACHINENAMEPREFIX}-<number>')"
    echo "  -r resource_group                     specify resource group for deploying the VM image - will be created if it does not already exist (defaults to '${RESOURCEGROUP}')"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "hi:n:r:s:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        i)
            SHMID=$OPTARG
            ;;
        n)
            MACHINENUMBER=$OPTARG
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


# Check that a subscription has been provided
# -------------------------------------------
if [ "$SUBSCRIPTION" = "" ]; then
    echo -e "${RED}Source subscription is a required argument!${END}"
    print_usage_and_exit
fi


# Check that an SHM ID has been provided
# -------------------------------------------
if [ "$SHMID" = "" ]; then
    echo -e "${RED}SHM ID is a required argument!${END}"
    print_usage_and_exit
fi
# Check that a machine number has been provided
# -------------------------------------------
if [ "$MACHINENUMBER" = "" ]; then
    echo -e "${RED}Machine number is a required argument!${END}"
    print_usage_and_exit
fi
MACHINENAME="${MACHINENAMEPREFIX}-${SHMID}-${MACHINENUMBER}"
DNSNAME="$(echo $MACHINENAME | tr '[:upper:]' '[:lower:]')"


# Switch subscription
# -------------------
az account set --subscription "$SUBSCRIPTION"
if [ "$(az account show --query 'name' | xargs)" != "$SUBSCRIPTION" ]; then
    echo -e "${RED}Could not set target subscription to ${BLUE}'${SUBSCRIPTION}'${END}${RED}. Are you a member? Current subscription is ${BLUE}'$(az account show --query 'name' | xargs)'${END}"
    print_usage_and_exit
fi


# Identify which keyvault should be used for storing passwords
# ------------------------------------------------------------
KEYVAULT_NAME="$(az keyvault list --resource-group $KEYVAULT_RG --query '([].name)[0]' -o tsv)"
if [ "$KEYVAULT_NAME" = "" ]; then
    echo -e "${RED}Could not find a keyvault in ${BLUE}$KEYVAULT_RG${RED}. Have you deployed one?${END}"
    print_usage_and_exit
fi
echo -e "${BOLD}Found a keyvault in ${KEYVAULT_RG}: ${BLUE}$KEYVAULT_NAME${END}"


# Setup deployment resource group if it does not already exist
# ------------------------------------------------------------
if [ "$(az group exists --name $RESOURCEGROUP)" != "true" ]; then
    echo -e "${BOLD}Creating resource group ${BLUE}$RESOURCEGROUP${END} ${BOLD}in ${BLUE}$SUBSCRIPTION${END}"
    az group create --name $RESOURCEGROUP --location $LOCATION
fi


# Create NSG if it does not already exist
# ---------------------------------------
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSG_NAME 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating NSG for deployment: ${BLUE}$NSG_NAME${END}"
    az network nsg create --resource-group $RESOURCEGROUP --name $NSG_NAME
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_NAME --direction Inbound --priority 1000 --name AllowMosh --description "Allow Mosh" --access "Allow" --source-address-prefixes "*" --source-port-ranges "*" --destination-address-prefixes "VirtualNetwork" --destination-port-ranges "60000-61000" --protocol "UDP"
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_NAME --direction Inbound --priority 2000 --name AllowTuringIPs --description "Allow inbound Turing connections on port 22 (SSH)" --access "Allow" --source-address-prefixes 193.60.220.253 193.60.220.240 --source-port-ranges "*" --destination-address-prefixes "*" --destination-port-ranges "22" --protocol "TCP"
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_NAME --direction Inbound --priority 3000 --name IgnoreInboundRulesBelowHere --description "Deny all other inbound" --access "Deny" --source-address-prefixes "*" --source-port-ranges "*" --destination-address-prefixes "*" --destination-port-ranges "*" --protocol "*"
fi


# Create VNet if it does not already exist
# ----------------------------------------
if [ "$(az network vnet list --resource-group $RESOURCEGROUP | grep $VNET_NAME)" = "" ]; then
    echo -e "${BOLD}Creating VNet for deployment: ${BLUE}$VNET_NAME${END}${BOLD} using the IP range ${BLUE}$VNET_IPRANGE${END}"
    az network vnet create --resource-group $RESOURCEGROUP --name $VNET_NAME --address-prefixes $VNET_IPRANGE
fi


# Create subnet if it does not already exist
# ------------------------------------------
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNET_NAME | grep "${SUBNET_NAME}" 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating subnet ${BLUE}$SUBNET_NAME${END}"
    az network vnet subnet create \
        --address-prefix $VNET_IPRANGE \
        --name $SUBNET_NAME \
        --network-security-group $NSG_NAME \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNET_NAME
fi


# Deploy a deployment VM
# ----------------------
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $MACHINENAME)" != "" ]; then
    echo -e "${RED}There is already a VM named ${BLUE}'${MACHINENAME}'${END}"
    print_usage_and_exit
else
    CLOUDINITYAML="cloud-init-deployment-vm.yaml"
    ADMIN_PASSWORD_SECRET_NAME="deployment-vm-admin-password"

    # Ensure that admin password is available
    if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
        echo -e "${BOLD}Creating admin password for ${BLUE}$MACHINENAME${END}"
        az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(head /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32)
    fi
    # Retrieve admin password from keyvault
    ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

    # Create the VM based off the selected source image
    echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME${END}${BOLD} as part of ${BLUE}$RESOURCEGROUP${END}${BOLD}...${END}"

    # Create the VM
    OSDISKNAME=${MACHINENAME}OSDisk
    az vm create \
        --admin-password $ADMIN_PASSWORD \
        --admin-username $ADMIN_USERNAME \
        --authentication-type password \
        --custom-data $CLOUDINITYAML \
        --image $SOURCEIMAGE \
        --name $MACHINENAME \
        --nsg $NSG_NAME \
        --os-disk-name $OSDISKNAME \
        --public-ip-address-dns-name $DNSNAME \
        --resource-group $RESOURCEGROUP \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS \
        --subnet $SUBNET_NAME \
        --vnet-name $VNET_NAME
    echo -e "${BOLD}Deployment in progress for new VM: ${BLUE}${MACHINENAME}${END}"

    # Retrieve the SSH key
    while true; do
        COMMAND_OUTPUT=$(az vm run-command invoke --name $MACHINENAME --resource-group $RESOURCEGROUP --command-id RunShellScript --scripts "cat ~atiadmin/.ssh/id_rsa.pub" --query "value[0].message" -o tsv)
        if [[ "$COMMAND_OUTPUT" != *"No such file or directory"* ]]; then break; fi
        echo -e "${BOLD}Checking whether deployment has finished...${END}"
        sleep 60
    done
    echo "COMMAND_OUTPUT: '$COMMAND_OUTPUT'"
    SSH_PUBLIC_KEY=$(echo $COMMAND_OUTPUT | cut -d' ' -f4-5)

    echo -e "${BOLD}Please add the following deploy key to the 'Settings > Deploy Keys' tab of the safe haven repo on Github (do not check the 'Allow write access' box - these VMs only need read access)${END}"
    echo -e ""
    echo -e "${BLUE}$SSH_PUBLIC_KEY${END}"
    echo -e ""
    echo -e "${BOLD}You can then log into the newly created deployment VM using ${BLUE}ssh atiadmin@${DNSNAME}.westeurope.cloudapp.azure.com${END}"
    echo -e "${BOLD}Once you've logged in, you can clone the safe haven repo with: ${BLUE}git clone git@github.com:alan-turing-institute/data-safe-haven.git${END}"
fi

