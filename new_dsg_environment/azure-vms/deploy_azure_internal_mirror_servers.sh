#! /bin/bash

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# Options which are configurable at the command line
IP_TRIPLET_INTERNAL="10.0.2"
KEYVAULT_NAME="kv-sh-pkg-mirrors" # must match what was used for the external mirrors
RESOURCEGROUP="RG_SH_PKG_MIRRORS"
SUBSCRIPTION="" # must be provided

# Other constants
ADMIN_USERNAME="atiadmin"
LOCATION="uksouth"
MACHINENAME_PREFIX_EXTERNAL="MirrorVMExternal"
NAME_SUFFIX=""
NSG_EXTERNAL="NSG_SH_PKG_MIRRORS_EXTERNAL"
SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"
SUBNET_EXTERNAL="SBNT_SH_PKG_MIRRORS_EXTERNAL"
VNET_NAME="VNET_SH_PKG_MIRRORS"

# Document usage for this script
# ------------------------------
print_usage_and_exit() {
    echo "usage: $0 [-h] -s subscription [-i internal_ip] [-k keyvault_name] [-r resource_group] [-x name_suffix]"
    echo "  -h                           display help"
    echo "  -s subscription [required]   specify subscription where the mirror servers should be deployed. (Test using 'Safe Haven Management Testing')"
    echo "  -i internal_ip               specify initial IP triplet for internal mirror servers (defaults to '${IP_TRIPLET_INTERNAL}')"
    echo "  -k keyvault_name             specify name for keyvault that already contains admin passwords for the mirror servers (defaults to '${KEYVAULT_NAME}')"
    echo "  -r resource_group            specify resource group that contains the external mirror servers (defaults to '${RESOURCEGROUP}')"
    echo "  -x name_suffix               specify (optional) suffix that will be used to distinguish these internal mirror servers from any others (defaults to '${NAME_SUFFIX}')"
    exit 1
}


# Read command line arguments, overriding defaults where necessary
# ----------------------------------------------------------------
while getopts "hi:k:r:s:x:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        i)
            IP_TRIPLET_INTERNAL=$OPTARG
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
        x)
            NAME_SUFFIX=$OPTARG
            ;;
        \?)
            print_usage_and_exit
            ;;
    esac
done


# Setup internal names to match the external names
# ------------------------------------------------
NSG_INTERNAL="$(echo $NSG_EXTERNAL | sed 's/EXTERNAL/INTERNAL/')"
NSG_DEPLOYMENT="$(echo $NSG_EXTERNAL | sed 's/EXTERNAL/DEPLOYMENT/')"
SUBNET_INTERNAL="$(echo $SUBNET_EXTERNAL | sed 's/EXTERNAL/INTERNAL/')"
SUBNET_DEPLOYMENT="$(echo $SUBNET_EXTERNAL | sed 's/EXTERNAL/DEPLOYMENT/')"
MACHINENAME_PREFIX_INTERNAL="$(echo $MACHINENAME_PREFIX_EXTERNAL | sed 's/External/Internal/')"
# Add name suffix if needed
if [ "$NAME_SUFFIX" != "" ]; then
    SUBNET_INTERNAL="${SUBNET_INTERNAL}_${NAME_SUFFIX}"
    MACHINENAME_PREFIX_INTERNAL="${MACHINENAME_PREFIX_INTERNAL}${NAME_SUFFIX}"
fi


# Check that a subscription has been provided and switch to it
# ------------------------------------------------------------
if [ "$SUBSCRIPTION" = "" ]; then
    echo -e "${RED}Subscription is a required argument!${END}"
    print_usage_and_exit
fi
az account set --subscription "$SUBSCRIPTION"


# Ensure that the external mirrors have been set up
# -------------------------------------------------
# Ensure that resource group exists
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo -e "${RED}Resource group ${BLUE}$RESOURCEGROUP${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi

# Ensure that keyvault exists
if [ "$(az keyvault list --resource-group $RESOURCEGROUP | grep $KEYVAULT_NAME)" = "" ]; then
    echo -e "${RED}Keyvault ${BLUE}$KEYVAULT_NAME${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi

# Ensure that VNet exists
if [ "$(az network vnet list -g $RESOURCEGROUP | grep $VNET_NAME)" = "" ]; then
    echo -e "${RED}VNet ${BLUE}$VNET_NAME${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi

# Ensure that deployment NSG exists
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSG_DEPLOYMENT 2> /dev/null)" = "" ]; then
    echo -e "${RED}Deployment NSG ${BLUE}$NSG_DEPLOYMENT${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi

# Ensure that external NSG exists
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSG_EXTERNAL 2> /dev/null)" = "" ]; then
    echo -e "${RED}External NSG ${BLUE}$NSG_EXTERNAL${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi

# Ensure that deployment subnet exists
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNET_NAME | grep "${SUBNET_DEPLOYMENT}" 2> /dev/null)" = "" ]; then
    echo -e "${RED}Deployment subnet ${BLUE}$SUBNET_DEPLOYMENT${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi

# Ensure that external subnet exists
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNET_NAME | grep "${SUBNET_EXTERNAL}" 2> /dev/null)" = "" ]; then
    echo -e "${RED}External subnet ${BLUE}$SUBNET_EXTERNAL${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi


# Construct and validate IP ranges
# --------------------------------
# Validate triplet against IP ranges set during external mirror deployment
for EXISTING_IP_RANGE in $(az network vnet show --resource-group $RESOURCEGROUP --name $VNET_NAME --query "subnets[].addressPrefix" -o tsv); do
    EXISTING_IP_TRIPLET=$(echo $EXISTING_IP_RANGE | cut -d'.' -f1-3)
    if [ "$IP_TRIPLET_INTERNAL" = "$EXISTING_IP_TRIPLET" ]; then
        echo -e "${RED}IP triplet ${BLUE}$IP_TRIPLET_INTERNAL${BOLD} is already in use!${END}"
        print_usage_and_exit
    fi
done
IP_RANGE_INTERNAL="${IP_TRIPLET_INTERNAL}.0/24"
IP_RANGE_EXTERNAL=$(az network vnet subnet show --resource-group $RESOURCEGROUP --vnet-name $VNET_NAME --name $SUBNET_EXTERNAL --query "addressPrefix" | xargs)
IP_RANGE_DEPLOYMENT=$(az network vnet subnet show --resource-group $RESOURCEGROUP --vnet-name $VNET_NAME --name $SUBNET_DEPLOYMENT --query "addressPrefix" | xargs)
echo -e "${BOLD}Will deploy internal mirrors in the IP range ${BLUE}$IP_RANGE_DEPLOYMENT${END}${BOLD} before moving them to ${BLUE}$IP_RANGE_INTERNAL${END}"


# Set up the internal NSG and configure the external NSG
# ------------------------------------------------------
# Update external NSG to allow connections to this IP range
echo -e "${BOLD}Updating NSG ${BLUE}$NSG_EXTERNAL${END}${BOLD} to allow connections to IP range ${BLUE}$IP_RANGE_INTERNAL${END}"
# ... if rsync rules do not exist then we create them
if [ "$(az network nsg rule show --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --name rsyncInbound 2> /dev/null)" = "" ]; then
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Inbound --name rsyncInbound --description "Allow ports 22 and 873 for rsync" --source-address-prefixes $IP_RANGE_INTERNAL --destination-port-ranges 22 873 --protocol TCP --destination-address-prefixes $IP_RANGE_EXTERNAL --priority 200
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name rsyncOutbound --description "Allow ports 22 and 873 for rsync" --source-address-prefixes $IP_RANGE_EXTERNAL --destination-port-ranges 22 873 --protocol TCP --destination-address-prefixes $IP_RANGE_INTERNAL --priority 200
# ... otherwise we update them, extracting the existing IP ranges first
else
    EXISTING_IP_RANGES=$(az network nsg rule show --resource-group RG_SH_PKG_MIRRORS --nsg-name NSG_SH_PKG_MIRRORS_EXTERNAL --name rsyncInbound --query "[sourceAddressPrefix, sourceAddressPrefixes]" -o tsv | xargs)
    az network nsg rule update --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --name rsyncOutbound --destination-address-prefixes $EXISTING_IP_RANGES $IP_RANGE_INTERNAL
fi

# Create internal NSG if it does not already exist
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSG_INTERNAL 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating NSG for internal mirrors: ${BLUE}$NSG_INTERNAL${END}"
    az network nsg create --resource-group $RESOURCEGROUP --name $NSG_INTERNAL
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Inbound --name rsyncInbound --description "Allow ports 22 and 873 for rsync" --source-address-prefixes $IP_RANGE_EXTERNAL --destination-port-ranges 22 873 --protocol TCP --destination-address-prefixes "*" --priority 200
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Inbound --name httpInbound --description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for webservices" --source-address-prefixes VirtualNetwork --destination-port-ranges 80 443 3128 --protocol TCP --destination-address-prefixes "*" --priority 300
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Inbound --name DenyAllInbound --description "Deny all other inbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Outbound --name DenyAllOutbound --description "Deny all other outbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
fi


# Create internal subnet if it does not already exist
# ---------------------------------------------------
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNET_NAME | grep "${SUBNET_INTERNAL}" 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating subnet ${BLUE}$SUBNET_INTERNAL${END}"
    az network vnet subnet create \
        --address-prefix $IP_RANGE_INTERNAL \
        --name $SUBNET_INTERNAL \
        --network-security-group $NSG_INTERNAL \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNET_NAME
fi

# Set up PyPI internal mirror
# ---------------------------
MACHINENAME_INTERNAL="${MACHINENAME_PREFIX_INTERNAL}PyPI"
MACHINENAME_EXTERNAL="${MACHINENAME_PREFIX_EXTERNAL}PyPI"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $MACHINENAME_INTERNAL)" = "" ]; then
    CLOUDINITYAML="cloud-init-mirror-internal-pypi.yaml"
    ADMIN_PASSWORD_SECRET_NAME="vm-admin-password-internal-pypi"
    if [ "$NAME_SUFFIX" != "" ]; then
        ADMIN_PASSWORD_SECRET_NAME="${ADMIN_PASSWORD_SECRET_NAME}-${NAME_SUFFIX}"
    fi

    # Construct a new cloud-init YAML file with the appropriate SSH key included
    TMPCLOUDINITYAML="$(mktemp).yaml"
    EXTERNAL_PUBLIC_SSH_KEY=$(az vm run-command invoke --name $MACHINENAME_EXTERNAL --resource-group $RESOURCEGROUP --command-id RunShellScript --scripts "cat /home/mirrordaemon/.ssh/id_rsa.pub" --query "value[0].message" -o tsv | grep "^ssh")
    sed -e "s|EXTERNAL_PUBLIC_SSH_KEY|${EXTERNAL_PUBLIC_SSH_KEY}|" $CLOUDINITYAML > $TMPCLOUDINITYAML

    # Ensure that admin password is available
    if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
        echo -e "${BOLD}Creating admin password for ${BLUE}$MACHINENAME_INTERNAL${END}"
        az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(date +%s | sha256sum | base64 | head -c 32)
    fi
    # Retrieve admin password from keyvault
    ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

    # Create the VM based off the selected source image, opening port 443 for the webserver
    echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME_INTERNAL${END}${BOLD} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${BOLD}This will be based off the ${BLUE}$SOURCEIMAGE${BOLD} image${END}"

    # Create the data disk
    echo -e "${BOLD}Creating 4TB datadisk...${END}"
    DISKNAME=${MACHINENAME_INTERNAL}_DATADISK
    az disk create \
        --location $LOCATION \
        --name $DISKNAME \
        --resource-group $RESOURCEGROUP \
        --size-gb 4095

    echo -e "${BOLD}Creating VM...${END}"
    OSDISKNAME=${MACHINENAME_INTERNAL}_OSDISK
    az vm create \
        --admin-password $ADMIN_PASSWORD \
        --admin-username $ADMIN_USERNAME \
        --attach-data-disks $DISKNAME \
        --authentication-type password \
        --custom-data $TMPCLOUDINITYAML \
        --image $SOURCEIMAGE \
        --name $MACHINENAME_INTERNAL \
        --nsg "" \
        --os-disk-name $OSDISKNAME \
        --public-ip-address "" \
        --resource-group $RESOURCEGROUP \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS \
        --subnet $SUBNET_DEPLOYMENT \
        --vnet-name $VNET_NAME
    rm $TMPCLOUDINITYAML
    echo -e "${BOLD}Deployed new ${BLUE}$MACHINENAME_INTERNAL${END}${BOLD} server${END}"

    # Poll VM to see whether it has finished running
    echo -e "${BOLD}Waiting for VM setup to finish (this may take several minutes)...${END}"
    while true; do
        POLL=$(az vm get-instance-view --resource-group $RESOURCEGROUP --name $MACHINENAME_INTERNAL --query "instanceView.statuses[?code == 'PowerState/running'].displayStatus")
        if [ "$(echo $POLL | grep 'VM running')" == "" ]; then break; fi
        sleep 10
    done

    # Switch NSG and restart
    PRIVATEIPADDRESS=${IP_TRIPLET_INTERNAL}.4
    echo -e "${BOLD}Switching to secure subnet: ${BLUE}${SUBNET_INTERNAL}${END}"
    NIC_NAME="${MACHINENAME_INTERNAL}VMNic"
    az network nic ip-config update --resource-group $RESOURCEGROUP --nic-name $NIC_NAME --name "ipconfig${MACHINENAME_INTERNAL}" --subnet $SUBNET_INTERNAL --vnet-name $VNET_NAME  --private-ip-address $PRIVATEIPADDRESS
    echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME_INTERNAL}${END}"
    az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME_INTERNAL

    # Update known hosts on the external server to allow connections to the internal server
    # PRIVATEIPADDRESS=$(az vm list-ip-addresses --resource-group $RESOURCEGROUP --name $MACHINENAME_INTERNAL --query "[].virtualMachine.network.privateIpAddresses[]" -o tsv)
    echo -e "${BOLD}Update known hosts on ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} to allow connections to ${BLUE}$MACHINENAME_INTERNAL${END}"
    INTERNAL_HOSTS=$(az vm run-command invoke --name ${MACHINENAME_INTERNAL} --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "ssh-keyscan 127.0.0.1 2> /dev/null" --query "value[0].message" -o tsv | grep "^127.0.0.1" | sed "s/127.0.0.1/${PRIVATEIPADDRESS}/")
    az vm run-command invoke --name $MACHINENAME_EXTERNAL --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "echo \"$INTERNAL_HOSTS\" > ~mirrordaemon/.ssh/known_hosts; ls -alh ~mirrordaemon/.ssh/known_hosts; ssh-keygen -H -f ~mirrordaemon/.ssh/known_hosts; chown mirrordaemon:mirrordaemon ~mirrordaemon/.ssh/known_hosts; rm ~mirrordaemon/.ssh/known_hosts.old" --query "value[0].message" -o tsv

    # Update known IP addresses on the external server to schedule pushing to the internal server
    echo -e "${BOLD}Registering IP address ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} with ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} as the location of ${BLUE}$MACHINENAME_INTERNAL${END}"
    az vm run-command invoke --name $MACHINENAME_EXTERNAL --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "echo $PRIVATEIPADDRESS >> ~mirrordaemon/internal_mirror_ip_addresses.txt; ls -alh ~mirrordaemon/internal_mirror_ip_addresses.txt; cat ~mirrordaemon/internal_mirror_ip_addresses.txt" --query "value[0].message" -o tsv
    echo -e "${BOLD}Finished updating ${BLUE}$MACHINENAME_EXTERNAL${END}"
fi


# Set up CRAN internal mirror
# ---------------------------
MACHINENAME_INTERNAL="${MACHINENAME_PREFIX_INTERNAL}CRAN"
MACHINENAME_EXTERNAL="${MACHINENAME_PREFIX_EXTERNAL}CRAN"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $MACHINENAME_INTERNAL)" = "" ]; then
    CLOUDINITYAML="cloud-init-mirror-internal-cran.yaml"
    ADMIN_PASSWORD_SECRET_NAME="vm-admin-password-internal-cran"
    if [ "$NAME_SUFFIX" != "" ]; then
        ADMIN_PASSWORD_SECRET_NAME="${ADMIN_PASSWORD_SECRET_NAME}-${NAME_SUFFIX}"
    fi

    # Construct a new cloud-init YAML file with the appropriate SSH key included
    TMPCLOUDINITYAML="$(mktemp).yaml"
    EXTERNAL_PUBLIC_SSH_KEY=$(az vm run-command invoke --name $MACHINENAME_EXTERNAL --resource-group $RESOURCEGROUP --command-id RunShellScript --scripts "cat /home/mirrordaemon/.ssh/id_rsa.pub" --query "value[0].message" -o tsv | grep "^ssh")
    sed -e "s|EXTERNAL_PUBLIC_SSH_KEY|${EXTERNAL_PUBLIC_SSH_KEY}|" $CLOUDINITYAML > $TMPCLOUDINITYAML

    # Ensure that admin password is available
    if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
        echo -e "${BOLD}Creating admin password for ${BLUE}$MACHINENAME_INTERNAL${END}"
        az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(date +%s | sha256sum | base64 | head -c 32)
    fi
    # Retrieve admin password from keyvault
    ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

    # Create the VM based off the selected source image, opening port 443 for the webserver
    echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME_INTERNAL${BOLD} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${BOLD}This will be based off the ${BLUE}$SOURCEIMAGE${END}${BOLD} image${END}"

    # Create the data disk
    echo -e "${BOLD}Creating 4TB datadisk...${END}"
    DISKNAME=${MACHINENAME_INTERNAL}_DATADISK
    az disk create \
        --location $LOCATION \
        --name $DISKNAME \
        --resource-group $RESOURCEGROUP \
        --size-gb 4095

    echo -e "${BOLD}Creating VM...${END}"
    OSDISKNAME=${MACHINENAME_INTERNAL}_OSDISK
    az vm create \
        --admin-password $ADMIN_PASSWORD \
        --admin-username $ADMIN_USERNAME \
        --attach-data-disks $DISKNAME \
        --authentication-type password \
        --custom-data $TMPCLOUDINITYAML \
        --image $SOURCEIMAGE \
        --name $MACHINENAME_INTERNAL \
        --nsg "" \
        --os-disk-name $OSDISKNAME \
        --public-ip-address "" \
        --resource-group $RESOURCEGROUP \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS \
        --subnet $SUBNET_DEPLOYMENT \
        --vnet-name $VNET_NAME
    rm $TMPCLOUDINITYAML
    echo -e "${BOLD}Deployed new ${BLUE}$MACHINENAME_INTERNAL${END}${BOLD} server${END}"

    # Poll VM to see whether it has finished running
    echo -e "${BOLD}Waiting for VM setup to finish (this may take several minutes)...${END}"
    while true; do
        POLL=$(az vm get-instance-view --resource-group $RESOURCEGROUP --name $MACHINENAME_INTERNAL --query "instanceView.statuses[?code == 'PowerState/running'].displayStatus")
        if [ "$(echo $POLL | grep 'VM running')" == "" ]; then break; fi
        sleep 10
    done

    # Switch NSG and restart
    PRIVATEIPADDRESS=${IP_TRIPLET_INTERNAL}.5
    echo -e "${BOLD}Switching to secure subnet: ${BLUE}${SUBNET_INTERNAL}${END}"
    NIC_NAME="${MACHINENAME_INTERNAL}VMNic"
    az network nic ip-config update --resource-group $RESOURCEGROUP --nic-name $NIC_NAME --name "ipconfig${MACHINENAME_INTERNAL}" --subnet $SUBNET_INTERNAL --vnet-name $VNET_NAME  --private-ip-address $PRIVATEIPADDRESS
    echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME_INTERNAL}${END}"
    az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME_INTERNAL

    # Update known hosts on the external server to allow connections to the internal server
    # PRIVATEIPADDRESS=$(az vm list-ip-addresses --resource-group $RESOURCEGROUP --name $MACHINENAME_INTERNAL --query "[].virtualMachine.network.privateIpAddresses[]" -o tsv)
    echo -e "${BOLD}Update known hosts on ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} to allow connections to ${BLUE}$MACHINENAME_INTERNAL${END}"
    INTERNAL_HOSTS=$(az vm run-command invoke --name ${MACHINENAME_INTERNAL} --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "ssh-keyscan 127.0.0.1 2> /dev/null" --query "value[0].message" -o tsv | grep "^127.0.0.1" | sed "s/127.0.0.1/${PRIVATEIPADDRESS}/")
    az vm run-command invoke --name $MACHINENAME_EXTERNAL --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "echo \"$INTERNAL_HOSTS\" > ~mirrordaemon/.ssh/known_hosts; ls -alh ~mirrordaemon/.ssh/known_hosts; ssh-keygen -H -f ~mirrordaemon/.ssh/known_hosts; chown mirrordaemon:mirrordaemon ~mirrordaemon/.ssh/known_hosts; rm ~mirrordaemon/.ssh/known_hosts.old" --query "value[0].message" -o tsv

    # Update known IP addresses on the external server to schedule pushing to the internal server
    echo -e "${BOLD}Registering IP address ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} with ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} as the location of ${BLUE}$MACHINENAME_INTERNAL${END}"
    az vm run-command invoke --name $MACHINENAME_EXTERNAL --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "echo $PRIVATEIPADDRESS >> ~mirrordaemon/internal_mirror_ip_addresses.txt; ls -alh ~mirrordaemon/internal_mirror_ip_addresses.txt; cat ~mirrordaemon/internal_mirror_ip_addresses.txt" --query "value[0].message" -o tsv
    echo -e "${BOLD}Finished updating ${BLUE}$MACHINENAME_EXTERNAL${END}"
fi
