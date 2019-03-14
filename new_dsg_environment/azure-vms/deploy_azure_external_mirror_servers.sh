#! /bin/bash

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# Options which are configurable at the command line
IP_TRIPLET_DEPLOYMENT="10.0.0"
IP_TRIPLET_EXTERNAL="10.0.1"
KEYVAULT_NAME="kv-sh-pkg-mirrors-1038" # must be globally unique
RESOURCEGROUP="RG_SH_PKG_MIRRORS_1038"
SUBSCRIPTION="" # must be provided

# Other constants
ADMIN_USERNAME="atiadmin"
LOCATION="uksouth"
MACHINENAME_PREFIX_EXTERNAL="MirrorVMExternal"
NSG_EXTERNAL="NSG_SH_PKG_MIRRORS_EXTERNAL"
SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"
SUBNET_EXTERNAL="SBNT_SH_PKG_MIRRORS_EXTERNAL"
VNET_NAME="VNET_SH_PKG_MIRRORS"


# Document usage for this script
# ------------------------------
print_usage_and_exit() {
    echo "usage: $0 [-h] -s subscription [-e external_ip] [-k keyvault_name] [-r resource_group]"
    echo "  -h                           display help"
    echo "  -s subscription [required]   specify subscription where the mirror servers should be deployed. (Test using 'Safe Haven Management Testing')"
    echo "  -d deployment_ip             specify initial IP triplet used during deployment (defaults to '${IP_TRIPLET_EXTERNAL}')"
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
            print_usage_and_exit
            ;;
    esac
done


# Setup deployment names to match the external names
# ------------------------------------------------
NSG_DEPLOYMENT="$(echo $NSG_EXTERNAL | sed 's/EXTERNAL/DEPLOYMENT/')"
SUBNET_DEPLOYMENT="$(echo $SUBNET_EXTERNAL | sed 's/EXTERNAL/DEPLOYMENT/')"


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
    echo -e "${BOLD}Creating resource group ${BLUE}$RESOURCEGROUP${END}"
    az group create --name $RESOURCEGROUP --location $LOCATION
fi


# Create keyvault for storing passwords if it does not already exist
# ------------------------------------------------------------------
if [ "$(az keyvault list --resource-group $RESOURCEGROUP | grep $KEYVAULT_NAME)" = "" ]; then
    echo -e "${BOLD}Creating keyvault ${BLUE}$KEYVAULT_NAME${END}"
    az keyvault create --name $KEYVAULT_NAME --resource-group $RESOURCEGROUP --enabled-for-deployment true
    # Wait for DNS propagation of keyvault
    sleep 10
fi


# Set IP range from triplet information
# -------------------------------------
IP_RANGE_DEPLOYMENT="${IP_TRIPLET_DEPLOYMENT}.0/24"
IP_RANGE_EXTERNAL="${IP_TRIPLET_EXTERNAL}.0/24"
if [ "$IP_RANGE_DEPLOYMENT" = "$IP_RANGE_EXTERNAL" ]; then
    echo -e "${RED}Deployment and external IP ranges must be different!${END}"
    print_usage_and_exit
fi
echo -e "${BOLD}Will deploy external mirrors in the IP range ${BLUE}$IP_RANGE_DEPLOYMENT${END}${BOLD} before moving them to ${BLUE}$IP_RANGE_EXTERNAL${END}"


# Set up the VNet, NSGs and external subnet
# -------------------------------------------------
# Create VNet if it does not already exist
if [ "$(az network vnet list -g $RESOURCEGROUP | grep $VNET_NAME)" = "" ]; then
    echo -e "${BOLD}Creating VNet ${BLUE}$VNET_NAME${END}"
    az network vnet create --resource-group $RESOURCEGROUP --name $VNET_NAME
fi

# Create deployment NSG if it does not already exist
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSG_DEPLOYMENT 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating NSG ${BLUE}$NSG_DEPLOYMENT${END}${BOLD} with outbound internet access ${BLUE}(for use during deployment *only*)${END}"
    az network nsg create --resource-group $RESOURCEGROUP --name $NSG_DEPLOYMENT
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_DEPLOYMENT --direction Inbound --name DenyAllInbound --description "Deny all other inbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_DEPLOYMENT --direction Outbound --name configurationOutbound --description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for installing software" --source-address-prefixes "*" --destination-port-ranges 80 443 3128 --protocol TCP --destination-address-prefixes Internet --priority 300
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_DEPLOYMENT --direction Outbound --name DenyAllOutbound --description "Deny all other outbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
fi

# Create external NSG if it does not already exist
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSG_EXTERNAL 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating NSG for external mirrors: ${BLUE}$NSG_EXTERNAL${END}"
    az network nsg create --resource-group $RESOURCEGROUP --name $NSG_EXTERNAL
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Inbound --name DenyAllInbound --description "Deny all other inbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name updateOutbound --description "Allow ports 443 (https) and 873 (unencrypted rsync) for updating mirrors" --source-address-prefixes $IP_RANGE_EXTERNAL --destination-port-ranges 443 873 --protocol TCP --destination-address-prefixes Internet --priority 300
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name DenyAllOutbound --description "Deny all other outbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
fi

# Create deployment subnet if it does not already exist
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNET_NAME | grep "${SUBNET_DEPLOYMENT}" 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating subnet ${BLUE}$SUBNET_DEPLOYMENT${END}"
    az network vnet subnet create \
        --address-prefix $IP_RANGE_DEPLOYMENT \
        --name $SUBNET_DEPLOYMENT \
        --network-security-group $NSG_DEPLOYMENT \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNET_NAME
fi

# Create external subnet if it does not already exist
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNET_NAME | grep "${SUBNET_EXTERNAL}" 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating subnet ${BLUE}$SUBNET_EXTERNAL${END}"
    az network vnet subnet create \
        --address-prefix $IP_RANGE_EXTERNAL \
        --name $SUBNET_EXTERNAL \
        --network-security-group $NSG_EXTERNAL \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNET_NAME
fi


az network vnet subnet show -g $RESOURCEGROUP -n $SUBNET_EXTERNAL --vnet-name $VNET_NAME
az network vnet subnet show -g $RESOURCEGROUP -n $SUBNET_DEPLOYMENT --vnet-name $VNET_NAME


# Set up PyPI external mirror
# ---------------------------
MACHINENAME_EXTERNAL="${MACHINENAME_PREFIX_EXTERNAL}PyPI"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $MACHINENAME_EXTERNAL)" = "" ]; then
    CLOUDINITYAML="cloud-init-mirror-external-pypi.yaml"
    ADMIN_PASSWORD_SECRET_NAME="vm-admin-password-external-pypi"

    # Ensure that admin password is available
    if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
        echo -e "${BOLD}Creating admin password for ${BLUE}$MACHINENAME_EXTERNAL${END}"
        az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(date +%s | sha256sum | base64 | head -c 32)
    fi
    # Retrieve admin password from keyvault
    ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

    # Create the VM based off the selected source image
    echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${BOLD}This will be based off the ${BLUE}$SOURCEIMAGE${END}${BOLD} image${END}"

    # Create the data disk
    echo -e "${BOLD}Creating 4TB datadisk...${END}"
    DISKNAME=${MACHINENAME_EXTERNAL}_DATADISK
    az disk create \
        --resource-group $RESOURCEGROUP \
        --name $DISKNAME \
        --size-gb 4095 \
        --location $LOCATION

    echo -e "${BOLD}Creating VM...${END}"
    OSDISKNAME=${MACHINENAME_EXTERNAL}_OSDISK
    PRIVATEIPADDRESS=${IP_TRIPLET_DEPLOYMENT}.4
    az vm create \
        --admin-password $ADMIN_PASSWORD \
        --admin-username $ADMIN_USERNAME \
        --attach-data-disks $DISKNAME \
        --authentication-type password \
        --custom-data $CLOUDINITYAML \
        --image $SOURCEIMAGE \
        --name $MACHINENAME_EXTERNAL \
        --nsg "" \
        --os-disk-name $OSDISKNAME \
        --public-ip-address "" \
        --private-ip-address $PRIVATEIPADDRESS \
        --resource-group $RESOURCEGROUP \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS \
        --subnet $SUBNET_DEPLOYMENT \
        --vnet-name $VNET_NAME
    echo -e "${BOLD}Deployed new ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} server${END}"

    # Poll VM to see whether it has finished running
    echo -e "${BOLD}Waiting for VM setup to finish (this may take several minutes)...${END}"
    while true; do
        POLL=$(az vm get-instance-view --resource-group $RESOURCEGROUP --name $MACHINENAME_EXTERNAL --query "instanceView.statuses[?code == 'PowerState/running'].displayStatus")
        if [ "$(echo $POLL | grep 'VM running')" == "" ]; then break; fi
        sleep 10
    done

    # VM must be on for the subnet change to work
    echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME_EXTERNAL}${END}"
    az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME_EXTERNAL

    # Switch IP and subnet
    PRIVATEIPADDRESS=$(echo $PRIVATEIPADDRESS | sed "s/${IP_TRIPLET_DEPLOYMENT}/${IP_TRIPLET_EXTERNAL}/")
    NIC_NAME="${MACHINENAME_EXTERNAL}VMNic"
    IPCONFIG_NAME=$(az network nic show --resource-group $RESOURCEGROUP --name $NIC_NAME --query ipConfigurations[].name -o tsv)
    echo -e "${BOLD}Switching to IP address ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} inside secure subnet: ${BLUE}${SUBNET_EXTERNAL}${END}"
    az network nic ip-config update --resource-group $RESOURCEGROUP --nic-name $NIC_NAME --name $IPCONFIG_NAME --subnet $SUBNET_EXTERNAL --vnet-name $VNET_NAME --private-ip-address $PRIVATEIPADDRESS
fi


# Set up CRAN external mirror
# ---------------------------
MACHINENAME_EXTERNAL="${MACHINENAME_PREFIX_EXTERNAL}CRAN"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $MACHINENAME_EXTERNAL)" = "" ]; then
    CLOUDINITYAML="cloud-init-mirror-external-cran.yaml"
    ADMIN_PASSWORD_SECRET_NAME="vm-admin-password-external-cran"

    # Ensure that admin password is available
    if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
        echo -e "${BOLD}Creating admin password for ${BLUE}$MACHINENAME_EXTERNAL${END}"
        az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(date +%s | sha256sum | base64 | head -c 32)
    fi
    # Retrieve admin password from keyvault
    ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

    # Create the VM based off the selected source image
    echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${BOLD}This will be based off the ${BLUE}$SOURCEIMAGE${END}${BOLD} image${END}"

    # Create the data disk
    echo -e "${BOLD}Creating 4TB datadisk...${END}"
    DISKNAME=${MACHINENAME_EXTERNAL}_DATADISK
    az disk create \
        --resource-group $RESOURCEGROUP \
        --name $DISKNAME \
        --size-gb 4095 \
        --location $LOCATION

    echo -e "${BOLD}Creating VM...${END}"
    OSDISKNAME=${MACHINENAME_EXTERNAL}_OSDISK
    PRIVATEIPADDRESS=${IP_TRIPLET_DEPLOYMENT}.5
    az vm create \
        --admin-password $ADMIN_PASSWORD \
        --admin-username $ADMIN_USERNAME \
        --attach-data-disks $DISKNAME \
        --authentication-type password \
        --custom-data $CLOUDINITYAML \
        --image $SOURCEIMAGE \
        --name $MACHINENAME_EXTERNAL \
        --nsg "" \
        --os-disk-name $OSDISKNAME \
        --public-ip-address "" \
        --private-ip-address $PRIVATEIPADDRESS \
        --resource-group $RESOURCEGROUP \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS \
        --subnet $SUBNET_DEPLOYMENT \
        --vnet-name $VNET_NAME
    echo -e "${BOLD}Deployed new ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} server${END}"

    # Poll VM to see whether it has finished running
    echo -e "${BOLD}Waiting for VM setup to finish (this may take several minutes)...${END}"
    while true; do
        POLL=$(az vm get-instance-view --resource-group $RESOURCEGROUP --name $MACHINENAME_EXTERNAL --query "instanceView.statuses[?code == 'PowerState/running'].displayStatus")
        if [ "$(echo $POLL | grep 'VM running')" == "" ]; then break; fi
        sleep 10
    done

    # VM must be on for the subnet change to work
    echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME_EXTERNAL}${END}"
    az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME_EXTERNAL

    # Switch IP and subnet
    PRIVATEIPADDRESS=$(echo $PRIVATEIPADDRESS | sed "s/${IP_TRIPLET_DEPLOYMENT}/${IP_TRIPLET_EXTERNAL}/")
    NIC_NAME="${MACHINENAME_EXTERNAL}VMNic"
    IPCONFIG_NAME=$(az network nic show --resource-group $RESOURCEGROUP --name $NIC_NAME --query ipConfigurations[].name -o tsv)
    echo -e "${BOLD}Switching to IP address ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} inside secure subnet: ${BLUE}${SUBNET_EXTERNAL}${END}"
    az network nic ip-config update --resource-group $RESOURCEGROUP --nic-name $NIC_NAME --name $IPCONFIG_NAME --subnet $SUBNET_EXTERNAL --vnet-name $VNET_NAME --private-ip-address $PRIVATEIPADDRESS
fi
