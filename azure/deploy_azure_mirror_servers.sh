#! /bin/bash

# Constants for colourised output
RED="\033[0;31m"
BLUE="\033[0;34m"
END="\033[0m"

# Set default names
SUBSCRIPTION="Safe Haven Management Testing"
RESOURCEGROUP="DataSafeHavenMirrors"
VAULTNAME="safehavenkeys"
SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"


# Switch subscription and setup resource group if it does not already exist
az account set --subscription "$SUBSCRIPTION"
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo "Creating resource group $RESOURCEGROUP"
    az group create --name $RESOURCEGROUP --location ukwest
fi

# Create keyvault if it does not already exist
if [ "$(az keyvault list | grep $VAULTNAME)" = "" ]; then
    echo "Creating keyvault $VAULTNAME"
    az keyvault create --name $VAULTNAME --resource-group $RESOURCEGROUP --enabled-for-deployment true
fi

# Create secrets in the keyvault
if [ "$(az keyvault certificate list --vault-name $VAULTNAME | grep "key-PyPI")" = "" ]; then
    echo "Creating PyPI secret"
    az keyvault certificate create --vault-name $VAULTNAME -n key-PyPI -p "$(az keyvault certificate get-default-policy -o json)"
fi
if [ "$(az keyvault certificate list --vault-name $VAULTNAME | grep "key-CRAN")" = "" ]; then
    echo "Creating CRAN secret"
    az keyvault certificate create --vault-name $VAULTNAME -n key-CRAN -p "$(az keyvault certificate get-default-policy -o json)"
fi


# Set up PyPI mirror
# ------------------
VMNAME="ExternalMirrorPyPI"
INITSCRIPT="cloud-init-pypi.yaml"

# Create the VM based off the selected source image
echo -e "${RED}Creating VM ${BLUE}$VMNAME${RED}as part of ${BLUE}$RESOURCEGROUP${END}"
echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
KEY_PYPI=$(az keyvault secret list-versions --vault-name $VAULTNAME -n key-PyPI --query "[?attributes.enabled].id" -o tsv)
VM_SECRET=$(az vm secret format -s "$KEY_PYPI")

az vm create \
    --resource-group $RESOURCEGROUP \
    --name $VMNAME \
    --image $SOURCEIMAGE \
    --custom-data $INITSCRIPT \
    --size Standard_F4s_v2 \
    --admin-username adminpypi \
    --data-disk-sizes-gb 4095 \
    --storage-sku Standard_LRS \
    --secrets "$VM_SECRET"
echo -e "${RED}Deployed new ${BLUE}$VMNAME${RED} server"


# Set up CRAN mirror
# ------------------
VMNAME="ExternalMirrorCRAN"
INITSCRIPT="cloud-init-cran.yaml"

# Create the VM based off the selected source image
echo -e "${RED}Creating VM ${BLUE}$VMNAME${RED}as part of ${BLUE}$RESOURCEGROUP${END}"
echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
KEY_PYPI=$(az keyvault secret list-versions --vault-name $VAULTNAME -n key-CRAN --query "[?attributes.enabled].id" -o tsv)
VM_SECRET=$(az vm secret format -s "$KEY_PYPI")

az vm create \
    --resource-group $RESOURCEGROUP \
    --name $VMNAME \
    --image $SOURCEIMAGE \
    --custom-data $INITSCRIPT \
    --size Standard_F4s_v2 \
    --admin-username admincran \
    --data-disk-sizes-gb 4095 \
    --storage-sku Standard_LRS \
    --secrets "$VM_SECRET"
echo -e "${RED}Deployed new ${BLUE}$VMNAME${RED} server"

