#! /bin/bash

# Constants for colourised output
RED="\033[0;31m"
BLUE="\033[0;34m"
END="\033[0m"

# Set default names
SUBSCRIPTION="Safe Haven Management Testing"
RESOURCEGROUP="DataSafeHavenMirrors"
VNETNAME="DataSafeHavenVNet"
VAULTNAME="datasafehavenmirrorkeys"
SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"


# Set up subscription and vnet
# --------------------------------
# Switch subscription and setup resource group if it does not already exist
az account set --subscription "$SUBSCRIPTION"
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo "Creating resource group $RESOURCEGROUP"
    az group create --name $RESOURCEGROUP --location ukwest
fi

# Create vnet if it does not already exist
if [ "$(az network vnet list -g $RESOURCEGROUP | grep $VNETNAME)" = "" ]; then
    echo "Creating VNet $VNETNAME"
    az network vnet create -g $RESOURCEGROUP -n $VNETNAME
fi


# Create keyvault with secrets
# ------------------------------
# Create keyvault if it does not already exist
if [ "$(az keyvault list | grep $VAULTNAME)" = "" ]; then
    echo "Creating keyvault $VAULTNAME"
    az keyvault create --name $VAULTNAME --resource-group $RESOURCEGROUP --enabled-for-deployment true
fi
# For external mirrors
if [ "$(az keyvault certificate list --vault-name $VAULTNAME | grep "keyextPyPI")" = "" ]; then
    echo "Creating external PyPI secret"
    az keyvault certificate create --vault-name $VAULTNAME -n keyextPyPI -p "$(az keyvault certificate get-default-policy -o json)"
fi
if [ "$(az keyvault certificate list --vault-name $VAULTNAME | grep "keyextCRAN")" = "" ]; then
    echo "Creating external CRAN secret"
    az keyvault certificate create --vault-name $VAULTNAME -n keyextCRAN -p "$(az keyvault certificate get-default-policy -o json)"
fi
# For internal mirrors
if [ "$(az keyvault certificate list --vault-name $VAULTNAME | grep "keyintPyPI")" = "" ]; then
    echo "Creating internal PyPI secret"
    az keyvault certificate create --vault-name $VAULTNAME -n keyintPyPI -p "$(az keyvault certificate get-default-policy -o json)"
fi
if [ "$(az keyvault certificate list --vault-name $VAULTNAME | grep "keyintCRAN")" = "" ]; then
    echo "Creating internal CRAN secret"
    az keyvault certificate create --vault-name $VAULTNAME -n keyintCRAN -p "$(az keyvault certificate get-default-policy -o json)"
fi


# Set up the NSGs and subnets
# ---------------------------
if [ "$(az network nsg show -g $RESOURCEGROUP -n NSGExternalMirrors 2> /dev/null)" = "" ]; then
    echo "Creating NSG for external mirrors"
    az network nsg create -g $RESOURCEGROUP -n NSGExternalMirrors
fi
if [ "$(az network nsg show -g $RESOURCEGROUP -n NSGInternalMirrors 2> /dev/null)" = "" ]; then
    echo "Creating NSG for internal mirrors"
    az network nsg create -g $RESOURCEGROUP -n NSGInternalMirrors
fi
# Make the subnets
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNETNAME | grep "SubnetExternal" 2> /dev/null)" = "" ]; then
    echo "Creating subnet SubnetExternal"
    az network vnet subnet create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNETNAME \
        --network-security-group NSGExternalMirrors \
        --address-prefix 10.0.0.0/24 \
        --name SubnetExternal
fi
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNETNAME | grep "SubnetInternal" 2> /dev/null)" = "" ]; then
    echo "Creating subnet SubnetInternal"
    az network vnet subnet create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNETNAME \
        --network-security-group NSGInternalMirrors \
        --address-prefix 10.0.1.0/24 \
        --name SubnetInternal
fi


# Set up PyPI external mirror
# ---------------------------
VMNAME="ExternalMirrorPyPI"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $VMNAME)" = "" ]; then
    INITSCRIPT="cloud-init-mirror-external-pypi.yaml"

    # Create the VM based off the selected source image
    echo -e "${RED}Creating VM ${BLUE}$VMNAME${RED} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
    KEY_SECRET=$(az keyvault secret list-versions --vault-name $VAULTNAME -n keyextPyPI --query "[?attributes.enabled].id" -o tsv)
    VM_SECRET=$(az vm secret format -s "$KEY_SECRET")

    az vm create \
        --resource-group $RESOURCEGROUP \
        --subnet SubnetExternal \
        --vnet-name $VNETNAME \
        --name $VMNAME \
        --image $SOURCEIMAGE \
        --custom-data $INITSCRIPT \
        --size Standard_F4s_v2 \
        --admin-username adminpypi \
        --data-disk-sizes-gb 4095 \
        --storage-sku Standard_LRS \
        --secrets "$VM_SECRET"
    echo -e "${RED}Deployed new ${BLUE}$VMNAME${RED} server${END}"
fi


# Set up CRAN external mirror
# ---------------------------
VMNAME="ExternalMirrorCRAN"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $VMNAME)" = "" ]; then
    INITSCRIPT="cloud-init-mirror-external-cran.yaml"

    # Create the VM based off the selected source image
    echo -e "${RED}Creating VM ${BLUE}$VMNAME${RED} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
    KEY_SECRET=$(az keyvault secret list-versions --vault-name $VAULTNAME -n keyextCRAN --query "[?attributes.enabled].id" -o tsv)
    VM_SECRET=$(az vm secret format -s "$KEY_SECRET")

    az vm create \
        --resource-group $RESOURCEGROUP \
        --subnet SubnetExternal \
        --vnet-name $VNETNAME \
        --name $VMNAME \
        --image $SOURCEIMAGE \
        --custom-data $INITSCRIPT \
        --size Standard_F4s_v2 \
        --admin-username admincran \
        --data-disk-sizes-gb 4095 \
        --storage-sku Standard_LRS \
        --secrets "$VM_SECRET"
    echo -e "${RED}Deployed new ${BLUE}$VMNAME${RED} server${END}"
fi


# Set up PyPI internal mirror
# ---------------------------
VMNAME="InternalMirrorPyPI"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $VMNAME)" = "" ]; then
    INITSCRIPT="cloud-init-mirror-internal-pypi.yaml"

    # Create the VM based off the selected source image, opening port 443 for the webserver
    echo -e "${RED}Creating VM ${BLUE}$VMNAME${RED} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
    KEY_SECRET=$(az keyvault secret list-versions --vault-name $VAULTNAME -n keyintPyPI --query "[?attributes.enabled].id" -o tsv)
    VM_SECRET=$(az vm secret format -s "$KEY_SECRET")

    az vm create \
        --resource-group $RESOURCEGROUP \
        --subnet SubnetInternal \
        --vnet-name $VNETNAME \
        --name $VMNAME \
        --image $SOURCEIMAGE \
        --custom-data $INITSCRIPT \
        --size Standard_F4s_v2 \
        --admin-username adminpypi \
        --data-disk-sizes-gb 4095 \
        --storage-sku Standard_LRS \
        --secrets "$VM_SECRET"
    echo -e "${RED}Deployed new ${BLUE}$VMNAME${RED} server${END}"
fi

# Set up CRAN internal mirror
# ---------------------------
VMNAME="InternalMirrorCRAN"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $VMNAME)" = "" ]; then
    INITSCRIPT="cloud-init-mirror-internal-cran.yaml"

    # Create the VM based off the selected source image, opening port 443 for the webserver
    echo -e "${RED}Creating VM ${BLUE}$VMNAME${RED} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
    KEY_SECRET=$(az keyvault secret list-versions --vault-name $VAULTNAME -n keyintCRAN --query "[?attributes.enabled].id" -o tsv)
    VM_SECRET=$(az vm secret format -s "$KEY_SECRET")

    az vm create \
        --resource-group $RESOURCEGROUP \
        --subnet SubnetInternal \
        --vnet-name $VNETNAME \
        --name $VMNAME \
        --image $SOURCEIMAGE \
        --custom-data $INITSCRIPT \
        --size Standard_F4s_v2 \
        --admin-username admincran \
        --data-disk-sizes-gb 4095 \
        --storage-sku Standard_LRS \
        --secrets "$VM_SECRET"
    echo -e "${RED}Deployed new ${BLUE}$VMNAME${RED} server${END}"

    az vm open-port \
        --resource-group $RESOURCEGROUP \
        --name $VMNAME \
        --port 443
fi

# Currently running manual SSH generation on the external mirror - TODO find a better method
# ssh-keygen -t rsa -b 4096