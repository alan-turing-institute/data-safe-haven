#! /bin/bash

# Load common constants and options
source ${BASH_SOURCE%/*}/configs/mirrors.sh
source ${BASH_SOURCE%/*}/configs/text.sh

# Document usage for this script
# ------------------------------
print_usage_and_exit() {
    echo "usage: $0 [-h] -s subscription [-i vnet_ip] [-k keyvault_name] [-r resource_group] [-t tier]"
    echo "  -h                           display help"
    echo "  -s subscription [required]   specify subscription where the mirror servers should be deployed. (Test using 'Safe Haven Management Testing')"
    echo "  -k keyvault_name             specify (globally unique) name for keyvault that will be used to store admin passwords for the mirror servers (defaults to '${KEYVAULT_NAME}')"
    echo "  -r resource_group            specify resource group - will be created if it does not already exist (defaults to '${RESOURCEGROUP}')"
    echo "  -t tier                      specify which tier these mirrors will belong to, either '2' or '3' (defaults to '${TIER}')"
    exit 1
}


# Read command line arguments, overriding defaults where necessary
# ----------------------------------------------------------------
while getopts "hk:r:s:t:" opt; do
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
        t)
            TIER=$OPTARG
            ;;
        \?)
            print_usage_and_exit
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


# Check that Tier is either 2 or 3
# --------------------------------
if [ "$TIER" != "2" ] && [ "$TIER" != "3" ]; then
    echo -e "${RED}Tier must be either '2' or '3'${END}"
    print_usage_and_exit
fi


# Set tier-dependent variables
# ----------------------------
MACHINENAME_PREFIX="Tier${TIER}External${MACHINENAME_BASE}"
NSG_EXTERNAL="${NSG_PREFIX}_EXTERNAL_TIER${TIER}"
SUBNET_EXTERNAL="${SUBNET_PREFIX}_EXTERNAL_TIER${TIER}"
VNETNAME="${VNETNAME_PREFIX}_TIER${TIER}"
VNET_IPTRIPLET="10.20.${TIER}"


# Set datadisk size
# -----------------
if [ "$TIER" == "2" ]; then
    PYPIDATADISKSIZE=$DATADISK_LARGE
    PYPIDATADISKSIZEGB=$DATADISK_LARGE_NGB
    CRANDATADISKSIZE=$DATADISK_MEDIUM
    CRANDATADISKSIZEGB=$DATADISK_MEDIUM_NGB
elif [ "$TIER" == "3" ]; then
    PYPIDATADISKSIZE=$DATADISK_MEDIUM
    PYPIDATADISKSIZEGB=$DATADISK_MEDIUM_NGB
    CRANDATADISKSIZE=$DATADISK_SMALL
    CRANDATADISKSIZEGB=$DATADISK_SMALL_NGB
else
    print_usage_and_exit
fi


# Setup resource group if it does not already exist
# -------------------------------------------------------------------------
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo -e "${BOLD}Creating resource group ${BLUE}$RESOURCEGROUP${END}"
    az group create --name $RESOURCEGROUP --location $LOCATION
fi


# Create keyvault for storing passwords if it does not already exist
# ------------------------------------------------------------------
if [ "$(az keyvault list --resource-group $RESOURCEGROUP --query '[].name' -o tsv | grep $KEYVAULT_NAME)" != "$KEYVAULT_NAME" ]; then
    echo -e "${BOLD}Creating keyvault ${BLUE}$KEYVAULT_NAME${END}"
    az keyvault create --name $KEYVAULT_NAME --resource-group $RESOURCEGROUP --enabled-for-deployment true
    # Wait for DNS propagation of keyvault
    sleep 10
fi


# Set up the VNet as well as the subnet and NSG for external mirrors
# ------------------------------------------------------------------
# Define IP address ranges
IP_RANGE_VNET="${VNET_IPTRIPLET}.0/24"
IP_RANGE_SBNT_EXTERNAL="${VNET_IPTRIPLET}.0/28"

# Create VNet if it does not already exist
if [ "$(az network vnet list --resource-group $RESOURCEGROUP --query '[].name' -o tsv | grep $VNETNAME)" != "$VNETNAME" ]; then
    echo -e "${BOLD}Creating mirror VNet ${BLUE}$VNETNAME${END}${BOLD} using the IP range ${BLUE}$IP_RANGE_VNET${END}"
    az network vnet create --resource-group $RESOURCEGROUP --name $VNETNAME --address-prefixes $IP_RANGE_VNET --output none
fi

# Create external NSG if it does not already exist
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSG_EXTERNAL 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating NSG for external mirrors: ${BLUE}$NSG_EXTERNAL${END}"
    az network nsg create --resource-group $RESOURCEGROUP --name $NSG_EXTERNAL --output none
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Inbound --name IgnoreInboundRulesBelowHere --description "Deny all other inbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000 --output none
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name updateOutbound --description "Allow ports 443 (https) and 873 (unencrypted rsync) for updating mirrors" --access "Allow" --source-address-prefixes $IP_RANGE_SBNT_EXTERNAL --destination-port-ranges 443 873 --protocol TCP --destination-address-prefixes Internet --priority 300 --output none
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name IgnoreOutboundRulesBelowHere --description "Deny all other outbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000 --output none
fi

# Create external subnet if it does not already exist
if [ "$(az network vnet subnet show --resource-group $RESOURCEGROUP --vnet-name $VNETNAME --name $SUBNET_EXTERNAL --query 'name' -o tsv 2> /dev/null)" != "$SUBNET_EXTERNAL" ]; then
    echo -e "${BOLD}Creating subnet ${BLUE}$SUBNET_EXTERNAL${END}"
    az network vnet subnet create \
        --address-prefix $IP_RANGE_SBNT_EXTERNAL \
        --name $SUBNET_EXTERNAL \
        --network-security-group $NSG_EXTERNAL \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNETNAME \
        --output none
fi
echo -e "${BOLD}External tier-${TIER} mirrors will be deployed in the IP range ${BLUE}$IP_RANGE_SBNT_EXTERNAL${END}"


# Set up PyPI external mirror
# ---------------------------
MACHINENAME="${MACHINENAME_PREFIX}PyPI"
if [ "$(az vm show --resource-group $RESOURCEGROUP --name $MACHINENAME 2> /dev/null)" != "" ]; then
    echo -e "${BOLD}VM ${BLUE}$MACHINENAME${END}${BOLD} already exists in ${BLUE}$RESOURCEGROUP${END}"
else
    CLOUDINITYAML="${BASH_SOURCE%/*}/cloud-init-mirror-external-pypi.yaml"
    TIER3WHITELIST="${BASH_SOURCE%/*}/package_lists/tier3_pypi_whitelist.list"
    ADMIN_PASSWORD_SECRET_NAME="vm-admin-password-tier-${TIER}-external-pypi"

    # Make a temporary cloud-init file that we may alter
    TMP_CLOUDINITYAML="$(mktemp).yaml"
    cp $CLOUDINITYAML $TMP_CLOUDINITYAML

    # Apply whitelist if this is a Tier-3 mirror
    if [ "$TIER" == "3" ]; then
        # Indent whitelist by twelve spaces to match surrounding text
        TMP_WHITELIST="$(mktemp).list"
        cp $TIER3WHITELIST $TMP_WHITELIST
        sed -i -e 's/^/            /' $TMP_WHITELIST

        # Build cloud-config file
        sed -i -e "/; IF_WHITELIST_ENABLED packages =/ r ${TMP_WHITELIST}" $TMP_CLOUDINITYAML
        sed -i -e 's/; IF_WHITELIST_ENABLED //' $TMP_CLOUDINITYAML
        rm $TMP_WHITELIST
    fi

    # Ensure that admin password is available
    if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
        echo -e "${BOLD}Creating admin password for ${BLUE}$MACHINENAME${END}"
        az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(head /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32) --output none
    fi
    # Retrieve admin password from keyvault
    ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

    # Create the VM based off the selected source image
    echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME${END}${BOLD} in ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${BOLD}This will be based off the ${BLUE}$SOURCEIMAGE${END}${BOLD} image${END}"

    # Create the data disk
    echo -e "${BOLD}Creating ${PYPIDATADISKSIZE} datadisk...${END}"
    DISKNAME=${MACHINENAME}_DATADISK
    az disk create --resource-group $RESOURCEGROUP --name $DISKNAME --location $LOCATION --sku "Standard_LRS" --size-gb ${PYPIDATADISKSIZEGB} --output none

    # Temporarily allow outbound internet connections through the NSG from this IP address only
    PRIVATEIPADDRESS=${VNET_IPTRIPLET}.4
    echo -e "${BOLD}Temporarily allowing outbound internet access from ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} in NSG ${BLUE}$NSG_EXTERNAL${END}${BOLD} (for use during deployment *only*)${END}"
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name configurationOutboundTemporary --description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for installing software" --access "Allow" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges 80 443 3128 --protocol TCP --destination-address-prefixes Internet --priority 100 --output none
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name vnetOutboundTemporary --description "Block connections to the VNet" --access "Deny" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges "*" --protocol "*" --destination-address-prefixes VirtualNetwork --priority 150 --output none

    # Create the VM
    echo -e "${BOLD}Creating VM...${END}"
    OSDISKNAME=${MACHINENAME}_OSDISK
    az vm create \
        --admin-password $ADMIN_PASSWORD \
        --admin-username $ADMIN_USERNAME \
        --attach-data-disks $DISKNAME \
        --authentication-type password \
        --custom-data $TMP_CLOUDINITYAML \
        --image $SOURCEIMAGE \
        --name $MACHINENAME \
        --nsg "" \
        --os-disk-name $OSDISKNAME \
        --public-ip-address "" \
        --private-ip-address $PRIVATEIPADDRESS \
        --resource-group $RESOURCEGROUP \
        --size $MIRROR_VM_SIZE \
        --storage-sku $MIRROR_DISK_TYPE \
        --subnet $SUBNET_EXTERNAL \
        --vnet-name $VNETNAME \
        --output none
    echo -e "${BOLD}Deployed new ${BLUE}$MACHINENAME${END}${BOLD} server${END}"
    rm $TMP_CLOUDINITYAML

    # Poll VM to see whether it has finished running
    echo -e "${BOLD}Waiting for VM setup to finish (this may take several minutes)...${END}"
    while true; do
        POLL=$(az vm get-instance-view --resource-group $RESOURCEGROUP --name $MACHINENAME --query "instanceView.statuses[?code == 'PowerState/running'].displayStatus")
        if [ "$(echo $POLL | grep 'VM running')" == "" ]; then break; fi
        sleep 10
    done

    # Delete the configuration NSG rule and restart the VM
    echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME}${END}" --output none
    az network nsg rule delete --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --name configurationOutboundTemporary --output none
    az network nsg rule delete --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --name vnetOutboundTemporary --output none
    az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME --output none
fi


# Set up CRAN external mirror
# ---------------------------
if [ "$TIER" == "2" ]; then  # we do not support Tier-3 CRAN mirrors at present
    MACHINENAME="${MACHINENAME_PREFIX}CRAN"
    if [ "$(az vm show --resource-group $RESOURCEGROUP --name $MACHINENAME 2> /dev/null)" != "" ]; then
        echo -e "${BOLD}VM ${BLUE}$MACHINENAME${END}${BOLD} already exists in ${BLUE}$RESOURCEGROUP${END}"
    else
        CLOUDINITYAML="${BASH_SOURCE%/*}/cloud-init-mirror-external-cran.yaml"
        TIER3WHITELIST="${BASH_SOURCE%/*}/package_lists/tier3_cran_whitelist.list"
        ADMIN_PASSWORD_SECRET_NAME="vm-admin-password-tier-${TIER}-external-cran"

        # Make a temporary cloud-init file that we may alter
        TMP_CLOUDINITYAML="$(mktemp).yaml"
        cp $CLOUDINITYAML $TMP_CLOUDINITYAML

        # Apply whitelist if this is a Tier-3 mirror
        if [ "$TIER" == "3" ]; then
            # Build cloud-config file
            WHITELISTED_PACKAGES=$(cat $TIER3WHITELIST | tr '\n', ' ')
            sed -i -e "s/WHITELISTED_PACKAGES=/WHITELISTED_PACKAGES=\"${WHITELISTED_PACKAGES}\"/" $TMP_CLOUDINITYAML
            sed -i -e 's/# IF_WHITELIST_ENABLED //' $TMP_CLOUDINITYAML
        fi

        # Ensure that admin password is available
        if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
            echo -e "${BOLD}Creating admin password for ${BLUE}$MACHINENAME${END}"
            az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(head /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32) --output none
        fi
        # Retrieve admin password from keyvault
        ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

        # Create the VM based off the selected source image
        echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME${END}${BOLD} in ${BLUE}$RESOURCEGROUP${END}"
        echo -e "${BOLD}This will be based off the ${BLUE}$SOURCEIMAGE${END}${BOLD} image${END}"

        # Create the data disk
        echo -e "${BOLD}Creating ${CRANDATADISKSIZE} datadisk...${END}"
        DISKNAME=${MACHINENAME}_DATADISK
        az disk create --resource-group $RESOURCEGROUP --name $DISKNAME --location $LOCATION --sku "Standard_LRS" --size-gb ${CRANDATADISKSIZEGB} --output none

        # Temporarily allow outbound internet connections through the NSG from this IP address only
        PRIVATEIPADDRESS=${VNET_IPTRIPLET}.5
        echo -e "${BOLD}Temporarily allowing outbound internet access from ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} in NSG ${BLUE}$NSG_EXTERNAL${END}${BOLD} (for use during deployment *only*)${END}"
        az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name configurationOutboundTemporary --description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for installing software" --access "Allow" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges 80 443 3128 --protocol TCP --destination-address-prefixes Internet --priority 100 --output none
        az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name vnetOutboundTemporary --description "Block connections to the VNet" --access "Deny" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges "*" --protocol "*" --destination-address-prefixes VirtualNetwork --priority 200 --output none

        # Create the VM
        echo -e "${BOLD}Creating VM...${END}"
        OSDISKNAME=${MACHINENAME}_OSDISK
        az vm create \
            --admin-password $ADMIN_PASSWORD \
            --admin-username $ADMIN_USERNAME \
            --attach-data-disks $DISKNAME \
            --authentication-type password \
            --custom-data $TMP_CLOUDINITYAML \
            --image $SOURCEIMAGE \
            --name $MACHINENAME \
            --nsg "" \
            --os-disk-name $OSDISKNAME \
            --public-ip-address "" \
            --private-ip-address $PRIVATEIPADDRESS \
            --resource-group $RESOURCEGROUP \
            --size $MIRROR_VM_SIZE \
            --storage-sku $MIRROR_DISK_TYPE \
            --subnet $SUBNET_EXTERNAL \
            --vnet-name $VNETNAME \
            --output none
        echo -e "${BOLD}Deployed new ${BLUE}$MACHINENAME${END}${BOLD} server${END}"

        # Poll VM to see whether it has finished running
        echo -e "${BOLD}Waiting for VM setup to finish (this may take several minutes)...${END}"
        while true; do
            POLL=$(az vm get-instance-view --resource-group $RESOURCEGROUP --name $MACHINENAME --query "instanceView.statuses[?code == 'PowerState/running'].displayStatus")
            if [ "$(echo $POLL | grep 'VM running')" == "" ]; then break; fi
            sleep 10
        done

        # Delete the configuration NSG rule and restart the VM
        echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME}${END}"
        az network nsg rule delete --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --name configurationOutboundTemporary --output none
        az network nsg rule delete --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --name vnetOutboundTemporary --output none
        az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME --output none
    fi
fi
