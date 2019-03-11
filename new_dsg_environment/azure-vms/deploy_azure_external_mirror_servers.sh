#! /bin/bash

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# Options which are configurable at the command line
SUBSCRIPTION="" # must be provided
IP_TRIPLET_EXTERNAL="10.0.0"
KEYVAULT_NAME="kv-sh-pkg-mirrors" # must be globally unique
RESOURCEGROUP="RG_SH_PKG_MIRRORS"

# Other constants
SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"
LOCATION="uksouth"
VNET_NAME="VNET_SH_PKG_MIRRORS"
NSG_EXTERNAL="NSG_SH_PKG_MIRRORS_EXTERNAL"
SUBNET_EXTERNAL="SBNT_SH_PKG_MIRRORS_EXTERNAL"
VM_PREFIX_EXTERNAL="MirrorVMExternal"


# Document usage for this script
# ------------------------------
print_usage_and_exit() {
    echo "usage: $0 [-h] -s subscription [-e external_ip] [-k keyvault_name] [-r resource_group]"
    echo "  -h                           display help"
    echo "  -s subscription [required]   specify subscription where the mirror servers should be deployed. (Test using 'Safe Haven Management Testing')"
    echo "  -e external_ip               specify initial IP triplet for external mirror servers (defaults to '${IP_TRIPLET_EXTERNAL}')"
    echo "  -k keyvault_name             specify (globally unique) name for keyvault that will be used to store admin passwords for the mirror servers (defaults to '${KEYVAULT_NAME}')"
    echo "  -r resource_group            specify resource group - will be created if it does not already exist (defaults to '${RESOURCEGROUP}')"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
# ----------------------------------------------------------------
while getopts "he:k:r:s:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        e)
            IP_TRIPLET_EXTERNAL=$OPTARG
            ;;
        k)
            KEYVAULT_NAME=$OPTARG
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


# Check that a subscription has been provided and switch to it
# ------------------------------------------------------------
if [ "$SUBSCRIPTION" = "" ]; then
    echo -e "${RED}Subscription is a required argument!${END}"
    print_usage_and_exit
fi
az account set --subscription "$SUBSCRIPTION"


# Setup resource group if it does not already exist
# -------------------------------------------------------------------------
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo -e "${RED}Creating resource group ${BLUE}$RESOURCEGROUP${END}"
    az group create --name $RESOURCEGROUP --location $LOCATION
fi


# Create keyvault for storing passwords if it does not already exist
# ------------------------------------------------------------------
if [ "$(az keyvault list --resource-group $RESOURCEGROUP | grep $KEYVAULT_NAME)" = "" ]; then
    echo -e "${RED}Creating keyvault ${BLUE}$KEYVAULT_NAME${END}"
    az keyvault create --name $KEYVAULT_NAME --resource-group $RESOURCEGROUP --enabled-for-deployment true
    # Wait for DNS propagation of keyvault
    sleep 10
fi


# Set IP range from triplet information
# -------------------------------------
IP_RANGE_EXTERNAL="${IP_TRIPLET_EXTERNAL}.0/24"
echo -e "${RED}Will deploy external mirrors in the IP range ${BLUE}$IP_RANGE_EXTERNAL${END}"


# Set up the VNet, external NSG and external subnet
# -------------------------------------------------
# Create VNet if it does not already exist
if [ "$(az network vnet list -g $RESOURCEGROUP | grep $VNET_NAME)" = "" ]; then
    echo -e "${RED}Creating VNet ${BLUE}$VNET_NAME${END}"
    az network vnet create --resource-group $RESOURCEGROUP --name $VNET_NAME
fi

# Create external NSG if it does not already exist
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSG_EXTERNAL 2> /dev/null)" = "" ]; then
    echo -e "${RED}Creating NSG for external mirrors: ${BLUE}$NSG_EXTERNAL${END}"
    az network nsg create --resource-group $RESOURCEGROUP --name $NSG_EXTERNAL
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Inbound --name DenyAllInbound --description "Deny all other inbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name updateOutbound --description "Allow ports 80, 443, 873  and 8080 for updating mirrors" --source-address-prefixes $IP_RANGE_EXTERNAL --destination-port-ranges 80 443 873 8080 --protocol TCP --destination-address-prefixes Internet --priority 300
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name DenyAllOutbound --description "Deny all other outbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
fi

# Create external subnet if it does not already exist
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNET_NAME | grep "${SUBNET_EXTERNAL}" 2> /dev/null)" = "" ]; then
    echo -e "${RED}Creating subnet ${BLUE}$SUBNET_EXTERNAL${END}"
    az network vnet subnet create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNET_NAME \
        --network-security-group $NSG_EXTERNAL \
        --address-prefix $IP_RANGE_EXTERNAL \
        --name $SUBNET_EXTERNAL
fi




# Set up PyPI external mirror
# ---------------------------
VMNAME_EXTERNAL="${VM_PREFIX_EXTERNAL}PyPI"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $VMNAME_EXTERNAL)" = "" ]; then
    CLOUDINITYAML="cloud-init-mirror-external-pypi.yaml"
    ADMIN_PASSWORD_SECRET_NAME="vm-admin-password-external-pypi"

    # Ensure that admin password is available
    if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
        echo -e "${RED}Creating admin password for ${BLUE}$VMNAME_EXTERNAL${END}"
        az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(date +%s | sha256sum | base64 | head -c 32)
    fi
    # Retrieve admin password from keyvault
    ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

    # Create the VM based off the selected source image
    echo -e "${RED}Creating VM ${BLUE}$VMNAME_EXTERNAL${RED} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"

    # Create the data disk
    echo -e "${RED}Creating 4TB datadisk...${END}"
    DISKNAME=${VMNAME_EXTERNAL}_DATADISK
    az disk create \
        --resource-group $RESOURCEGROUP \
        --name $DISKNAME \
        --size-gb 4095 \
        --location $LOCATION

    echo -e "${RED}Creating VM...${END}"
    OSDISKNAME=${VMNAME_EXTERNAL}_OSDISK
    PRIVATEIPADDRESS=${IP_TRIPLET_EXTERNAL}.4
    az vm create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNET_NAME \
        --subnet $SUBNET_EXTERNAL \
        --name $VMNAME_EXTERNAL \
        --image $SOURCEIMAGE \
        --custom-data $CLOUDINITYAML \
        --admin-username atiadmin \
        --admin-password $ADMIN_PASSWORD \
        --authentication-type password \
        --attach-data-disks $DISKNAME \
        --os-disk-name $OSDISKNAME \
        --nsg "" \
        --public-ip-address "" \
        --private-ip-address $PRIVATEIPADDRESS \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS
    # rm $TMPCLOUDINITYAML
    echo -e "${RED}Deployed new ${BLUE}$VMNAME_EXTERNAL${RED} server${END}"
fi


# Set up CRAN external mirror
# ---------------------------
VMNAME_EXTERNAL="${VM_PREFIX_EXTERNAL}CRAN"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $VMNAME_EXTERNAL)" = "" ]; then
    CLOUDINITYAML="cloud-init-mirror-external-cran.yaml"
    ADMIN_PASSWORD_SECRET_NAME="vm-admin-password-external-cran"

    # Ensure that admin password is available
    if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
        echo -e "${RED}Creating admin password for ${BLUE}$VMNAME_EXTERNAL${END}"
        az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(date +%s | sha256sum | base64 | head -c 32)
    fi
    # Retrieve admin password from keyvault
    ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

    # Create the VM based off the selected source image
    echo -e "${RED}Creating VM ${BLUE}$VMNAME_EXTERNAL${RED} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"

    # Create the data disk
    echo -e "${RED}Creating 4TB datadisk...${END}"
    DISKNAME=${VMNAME_EXTERNAL}_DATADISK
    az disk create \
        --resource-group $RESOURCEGROUP \
        --name $DISKNAME \
        --size-gb 4095 \
        --location $LOCATION

    echo -e "${RED}Creating VM...${END}"
    OSDISKNAME=${VMNAME_EXTERNAL}_OSDISK
    PRIVATEIPADDRESS=${IP_TRIPLET_EXTERNAL}.5
    az vm create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNET_NAME \
        --subnet $SUBNET_EXTERNAL \
        --name $VMNAME_EXTERNAL \
        --image $SOURCEIMAGE \
        --custom-data $CLOUDINITYAML \
        --admin-username atiadmin \
        --admin-password $ADMIN_PASSWORD \
        --authentication-type password \
        --attach-data-disks $DISKNAME \
        --os-disk-name $OSDISKNAME \
        --nsg "" \
        --public-ip-address "" \
        --private-ip-address $PRIVATEIPADDRESS \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS
    echo -e "${RED}Deployed new ${BLUE}$VMNAME_EXTERNAL${RED} server${END}"
fi
