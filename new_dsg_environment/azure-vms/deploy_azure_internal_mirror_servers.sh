#! /bin/bash

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# Options which are configurable at the command line
# IP_TRIPLET_INTERNAL="10.1.1"
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
    echo "usage: $0 [-h] -s subscription [-k keyvault_name] [-r resource_group] [-x name_suffix]"
    echo "  -h                           display help"
    echo "  -s subscription [required]   specify subscription where the mirror servers should be deployed. (Test using 'Safe Haven Management Testing')"
    echo "  -k keyvault_name             specify name for keyvault that already contains admin passwords for the mirror servers (defaults to '${KEYVAULT_NAME}')"
    echo "  -r resource_group            specify resource group that contains the external mirror servers (defaults to '${RESOURCEGROUP}')"
    echo "  -x name_suffix               specify (optional) suffix that will be used to distinguish these internal mirror servers from any others (defaults to '${NAME_SUFFIX}')"
    exit 1
}


# Read command line arguments, overriding defaults where necessary
# ----------------------------------------------------------------
while getopts "hk:r:s:x:" opt; do
    case $opt in
        h)
            print_usage_and_exit
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
SUBNET_INTERNAL="$(echo $SUBNET_EXTERNAL | sed 's/EXTERNAL/INTERNAL/')"
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
if [ "$(az keyvault list --resource-group $RESOURCEGROUP --query "[].name" -o tsv)" != "$KEYVAULT_NAME" ]; then
    echo -e "${RED}Keyvault ${BLUE}$KEYVAULT_NAME${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi

# Ensure that VNet exists
if [ "$(az network vnet list --resource-group $RESOURCEGROUP --query "[].name" -o tsv)" != "$VNET_NAME" ]; then
    echo -e "${RED}VNet ${BLUE}$VNET_NAME${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi
IP_TRIPLET_VNET=$(az network vnet show --resource-group $RESOURCEGROUP --name $VNET_NAME --query "addressSpace.addressPrefixes" -o tsv | cut -d'.' -f1-3)
IP_RANGE_SBNT_EXTERNAL="${IP_TRIPLET_VNET}.0/28"

# Ensure that external NSG exists
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSG_EXTERNAL 2> /dev/null)" = "" ]; then
    echo -e "${RED}External NSG ${BLUE}$NSG_EXTERNAL${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi

# Ensure that external subnet exists
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNET_NAME --query "[].name" -o tsv)" != "$SUBNET_EXTERNAL" ]; then
    echo -e "${RED}External subnet ${BLUE}$SUBNET_EXTERNAL${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi


# Find the next valid IP range for this subnet
# --------------------------------------------
IP_ADDRESS_PREFIXES=$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNET_NAME --query "[].addressPrefix" -o tsv)
for FOURTH_OCTET in $(seq 0 16 240); do
    IP_RANGE_SUBNET_INTERNAL="${IP_TRIPLET_VNET}.${FOURTH_OCTET}/28"
    ALREADY_IN_USE=0
    for IP_ADDRESS_PREFIX in $IP_ADDRESS_PREFIXES; do
        if [ "$IP_RANGE_SUBNET_INTERNAL" == "$IP_ADDRESS_PREFIX" ]; then
            ALREADY_IN_USE=1
        fi
    done
    if [ $ALREADY_IN_USE -eq 0 ]; then
        break
    fi
done
if [ $ALREADY_IN_USE -eq 0 ]; then
    echo -e "${BOLD}Internal mirrors will be deployed in the IP range ${BLUE}$IP_RANGE_SUBNET_INTERNAL${END}"
else
    echo -e "${RED}Could not find a valid, unused IP range in ${BLUE}$VNET_NAME${END}"
    print_usage_and_exit
fi


# Set up the internal NSG and configure the external NSG
# ------------------------------------------------------
# Update external NSG to allow connections to this IP range
echo -e "${BOLD}Updating NSG ${BLUE}$NSG_EXTERNAL${END}${BOLD} to allow connections to IP range ${BLUE}$IP_RANGE_SUBNET_INTERNAL${END}"
# ... if rsync rules do not exist then we create them
if [ "$(az network nsg rule show --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --name rsyncOutbound 2> /dev/null)" = "" ]; then
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name rsyncOutbound --description "Allow ports 22 and 873 for rsync" --source-address-prefixes $IP_RANGE_SBNT_EXTERNAL --destination-port-ranges 22 873 --protocol TCP --destination-address-prefixes $IP_RANGE_SUBNET_INTERNAL --priority 200
# ... otherwise we update them, extracting the existing IP ranges first
else
    EXISTING_IP_RANGES=$(az network nsg rule show --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --name rsyncOutbound --query "[destinationAddressPrefix, destinationAddressPrefixes]" -o tsv | xargs)
    az network nsg rule update --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --name rsyncOutbound --destination-address-prefixes $EXISTING_IP_RANGES $IP_RANGE_SUBNET_INTERNAL
fi

# Create internal NSG if it does not already exist
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSG_INTERNAL 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating NSG for internal mirrors: ${BLUE}$NSG_INTERNAL${END}"
    az network nsg create --resource-group $RESOURCEGROUP --name $NSG_INTERNAL
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Inbound --name rsyncInbound --description "Allow ports 22 and 873 for rsync" --source-address-prefixes $IP_RANGE_SBNT_EXTERNAL --destination-port-ranges 22 873 --protocol TCP --destination-address-prefixes "*" --priority 200
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Inbound --name mirrorRequestsInbound --description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for webservices" --source-address-prefixes VirtualNetwork --destination-port-ranges 80 443 3128 --protocol TCP --destination-address-prefixes "*" --priority 300
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Inbound --name IgnoreInboundRulesBelowHere --description "Deny all other inbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Outbound --name IgnoreOutboundRulesBelowHere --description "Deny all other outbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
fi


# Create internal subnet if it does not already exist
# ---------------------------------------------------
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNET_NAME | grep "${SUBNET_INTERNAL}" 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating subnet ${BLUE}$SUBNET_INTERNAL${END}"
    az network vnet subnet create \
        --address-prefix $IP_RANGE_SUBNET_INTERNAL \
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
        az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(head /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32)
    fi
    # Retrieve admin password from keyvault
    ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

    # Create the VM based off the selected source image, opening port 443 for the webserver
    echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME_INTERNAL${END}${BOLD} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${BOLD}This will be based off the ${BLUE}$SOURCEIMAGE${END}${BOLD} image${END}"

    # Create the data disk
    echo -e "${BOLD}Creating 4TB datadisk...${END}"
    DISKNAME=${MACHINENAME_INTERNAL}_DATADISK
    az disk create --resource-group $RESOURCEGROUP --name $DISKNAME --location $LOCATION --sku "Standard_LRS" --size-gb 4095

    # Find the next unused IP address in this subnet and temporarily allow outbound internet connections through the NSG from it
    PRIVATEIPADDRESS="$IP_TRIPLET_VNET.$(($(echo $IP_RANGE_SUBNET_INTERNAL | cut -d'/' -f1 | cut -d'.' -f4) + 4))"
    echo -e "${BOLD}Temporarily allowing outbound internet access from ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} in NSG ${BLUE}$NSG_INTERNAL${END}${BOLD} (for use during deployment *only*)${END}"
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Outbound --name configurationOutboundTemporary --description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for installing software" --access "Allow" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges 80 443 3128 --protocol TCP --destination-address-prefixes Internet --priority 100
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Outbound --name vnetOutboundTemporary --description "Block connections to the VNet" --access "Deny" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges "*" --protocol "*" --destination-address-prefixes VirtualNetwork --priority 200

    # Create the VM
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
        --subnet $SUBNET_INTERNAL \
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

    # Delete the configuration NSG rule and restart the VM
    echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME_INTERNAL}${END}"
    az network nsg rule delete --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --name configurationOutboundTemporary
    az network nsg rule delete --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --name vnetOutboundTemporary
    az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME_INTERNAL

    # Update known hosts on the external server to allow connections to the internal server
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
        az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(head /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32)
    fi
    # Retrieve admin password from keyvault
    ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

    # Create the VM based off the selected source image, opening port 443 for the webserver
    echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME_INTERNAL${END}${BOLD} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${BOLD}This will be based off the ${BLUE}$SOURCEIMAGE${END}${BOLD} image${END}"

    # Create the data disk
    echo -e "${BOLD}Creating 4TB datadisk...${END}"
    DISKNAME=${MACHINENAME_INTERNAL}_DATADISK
    az disk create --resource-group $RESOURCEGROUP --name $DISKNAME --location $LOCATION --sku "Standard_LRS" --size-gb 1023

    # Find the next unused IP address in this subnet and temporarily allow outbound internet connections through the NSG from it
    PRIVATEIPADDRESS="$IP_TRIPLET_VNET.$(($(echo $IP_RANGE_SUBNET_INTERNAL | cut -d'/' -f1 | cut -d'.' -f4) + 5))"
    echo -e "${BOLD}Temporarily allowing outbound internet access from ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} in NSG ${BLUE}$NSG_INTERNAL${END}${BOLD} (for use during deployment *only*)${END}"
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Outbound --name configurationOutboundTemporary --description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for installing software" --access "Allow" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges 80 443 3128 --protocol TCP --destination-address-prefixes Internet --priority 100
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Outbound --name vnetOutboundTemporary --description "Block connections to the VNet" --access "Deny" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges "*" --protocol "*" --destination-address-prefixes VirtualNetwork --priority 200

    # Create the VM
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
        --subnet $SUBNET_INTERNAL \
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

    # Delete the configuration NSG rule and restart the VM
    echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME_INTERNAL}${END}"
    az network nsg rule delete --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --name configurationOutboundTemporary
    az network nsg rule delete --resource-group $RESOURCEGROUP --nsg-name $NSG_INTERNAL --name vnetOutboundTemporary
    az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME_INTERNAL

    # Update known hosts on the external server to allow connections to the internal server
    echo -e "${BOLD}Update known hosts on ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} to allow connections to ${BLUE}$MACHINENAME_INTERNAL${END}"
    INTERNAL_HOSTS=$(az vm run-command invoke --name ${MACHINENAME_INTERNAL} --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "ssh-keyscan 127.0.0.1 2> /dev/null" --query "value[0].message" -o tsv | grep "^127.0.0.1" | sed "s/127.0.0.1/${PRIVATEIPADDRESS}/")
    az vm run-command invoke --name $MACHINENAME_EXTERNAL --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "echo \"$INTERNAL_HOSTS\" > ~mirrordaemon/.ssh/known_hosts; ls -alh ~mirrordaemon/.ssh/known_hosts; ssh-keygen -H -f ~mirrordaemon/.ssh/known_hosts; chown mirrordaemon:mirrordaemon ~mirrordaemon/.ssh/known_hosts; rm ~mirrordaemon/.ssh/known_hosts.old" --query "value[0].message" -o tsv

    # Update known IP addresses on the external server to schedule pushing to the internal server
    echo -e "${BOLD}Registering IP address ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} with ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} as the location of ${BLUE}$MACHINENAME_INTERNAL${END}"
    az vm run-command invoke --name $MACHINENAME_EXTERNAL --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "echo $PRIVATEIPADDRESS >> ~mirrordaemon/internal_mirror_ip_addresses.txt; ls -alh ~mirrordaemon/internal_mirror_ip_addresses.txt; cat ~mirrordaemon/internal_mirror_ip_addresses.txt" --query "value[0].message" -o tsv
    echo -e "${BOLD}Finished updating ${BLUE}$MACHINENAME_EXTERNAL${END}"
fi
