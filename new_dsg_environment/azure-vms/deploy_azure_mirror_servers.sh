#! /bin/bash

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"


# Options which are configurable at the command line
SUBSCRIPTION="" # must be provided
IP_RANGE_EXTERNAL="10.0.0.0/24"
IP_RANGE_INTERNAL="10.0.1.0/24"
RESOURCEGROUP="RG_SH_PKG_MIRRORS"
VNETNAME="VNet_SH_PKG_MIRRORS"

# Other constants
VAULTNAME="kvdsgpkgmirrors"
SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"
LOCATION="uksouth"

# Document usage for this script
print_usage_and_exit() {
    echo "usage: $0 [-h] -s subscription [-e external_ip] [-i internal_ip] [-r resource_group] [-v vnet_name]"
    echo "  -h                           display help"
    echo "  -s subscription [required]   specify subscription for storing the VM images . (Test using 'Safe Haven Management Testing')"
    echo "  -e external_ip               specify IP range for external mirror servers (defaults to '10.0.0.0/24')"
    echo "  -i internal_ip               specify IP range for internal mirror servers (defaults to '10.0.1.0/24')"
    echo "  -r resource_group            specify resource group - will be created if it does not already exist (defaults to '${RESOURCEGROUP}')"
    echo "  -v vnet_name                 specify name for VNet that mirror servers will belong to (defaults to '${VNETNAME}')"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "he:i:r:s:v:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        e)
            IP_RANGE_EXTERNAL=$OPTARG
            ;;
        i)
            IP_RANGE_INTERNAL=$OPTARG
            ;;
        r)
            RESOURCEGROUP=$OPTARG
            ;;
        s)
            SUBSCRIPTION=$OPTARG
            ;;
        v)
            VNETNAME=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done

# Check that a subscription has been provided
if [ "$SUBSCRIPTION" = "" ]; then
    echo -e "${RED}Subscription is a required argument!${END}"
    print_usage_and_exit
fi

# Set up subscription and vnet
# --------------------------------
# Switch subscription and setup resource group if it does not already exist
az account set --subscription "$SUBSCRIPTION"
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo -e "Creating resource group ${BLUE}$RESOURCEGROUP${END}"
    az group create --name $RESOURCEGROUP --location $LOCATION
fi


# Create keyvault with secrets
# ------------------------------
# Create keyvault if it does not already exist
if [ "$(az keyvault list | grep $VAULTNAME)" = "" ]; then
    echo -e "Creating keyvault ${BLUE}$VAULTNAME${END}"
    az keyvault create --name $VAULTNAME --resource-group $RESOURCEGROUP --enabled-for-deployment true
fi
# Wait for DNS propagation of keyvault
sleep 10
# For PyPI mirrors
if [ "$(az keyvault certificate list --vault-name $VAULTNAME | grep "keyPyPI")" = "" ]; then
    echo -e "Creating external ${BLUE}PyPI secret${END}"
    az keyvault certificate create --vault-name $VAULTNAME -n keyPyPI -p "$(az keyvault certificate get-default-policy -o json)"
fi
# For CRAN mirrors
if [ "$(az keyvault certificate list --vault-name $VAULTNAME | grep "keyCRAN")" = "" ]; then
    echo -e "Creating external ${BLUE}CRAN secret${END}"
    az keyvault certificate create --vault-name $VAULTNAME -n keyCRAN -p "$(az keyvault certificate get-default-policy -o json)"
fi

# Set up the NSGs, vnet and subnets
# ---------------------------
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name NSG_PKG_MIRRORS_EXTERNAL 2> /dev/null)" = "" ]; then
    echo -e "Creating NSG for external mirrors: ${BLUE}NSG_PKG_MIRRORS_EXTERNAL${END}"
    az network nsg create --resource-group $RESOURCEGROUP --name NSG_PKG_MIRRORS_EXTERNAL
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name NSG_PKG_MIRRORS_EXTERNAL --direction Inbound --name ManualConfigSSH --description "Allow port 22 for management over ssh" --source-address-prefixes 193.60.220.253 --destination-port-ranges 22 --protocol TCP --destination-address-prefixes "*" --priority 100
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name NSG_PKG_MIRRORS_EXTERNAL --direction Inbound --name rsync --description "Allow ports 22 and 873 for rsync" --source-address-prefixes $IP_RANGE_INTERNAL --destination-port-ranges 22 873 --protocol TCP --destination-address-prefixes "*" --priority 200
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name NSG_PKG_MIRRORS_EXTERNAL --direction Inbound --name DenyAll --description "Deny all" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
fi
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name NSG_PKG_MIRRORS_INTERNAL 2> /dev/null)" = "" ]; then
    echo -e "Creating NSG for internal mirrors: ${BLUE}NSG_PKG_MIRRORS_INTERNAL${END}"
    az network nsg create --resource-group $RESOURCEGROUP --name NSG_PKG_MIRRORS_INTERNAL
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name NSG_PKG_MIRRORS_INTERNAL --direction Inbound --name rsync --description "Allow ports 22 and 873 for rsync" --source-address-prefixes $IP_RANGE_EXTERNAL --destination-port-ranges 22 873 --protocol TCP --destination-address-prefixes "*" --priority 200
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name NSG_PKG_MIRRORS_INTERNAL --direction Inbound --name http --description "Allow ports 80 and 8080 for webservices" --source-address-prefixes VirtualNetwork --destination-port-ranges 80 8080 --protocol TCP --destination-address-prefixes "*" --priority 300
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name NSG_PKG_MIRRORS_INTERNAL --direction Inbound --name DenyAll --description "Deny all" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
fi
# Create vnet if it does not already exist
if [ "$(az network vnet list -g $RESOURCEGROUP | grep $VNETNAME)" = "" ]; then
    echo "Creating VNet $VNETNAME"
    az network vnet create -g $RESOURCEGROUP -n $VNETNAME
fi
# Make the subnets
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNETNAME | grep "SBNT_PKG_MIRRORS_EXTERNAL" 2> /dev/null)" = "" ]; then
    echo -e "Creating subnet SBNT_PKG_MIRRORS_EXTERNAL"
    az network vnet subnet create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNETNAME \
        --network-security-group NSG_PKG_MIRRORS_EXTERNAL \
        --address-prefix $IP_RANGE_EXTERNAL \
        --name SBNT_PKG_MIRRORS_EXTERNAL
fi
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNETNAME | grep "SBNT_PKG_MIRRORS_INTERNAL" 2> /dev/null)" = "" ]; then
    echo -e "Creating subnet SBNT_PKG_MIRRORS_INTERNAL"
    az network vnet subnet create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNETNAME \
        --network-security-group NSG_PKG_MIRRORS_INTERNAL \
        --address-prefix $IP_RANGE_INTERNAL \
        --name SBNT_PKG_MIRRORS_INTERNAL
fi


# Set up PyPI external mirror
# ---------------------------
VMNAME="VMExternalMirrorPyPI"
SUBNET="SBNT_PKG_MIRRORS_EXTERNAL"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $VMNAME)" = "" ]; then
    INITSCRIPT="cloud-init-mirror-external-pypi.yaml"

    # Create the VM based off the selected source image
    echo -e "${RED}Creating VM ${BLUE}$VMNAME${RED} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
    KEY_SECRET=$(az keyvault secret list-versions --vault-name $VAULTNAME -n keyPyPI --query "[?attributes.enabled].id" -o tsv)
    VM_SECRET=$(az vm secret format -s "$KEY_SECRET")

    # Create the data disk
    echo -e "${RED}Creating 4TB datadisk${END}"
    DISKNAME=${VMNAME}_DATADISK
    az disk create \
        --resource-group $RESOURCEGROUP \
        --name $DISKNAME \
        --size-gb 4095 \
        --location $LOCATION

    echo -e "${RED}Creating VM...${END}"
    az vm create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNETNAME \
        --subnet $SUBNET \
        --name $VMNAME \
        --image $SOURCEIMAGE \
        --custom-data $INITSCRIPT \
        --admin-username atiadmin \
        --attach-data-disks $DISKNAME \
        --nsg "" \
        --public-ip-address "" \
        --secrets "$VM_SECRET" \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS
    echo -e "${RED}Deployed new ${BLUE}$VMNAME${RED} server${END}"
        # --public-ip-address "" \
fi


# Set up CRAN external mirror
# ---------------------------
VMNAME="VMExternalMirrorCRAN"
SUBNET="SBNT_PKG_MIRRORS_EXTERNAL"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $VMNAME)" = "" ]; then
    INITSCRIPT="cloud-init-mirror-external-cran.yaml"

    # Create the VM based off the selected source image
    echo -e "${RED}Creating VM ${BLUE}$VMNAME${RED} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
    KEY_SECRET=$(az keyvault secret list-versions --vault-name $VAULTNAME -n keyCRAN --query "[?attributes.enabled].id" -o tsv)
    VM_SECRET=$(az vm secret format -s "$KEY_SECRET")

    # Create the data disk
    echo -e "${RED}Creating 4TB datadisk${END}"
    DISKNAME=${VMNAME}_DATADISK
    az disk create \
        --resource-group $RESOURCEGROUP \
        --name $DISKNAME \
        --size-gb 4095 \
        --location $LOCATION

    echo -e "${RED}Creating VM...${END}"
    az vm create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNETNAME \
        --subnet $SUBNET \
        --name $VMNAME \
        --image $SOURCEIMAGE \
        --custom-data $INITSCRIPT \
        --admin-username atiadmin \
        --attach-data-disks $DISKNAME \
        --nsg "" \
        --public-ip-address "" \
        --secrets "$VM_SECRET" \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS
    echo -e "${RED}Deployed new ${BLUE}$VMNAME${RED} server${END}"
fi


# Set up PyPI internal mirror
# ---------------------------
VMNAME="VMInternalMirrorPyPI"
SUBNET="SBNT_PKG_MIRRORS_INTERNAL"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $VMNAME)" = "" ]; then
    INITSCRIPT="cloud-init-mirror-internal-pypi.yaml"

    # Create the VM based off the selected source image, opening port 443 for the webserver
    echo -e "${RED}Creating VM ${BLUE}$VMNAME${RED} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
    KEY_SECRET=$(az keyvault secret list-versions --vault-name $VAULTNAME -n keyPyPI --query "[?attributes.enabled].id" -o tsv)
    VM_SECRET=$(az vm secret format -s "$KEY_SECRET")

    # Create the data disk
    echo -e "${RED}Creating 4TB datadisk${END}"
    DISKNAME=${VMNAME}_DATADISK
    az disk create \
        --resource-group $RESOURCEGROUP \
        --name $DISKNAME \
        --size-gb 4095 \
        --location $LOCATION

    echo -e "${RED}Creating VM...${END}"
    az vm create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNETNAME \
        --subnet $SUBNET \
        --name $VMNAME \
        --image $SOURCEIMAGE \
        --custom-data $INITSCRIPT \
        --admin-username atiadmin \
        --attach-data-disks $DISKNAME \
        --nsg "" \
        --public-ip-address "" \
        --secrets "$VM_SECRET" \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS
    echo -e "${RED}Deployed new ${BLUE}$VMNAME${RED} server${END}"
fi

# Set up CRAN internal mirror
# ---------------------------
VMNAME="VMInternalMirrorCRAN"
SUBNET="SBNT_PKG_MIRRORS_INTERNAL"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $VMNAME)" = "" ]; then
    INITSCRIPT="cloud-init-mirror-internal-cran.yaml"

    # Create the VM based off the selected source image, opening port 443 for the webserver
    echo -e "${RED}Creating VM ${BLUE}$VMNAME${RED} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
    KEY_SECRET=$(az keyvault secret list-versions --vault-name $VAULTNAME -n keyCRAN --query "[?attributes.enabled].id" -o tsv)
    VM_SECRET=$(az vm secret format -s "$KEY_SECRET")

    # Create the data disk
    echo -e "${RED}Creating 4TB datadisk${END}"
    DISKNAME=${VMNAME}_DATADISK
    az disk create \
        --resource-group $RESOURCEGROUP \
        --name $DISKNAME \
        --size-gb 4095 \
        --location $LOCATION

    echo -e "${RED}Creating VM...${END}"
    az vm create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNETNAME \
        --subnet $SUBNET \
        --name $VMNAME \
        --image $SOURCEIMAGE \
        --custom-data $INITSCRIPT \
        --admin-username atiadmin \
        --attach-data-disks $DISKNAME \
        --nsg "" \
        --public-ip-address "" \
        --secrets "$VM_SECRET" \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS
    echo -e "${RED}Deployed new ${BLUE}$VMNAME${RED} server${END}"
fi