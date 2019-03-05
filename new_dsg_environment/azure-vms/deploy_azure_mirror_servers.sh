#! /bin/bash

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# Options which are configurable at the command line
SUBSCRIPTION="" # must be provided
IP_TRIPLET_EXTERNAL="10.0.0"
IP_TRIPLET_INTERNAL="10.0.1"
RESOURCEGROUP="RG_SH_PKG_MIRRORS"
VNETNAME="VNET_SH_PKG_MIRRORS"

# Other constants
KEYVAULT_NAME="kv-sh-pkg-mirrors"
SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"
LOCATION="uksouth"
NSG_EXTERNAL="NSG_SH_PKG_MIRRORS_EXTERNAL"
NSG_INTERNAL="NSG_SH_PKG_MIRRORS_INTERNAL"
SUBNET_EXTERNAL="SBNT_SH_PKG_MIRRORS_EXTERNAL"
SUBNET_INTERNAL="SBNT_SH_PKG_MIRRORS_INTERNAL"
VM_PREFIX_EXTERNAL="MirrorVMExternal"
VM_PREFIX_INTERNAL="MirrorVMInternal"

# Document usage for this script
print_usage_and_exit() {
    echo "usage: $0 [-h] -s subscription [-e external_ip] [-i internal_ip] [-r resource_group] [-v vnet_name]"
    echo "  -h                           display help"
    echo "  -s subscription [required]   specify subscription for storing the VM images . (Test using 'Safe Haven Management Testing')"
    echo "  -e external_ip               specify initial IP triplet for external mirror servers (defaults to '${IP_TRIPLET_EXTERNAL}')"
    echo "  -i internal_ip               specify initial IP triplet for internal mirror servers (defaults to '${IP_TRIPLET_INTERNAL}')"
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
            IP_TRIPLET_EXTERNAL=$OPTARG
            ;;
        i)
            IP_TRIPLET_INTERNAL=$OPTARG
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

# Set IP ranges from triplet information
if [ "$IP_TRIPLET_EXTERNAL" = "$IP_TRIPLET_INTERNAL" ]; then
    echo -e "${RED}Internal and external IP triplets must be different!${END}"
    print_usage_and_exit
fi
IP_RANGE_EXTERNAL="${IP_TRIPLET_EXTERNAL}.0/24"
IP_RANGE_INTERNAL="${IP_TRIPLET_INTERNAL}.0/24"

# Set up subscription and vnet
# --------------------------------
# Switch subscription and setup resource group if it does not already exist
az account set --subscription "$SUBSCRIPTION"
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo -e "${RED}Creating resource group ${BLUE}$RESOURCEGROUP${END}"
    az group create --name $RESOURCEGROUP --location $LOCATION
fi


# Create keyvault for storing passwords
# -------------------------------------
# Create keyvault if it does not already exist
if [ "$(az keyvault list | grep $KEYVAULT_NAME)" = "" ]; then
    echo -e "${RED}Creating keyvault ${BLUE}$KEYVAULT_NAME${END}"
    az keyvault create --name $KEYVAULT_NAME --resource-group $RESOURCEGROUP --enabled-for-deployment true
    # Wait for DNS propagation of keyvault
    sleep 10
fi


# Set up the NSGs, VNet and subnets
# ---------------------------------
# Create NSGs if they do not already exist
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSG_EXTERNAL 2> /dev/null)" = "" ]; then
    echo -e "${RED}Creating NSG for external mirrors: ${BLUE}$NSG_EXTERNAL${END}"
    az network nsg create --resource-group $RESOURCEGROUP --name $NSG_EXTERNAL
    # TODO: Remove this once we're happy with the setup
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Inbound --name ManualConfigSSH --description "Allow port 22 for management over ssh" --source-address-prefixes 193.60.220.253 --destination-port-ranges 22 --protocol TCP --destination-address-prefixes "*" --priority 100
    # ^^^^^^^^
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Inbound --name rsync --description "Allow ports 22 and 873 for rsync" --source-address-prefixes $IP_RANGE_INTERNAL --destination-port-ranges 22 873 --protocol TCP --destination-address-prefixes "*" --priority 200
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Inbound --name DenyAll --description "Deny all" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
fi
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSG_INTERNAL 2> /dev/null)" = "" ]; then
    echo -e "${RED}Creating NSG for internal mirrors: ${BLUE}$NSG_INTERNAL${END}"
    az network nsg create --resource-group $RESOURCEGROUP --name $NSG_INTERNAL
    # TODO: Remove this once we're happy with the setup
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Inbound --name ManualConfigSSH --description "Allow port 22 for management over ssh" --source-address-prefixes 193.60.220.253 --destination-port-ranges 22 --protocol TCP --destination-address-prefixes "*" --priority 100
    # ^^^^^^^^
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Inbound --name rsync --description "Allow ports 22 and 873 for rsync" --source-address-prefixes $IP_RANGE_EXTERNAL --destination-port-ranges 22 873 --protocol TCP --destination-address-prefixes "*" --priority 200
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Inbound --name http --description "Allow ports 80 and 8080 for webservices" --source-address-prefixes VirtualNetwork --destination-port-ranges 80 8080 --protocol TCP --destination-address-prefixes "*" --priority 300
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Inbound --name DenyAll --description "Deny all" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
fi

# Create VNet if it does not already exist
if [ "$(az network vnet list -g $RESOURCEGROUP | grep $VNETNAME)" = "" ]; then
    echo -e "${RED}Creating VNet ${BLUE}$VNETNAME${END}"
    az network vnet create --resource-group $RESOURCEGROUP --name $VNETNAME
fi
az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNETNAME

# Create subnets if they do not already exist
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNETNAME | grep "${SUBNET_EXTERNAL}" 2> /dev/null)" = "" ]; then
    echo -e "${RED}Creating subnet ${BLUE}$SUBNET_EXTERNAL${END}"
    az network vnet subnet create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNETNAME \
        --network-security-group $NSG_EXTERNAL \
        --address-prefix $IP_RANGE_EXTERNAL \
        --name $SUBNET_EXTERNAL
fi
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNETNAME | grep "${SUBNET_INTERNAL}" 2> /dev/null)" = "" ]; then
    echo -e "${RED}Creating subnet ${BLUE}$SUBNET_INTERNAL${END}"
    az network vnet subnet create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNETNAME \
        --network-security-group $NSG_INTERNAL \
        --address-prefix $IP_RANGE_INTERNAL \
        --name $SUBNET_INTERNAL
fi


# Set up PyPI external mirror
# ---------------------------
VMNAME_EXTERNAL="${VM_PREFIX_EXTERNAL}PyPI"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $VMNAME_EXTERNAL)" = "" ]; then
    CLOUDINITYAML="cloud-init-mirror-external-pypi.yaml"

    # Create the VM based off the selected source image
    echo -e "${RED}Creating VM ${BLUE}$VMNAME_EXTERNAL${RED} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"

    # Create the data disk
    echo -e "${RED}Creating 4TB datadisk${END}"
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
        --vnet-name $VNETNAME \
        --subnet $SUBNET_EXTERNAL \
        --name $VMNAME_EXTERNAL \
        --image $SOURCEIMAGE \
        --custom-data $CLOUDINITYAML \
        --admin-username atiadmin \
        --attach-data-disks $DISKNAME \
        --os-disk-name $OSDISKNAME \
        --nsg "" \
        --private-ip-address $PRIVATEIPADDRESS \
        --public-ip-address "" \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS
    echo -e "${RED}Deployed new ${BLUE}$VMNAME_EXTERNAL${RED} server${END}"
    # # Wait for the first stages of deployment to begin so that we can extract the ssh key
    # sleep 30
fi


# Set up CRAN external mirror
# ---------------------------
VMNAME_EXTERNAL="${VM_PREFIX_EXTERNAL}CRAN"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $VMNAME_EXTERNAL)" = "" ]; then
    CLOUDINITYAML="cloud-init-mirror-external-cran.yaml"

    # Create the VM based off the selected source image
    echo -e "${RED}Creating VM ${BLUE}$VMNAME_EXTERNAL${RED} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"

    # Create the data disk
    echo -e "${RED}Creating 4TB datadisk${END}"
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
        --vnet-name $VNETNAME \
        --subnet $SUBNET_EXTERNAL \
        --name $VMNAME_EXTERNAL \
        --image $SOURCEIMAGE \
        --custom-data $CLOUDINITYAML \
        --admin-username atiadmin \
        --attach-data-disks $DISKNAME \
        --os-disk-name $OSDISKNAME \
        --nsg "" \
        --private-ip-address $PRIVATEIPADDRESS \
        --public-ip-address "" \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS
    echo -e "${RED}Deployed new ${BLUE}$VMNAME_EXTERNAL${RED} server${END}"
    # # Wait for the first stages of deployment to begin so that we can extract the ssh key
    # sleep 30
fi


# Set up PyPI internal mirror
# ---------------------------
VMNAME_INTERNAL="${VM_PREFIX_INTERNAL}PyPI"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $VMNAME_INTERNAL)" = "" ]; then
    VMNAME_EXTERNAL="${VM_PREFIX_EXTERNAL}PyPI"

    # Construct a new cloud-init YAML file with the appropriate SSH key included
    BASECLOUDINITYAML="cloud-init-mirror-internal-pypi.yaml"
    CLOUDINITYAMLPREFIX=$(mktemp)
    CLOUDINITYAML="${CLOUDINITYAMLPREFIX}.yaml"
    rm $CLOUDINITYAMLPREFIX
    az vm run-command invoke --name $VMNAME_EXTERNAL --resource-group $RESOURCEGROUP --command-id RunShellScript --scripts "cat /home/mirrordaemon/.ssh/id_rsa.pub" --query "value[0].message" | cut -d'\' -f3 | sed "s/^n//" > external_key.pub
    sed -e "s|EXTERNAL_SSH_KEY_PLACEHOLDER|$(cat external_key.pub)|" $BASECLOUDINITYAML > $CLOUDINITYAML
    rm external_key.pub

    # Create the VM based off the selected source image, opening port 443 for the webserver
    echo -e "${RED}Creating VM ${BLUE}$VMNAME_INTERNAL${RED} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"

    # Create the data disk
    echo -e "${RED}Creating 4TB datadisk${END}"
    DISKNAME=${VMNAME_INTERNAL}_DATADISK
    az disk create \
        --resource-group $RESOURCEGROUP \
        --name $DISKNAME \
        --size-gb 4095 \
        --location $LOCATION

    echo -e "${RED}Creating VM...${END}"
    OSDISKNAME=${VMNAME_INTERNAL}_OSDISK
    PRIVATEIPADDRESS=${IP_TRIPLET_INTERNAL}.4
    az vm create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNETNAME \
        --subnet $SUBNET_INTERNAL \
        --name $VMNAME_INTERNAL \
        --image $SOURCEIMAGE \
        --custom-data $CLOUDINITYAML \
        --admin-username atiadmin \
        --attach-data-disks $DISKNAME \
        --os-disk-name $OSDISKNAME \
        --nsg "" \
        --private-ip-address $PRIVATEIPADDRESS \
        --public-ip-address "" \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS
    echo -e "${RED}Deployed new ${BLUE}$VMNAME_INTERNAL${RED} server${END}"

    # Update known hosts on the external server to allow connections to the internal server
    echo -e "Update known hosts on ${BLUE}$VMNAME_EXTERNAL${END} to allow connections to ${BLUE}$VMNAME_INTERNAL${END}"
    INTERNAL_HOSTS=$(az vm run-command invoke --name ${VMNAME_INTERNAL} --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "ssh-keyscan 127.0.0.1 2> /dev/null" --query "value[0].message" -o tsv | grep "^127.0.0.1" | sed "s/127.0.0.1/${PRIVATEIPADDRESS}/")
    az vm run-command invoke --name $VMNAME_EXTERNAL --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "echo \"$INTERNAL_HOSTS\" > ~mirrordaemon/.ssh/known_hosts; ls -alh ~mirrordaemon/.ssh/known_hosts; ssh-keygen -H -f ~mirrordaemon/.ssh/known_hosts; chown mirrordaemon:mirrordaemon ~mirrordaemon/.ssh/known_hosts; rm ~mirrordaemon/.ssh/known_hosts.old"
    echo -e "${RED}Finished updating ${BLUE}$VMNAME_EXTERNAL${END}"
fi

# Set up CRAN internal mirror
# ---------------------------
VMNAME_INTERNAL="${VM_PREFIX_INTERNAL}CRAN"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $VMNAME_INTERNAL)" = "" ]; then
    VMNAME_EXTERNAL="${VM_PREFIX_EXTERNAL}CRAN"
    # Construct a new cloud-init YAML file with the appropriate SSH key included
    BASECLOUDINITYAML="cloud-init-mirror-internal-cran.yaml"
    CLOUDINITYAMLPREFIX=$(mktemp)
    CLOUDINITYAML="${CLOUDINITYAMLPREFIX}.yaml"
    rm $CLOUDINITYAMLPREFIX
    az vm run-command invoke --name $VMNAME_EXTERNAL --resource-group $RESOURCEGROUP --command-id RunShellScript --scripts "cat /home/mirrordaemon/.ssh/id_rsa.pub" --query "value[0].message" | cut -d'\' -f3 | sed "s/^n//" > external_key.pub
    sed -e "s|EXTERNAL_SSH_KEY_PLACEHOLDER|$(cat external_key.pub)|" $BASECLOUDINITYAML > $CLOUDINITYAML
    rm external_key.pub

    # Create the VM based off the selected source image, opening port 443 for the webserver
    echo -e "${RED}Creating VM ${BLUE}$VMNAME_INTERNAL${RED} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${RED}This will be based off the ${BLUE}$SOURCEIMAGE${RED} image${END}"

    # Create the data disk
    echo -e "${RED}Creating 4TB datadisk${END}"
    DISKNAME=${VMNAME_INTERNAL}_DATADISK
    az disk create \
        --resource-group $RESOURCEGROUP \
        --name $DISKNAME \
        --size-gb 4095 \
        --location $LOCATION

    echo -e "${RED}Creating VM...${END}"
    OSDISKNAME=${VMNAME_INTERNAL}_OSDISK
    PRIVATEIPADDRESS=${IP_TRIPLET_INTERNAL}.5
    az vm create \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNETNAME \
        --subnet $SUBNET_INTERNAL \
        --name $VMNAME_INTERNAL \
        --image $SOURCEIMAGE \
        --custom-data $CLOUDINITYAML \
        --admin-username atiadmin \
        --attach-data-disks $DISKNAME \
        --os-disk-name $OSDISKNAME \
        --nsg "" \
        --private-ip-address $PRIVATEIPADDRESS \
        --public-ip-address "" \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS
    echo -e "${RED}Deployed new ${BLUE}$VMNAME_INTERNAL${RED} server${END}"

    # Update known hosts on the external server to allow connections to the internal server
    echo -e "Update known hosts on ${BLUE}$VMNAME_EXTERNAL${END} to allow connections to ${BLUE}$VMNAME_INTERNAL${END}"
    INTERNAL_HOSTS=$(az vm run-command invoke --name ${VMNAME_INTERNAL} --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "ssh-keyscan 127.0.0.1 2> /dev/null" --query "value[0].message" -o tsv | grep "^127.0.0.1" | sed "s/127.0.0.1/${PRIVATEIPADDRESS}/")
    az vm run-command invoke --name $VMNAME_EXTERNAL --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "echo \"$INTERNAL_HOSTS\" > ~mirrordaemon/.ssh/known_hosts; ssh-keygen -H -f ~mirrordaemon/.ssh/known_hosts; chown mirrordaemon:mirrordaemon ~mirrordaemon/.ssh/known_hosts; rm ~mirrordaemon/.ssh/known_hosts.old"
    echo -e "${RED}Finished updating ${BLUE}$VMNAME_EXTERNAL${END}"
fi
