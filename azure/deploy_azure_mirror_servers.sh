#! /bin/bash

# Constants for colourised output
RED="\033[0;31m"
BLUE="\033[0;34m"
END="\033[0m"

# Set default names
SUBSCRIPTION="Safe Haven Management Testing"
RESOURCEGROUP="DataSafeHavenMirrors"
VAULTNAME="datasafehavenmirrorkeys"
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
# ------------------------------
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


# Set up PyPI external mirror
# ---------------------------
VMNAME="ExternalMirrorPyPI"
INITSCRIPT="cloud-init-mirror-external-pypi.yaml"

# Create the VM based off the selected source image
echo -e "${RED}Creating VM ${BLUE}$VMNAME${RED}as part of ${BLUE}$RESOURCEGROUP${END}"
echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
KEY_PYPI=$(az keyvault secret list-versions --vault-name $VAULTNAME -n keyextPyPI --query "[?attributes.enabled].id" -o tsv)
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


# Set up CRAN external mirror
# ---------------------------
VMNAME="ExternalMirrorCRAN"
INITSCRIPT="cloud-init-mirror-external-cran.yaml"

# Create the VM based off the selected source image
echo -e "${RED}Creating VM ${BLUE}$VMNAME${RED}as part of ${BLUE}$RESOURCEGROUP${END}"
echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
KEY_PYPI=$(az keyvault secret list-versions --vault-name $VAULTNAME -n keyextCRAN --query "[?attributes.enabled].id" -o tsv)
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


# # Set up PyPI internal mirror
# # ---------------------------
# VMNAME="InternalMirrorPyPI"
# INITSCRIPT="cloud-init-mirror-internal-pypi.yaml"

# # Create the VM based off the selected source image
# echo -e "${RED}Creating VM ${BLUE}$VMNAME${RED}as part of ${BLUE}$RESOURCEGROUP${END}"
# echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
# KEY_PYPI=$(az keyvault secret list-versions --vault-name $VAULTNAME -n keyintPyPI --query "[?attributes.enabled].id" -o tsv)
# VM_SECRET=$(az vm secret format -s "$KEY_PYPI")

# az vm create \
#     --resource-group $RESOURCEGROUP \
#     --name $VMNAME \
#     --image $SOURCEIMAGE \
#     --custom-data $INITSCRIPT \
#     --size Standard_F4s_v2 \
#     --admin-username adminpypi \
#     --data-disk-sizes-gb 4095 \
#     --storage-sku Standard_LRS \
#     --secrets "$VM_SECRET"
# echo -e "${RED}Deployed new ${BLUE}$VMNAME${RED} server"

# # Set up CRAN internal mirror
# # ---------------------------
# VMNAME="InternalMirrorCRAN"
# INITSCRIPT="cloud-init-mirror-internal-cran.yaml"

# # Create the VM based off the selected source image
# echo -e "${RED}Creating VM ${BLUE}$VMNAME${RED}as part of ${BLUE}$RESOURCEGROUP${END}"
# echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"
# KEY_PYPI=$(az keyvault secret list-versions --vault-name $VAULTNAME -n keyintCRAN --query "[?attributes.enabled].id" -o tsv)
# VM_SECRET=$(az vm secret format -s "$KEY_PYPI")

# az vm create \
#     --resource-group $RESOURCEGROUP \
#     --name $VMNAME \
#     --image $SOURCEIMAGE \
#     --custom-data $INITSCRIPT \
#     --size Standard_F4s_v2 \
#     --admin-username admincran \
#     --data-disk-sizes-gb 4095 \
#     --storage-sku Standard_LRS \
#     --secrets "$VM_SECRET"
# echo -e "${RED}Deployed new ${BLUE}$VMNAME${RED} server"





# sudo pip install pypiserver for clients...

# Generate SSH keys
# ssh-keygen -t rsa -b 4096 -f keyextCRAN
# ssh-keygen -t rsa -b 4096 -f keyextPyPI

# Upload key to vault
# az keyvault secret set --name keyextCRAN --vault-name $VAULTNAME --file keyextCRAN
# az keyvault secret set --name keyextPyPI --vault-name $VAULTNAME --file keyextPyPI

# Download the private key
# az keyvault secret download --name keyextCRAN --vault-name $VAULTNAME --file keyextCRAN
# az keyvault secret download --name keyextPyPI --vault-name $VAULTNAME --file keyextPyPI

# # Retrieve secrets from the keyvault
# if [ ! -f keyextPyPI.pub ]; then
#     az keyvault secret download --vault-name $VAULTNAME -n keyextPyPI -e base64 -f keyextPyPI.pfx
#     openssl pkcs12 -in keyextPyPI.pfx -out keyextPyPI.pem -nocerts -nodes
#     chmod 0400 keyextPyPI.pem
#     ssh-keygen -f keyextPyPI.pem -y > keyextPyPI.pub
#     # rm -f keyextPyPI.pfx keyextPyPI.pem
# fi