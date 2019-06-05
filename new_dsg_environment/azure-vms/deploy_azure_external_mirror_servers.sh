#! /bin/bash

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

# Options which are configurable at the command line
IP_TRIPLET_VNET="10.1.0"
KEYVAULT_NAME="kv-shm-pkg-mirrors" # must be globally unique
RESOURCEGROUP="RG_SHM_PKG_MIRRORS"
SUBSCRIPTION="" # must be provided
TIER="2"

# Other constants
ADMIN_USERNAME="atiadmin"
LOCATION="uksouth"
MACHINENAME_PREFIX_EXTERNAL="ExternalMirror"
NSG_PREFIX_EXTERNAL="NSG_SHM_PKG_MIRRORS_EXTERNAL"
SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"
SUBNET_PREFIX_EXTERNAL="SBNT_SHM_PKG_MIRRORS_EXTERNAL"
VNETNAME_PREFIX="VNET_SHM_PKG_MIRRORS"


# Document usage for this script
# ------------------------------
print_usage_and_exit() {
    echo "usage: $0 [-h] -s subscription [-i vnet_ip] [-k keyvault_name] [-r resource_group] [-t tier]"
    echo "  -h                           display help"
    echo "  -s subscription [required]   specify subscription where the mirror servers should be deployed. (Test using 'Safe Haven Management Testing')"
    echo "  -i vnet_ip                   specify initial IP triplet for the mirror VNet (defaults to '${IP_TRIPLET_VNET}')"
    echo "  -k keyvault_name             specify (globally unique) name for keyvault that will be used to store admin passwords for the mirror servers (defaults to '${KEYVAULT_NAME}')"
    echo "  -r resource_group            specify resource group - will be created if it does not already exist (defaults to '${RESOURCEGROUP}')"
    echo "  -t tier                      specify which tier these mirrors will belong to, either '2' or '3' (defaults to '${TIER}')"
    exit 1
}


# Read command line arguments, overriding defaults where necessary
# ----------------------------------------------------------------
while getopts "hi:k:r:s:t:" opt; do
    case $opt in
        h)
            print_usage_and_exit
            ;;
        i)
            IP_TRIPLET_VNET=$OPTARG
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
VNETNAME="${VNETNAME_PREFIX}_TIER${TIER}"
SUBNET_EXTERNAL="${SUBNET_PREFIX_EXTERNAL}_TIER${TIER}"
MACHINENAME_PREFIX_EXTERNAL="Tier${TIER}${MACHINENAME_PREFIX_EXTERNAL}"
NSG_EXTERNAL="${NSG_PREFIX_EXTERNAL}_TIER${TIER}"

# Set datadisk size
# -----------------
if [ "$TIER" == "2" ]; then
    PYPIDATADISKSIZE="4TB"
    PYPIDATADISKSIZEGB="4095"
    CRANDATADISKSIZE="512GB"
    CRANDATADISKSIZEGB="511"
elif [ "$TIER" == "3" ]; then
    PYPIDATADISKSIZE="128GB"
    PYPIDATADISKSIZEGB="127"
    CRANDATADISKSIZE="128GB"
    CRANDATADISKSIZEGB="127"
else
    print_usage_and_exit
fi



CLOUDINITYAML="cloud-init-mirror-external-pypi.yaml"
TIER3WHITELIST="package_lists/tier3_pypi_whitelist.list"

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
    sed -i -e 's/; IF_WHITELIST_ENABLED //' $TMP_CLOUDINITYAML
    sed -i -e "/packages =/ r ${TMP_WHITELIST}" $TMP_CLOUDINITYAML
    # cat $TMP_WHITELIST
    rm $TMP_WHITELIST
    cat $TMP_CLOUDINITYAML
    print_usage_and_exit
fi


    # for RPACKAGE in $(cat package_lists/tier3_cran_whitelist.list)
# rsync -rtlzv --delete --dry-run --include="*/" --include="bin/linux/ubuntu/*/ztable*" --include="src/contrib/ztable*" --include "src/contrib/Archive/ztable/**" --include "web/packages/checks/check_results*ztable*" --include "web/dcmeta/ztable*" --include "web/packages/ztable/**" --exclude="*" cran.r-project.org::CRAN > mirror6.list

print_usage_and_exit


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


# Set up the VNet as well as the subnet and NSG for external mirrors
# ------------------------------------------------------------------
# Define IP address ranges
IP_RANGE_VNET="${IP_TRIPLET_VNET}.0/24"
IP_RANGE_SBNT_EXTERNAL="${IP_TRIPLET_VNET}.0/28"

# Create VNet if it does not already exist
if [ "$(az network vnet list -g $RESOURCEGROUP | grep $VNETNAME)" = "" ]; then
    echo -e "${BOLD}Creating mirror VNet ${BLUE}$VNETNAME${END}${BOLD} using the IP range ${BLUE}$IP_RANGE_VNET${END}"
    az network vnet create --resource-group $RESOURCEGROUP --name $VNETNAME --address-prefixes $IP_RANGE_VNET
fi

# Create external NSG if it does not already exist
if [ "$(az network nsg show --resource-group $RESOURCEGROUP --name $NSG_EXTERNAL 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating NSG for external mirrors: ${BLUE}$NSG_EXTERNAL${END}"
    az network nsg create --resource-group $RESOURCEGROUP --name $NSG_EXTERNAL
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Inbound --name IgnoreInboundRulesBelowHere --description "Deny all other inbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name updateOutbound --description "Allow ports 443 (https) and 873 (unencrypted rsync) for updating mirrors" --access "Allow" --source-address-prefixes $IP_RANGE_SBNT_EXTERNAL --destination-port-ranges 443 873 --protocol TCP --destination-address-prefixes Internet --priority 300
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name IgnoreOutboundRulesBelowHere --description "Deny all other outbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000
fi

# Create external subnet if it does not already exist
if [ "$(az network vnet subnet list --resource-group $RESOURCEGROUP --vnet-name $VNETNAME | grep "${SUBNET_EXTERNAL}" 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating subnet ${BLUE}$SUBNET_EXTERNAL${END}"
    az network vnet subnet create \
        --address-prefix $IP_RANGE_SBNT_EXTERNAL \
        --name $SUBNET_EXTERNAL \
        --network-security-group $NSG_EXTERNAL \
        --resource-group $RESOURCEGROUP \
        --vnet-name $VNETNAME
fi
echo -e "${BOLD}External tier ${TIER} mirrors will be deployed in the IP range ${BLUE}$IP_RANGE_SBNT_EXTERNAL${END}"


# Set up PyPI external mirror
# ---------------------------
MACHINENAME_EXTERNAL="${MACHINENAME_PREFIX_EXTERNAL}PyPI"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $MACHINENAME_EXTERNAL)" = "" ]; then
    CLOUDINITYAML="cloud-init-mirror-external-pypi.yaml"
    TIER3WHITELIST="package_lists/tier3_pypi_whitelist.ini"
    ADMIN_PASSWORD_SECRET_NAME="vm-admin-password-tier-${TIER}-external-pypi"

    # Make a temporary cloud-init file that we may alter
    TMP_CLOUDINITYAML="$(mktemp).yaml"
    cp $CLOUDINITYAML $TMP_CLOUDINITYAML

    # Apply whitelist if this is a Tier-3 mirror
    if [ "$TIER" == "3" ]; then
        # Indent whitelist by eight spaces to match surrounding text
        TMP_WHITELIST="$(mktemp).ini"
        cp $TIER3WHITELIST $TMP_WHITELIST
        sed -i -e 's/^/        /' $TMP_WHITELIST

        # ; To enable whitelisting both the [blacklist] and [whitelist] sections are needed
        # [blacklist]
        # plugins =
        #     whitelist_project

        # [whitelist]
        # packages =



        # Build cloud-config file
        sed -i -e 's/; IF_WHITELIST_ENABLED //' $TMP_CLOUDINITYAML
        sed -i -e "/@WHITELISTED_PACKAGES/ r ${TMP_WHITELIST}" $TMP_CLOUDINITYAML
        rm $TMP_WHITELIST
        cat $TMP_CLOUDINITYAML
        print_usage_and_exit
    fi

    # Ensure that admin password is available
    if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
        echo -e "${BOLD}Creating admin password for ${BLUE}$MACHINENAME_EXTERNAL${END}"
        az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(head /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32)
    fi
    # Retrieve admin password from keyvault
    ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

    # Create the VM based off the selected source image
    echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${BOLD}This will be based off the ${BLUE}$SOURCEIMAGE${END}${BOLD} image${END}"

    # Create the data disk
    echo -e "${BOLD}Creating ${PYPIDATADISKSIZE} datadisk...${END}"
    DISKNAME=${MACHINENAME_EXTERNAL}_DATADISK
    az disk create --resource-group $RESOURCEGROUP --name $DISKNAME --location $LOCATION --sku "Standard_LRS" --size-gb ${PYPIDATADISKSIZEGB}

    # Temporarily allow outbound internet connections through the NSG from this IP address only
    PRIVATEIPADDRESS=${IP_TRIPLET_VNET}.4
    echo -e "${BOLD}Temporarily allowing outbound internet access from ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} in NSG ${BLUE}$NSG_EXTERNAL${END}${BOLD} (for use during deployment *only*)${END}"
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name configurationOutboundTemporary --description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for installing software" --access "Allow" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges 80 443 3128 --protocol TCP --destination-address-prefixes Internet --priority 100
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name vnetOutboundTemporary --description "Block connections to the VNet" --access "Deny" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges "*" --protocol "*" --destination-address-prefixes VirtualNetwork --priority 200

    # Create the VM
    echo -e "${BOLD}Creating VM...${END}"
    OSDISKNAME=${MACHINENAME_EXTERNAL}_OSDISK
    az vm create \
        --admin-password $ADMIN_PASSWORD \
        --admin-username $ADMIN_USERNAME \
        --attach-data-disks $DISKNAME \
        --authentication-type password \
        --custom-data $TMP_CLOUDINITYAML \
        --image $SOURCEIMAGE \
        --name $MACHINENAME_EXTERNAL \
        --nsg "" \
        --os-disk-name $OSDISKNAME \
        --public-ip-address "" \
        --private-ip-address $PRIVATEIPADDRESS \
        --resource-group $RESOURCEGROUP \
        --size Standard_F4s_v2 \
        --storage-sku Standard_LRS \
        --subnet $SUBNET_EXTERNAL \
        --vnet-name $VNETNAME
    echo -e "${BOLD}Deployed new ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} server${END}"
    rm $TMP_CLOUDINITYAML

    # Poll VM to see whether it has finished running
    echo -e "${BOLD}Waiting for VM setup to finish (this may take several minutes)...${END}"
    while true; do
        POLL=$(az vm get-instance-view --resource-group $RESOURCEGROUP --name $MACHINENAME_EXTERNAL --query "instanceView.statuses[?code == 'PowerState/running'].displayStatus")
        if [ "$(echo $POLL | grep 'VM running')" == "" ]; then break; fi
        sleep 10
    done

    # Delete the configuration NSG rule and restart the VM
    echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME_EXTERNAL}${END}"
    az network nsg rule delete --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --name configurationOutboundTemporary
    az network nsg rule delete --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --name vnetOutboundTemporary
    az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME_EXTERNAL
fi


# Set up CRAN external mirror
# ---------------------------
MACHINENAME_EXTERNAL="${MACHINENAME_PREFIX_EXTERNAL}CRAN"
if [ "$(az vm list --resource-group $RESOURCEGROUP | grep $MACHINENAME_EXTERNAL)" = "" ]; then
    CLOUDINITYAML="cloud-init-mirror-external-cran.yaml"
    TIER3WHITELIST="package_lists/tier3_cran_whitelist.ini"
    ADMIN_PASSWORD_SECRET_NAME="vm-admin-password-tier-${TIER}-external-cran"

    # Ensure that admin password is available
    if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
        echo -e "${BOLD}Creating admin password for ${BLUE}$MACHINENAME_EXTERNAL${END}"
        az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(head /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32)
    fi
    # Retrieve admin password from keyvault
    ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

    # Create the VM based off the selected source image
    echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${BOLD}This will be based off the ${BLUE}$SOURCEIMAGE${END}${BOLD} image${END}"

    # Create the data disk
    echo -e "${BOLD}Creating ${CRANDATADISKSIZE} datadisk...${END}"
    DISKNAME=${MACHINENAME_EXTERNAL}_DATADISK
    az disk create --resource-group $RESOURCEGROUP --name $DISKNAME --location $LOCATION --sku "Standard_LRS" --size-gb ${CRANDATADISKSIZEGB}

    # Temporarily allow outbound internet connections through the NSG from this IP address only
    PRIVATEIPADDRESS=${IP_TRIPLET_VNET}.5
    echo -e "${BOLD}Temporarily allowing outbound internet access from ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} in NSG ${BLUE}$NSG_EXTERNAL${END}${BOLD} (for use during deployment *only*)${END}"
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name configurationOutboundTemporary --description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for installing software" --access "Allow" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges 80 443 3128 --protocol TCP --destination-address-prefixes Internet --priority 100
    az network nsg rule create --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name vnetOutboundTemporary --description "Block connections to the VNet" --access "Deny" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges "*" --protocol "*" --destination-address-prefixes VirtualNetwork --priority 200

    # Create the VM
    echo -e "${BOLD}Creating VM...${END}"
    OSDISKNAME=${MACHINENAME_EXTERNAL}_OSDISK
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
        --subnet $SUBNET_EXTERNAL \
        --vnet-name $VNETNAME
    echo -e "${BOLD}Deployed new ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} server${END}"

    # Poll VM to see whether it has finished running
    echo -e "${BOLD}Waiting for VM setup to finish (this may take several minutes)...${END}"
    while true; do
        POLL=$(az vm get-instance-view --resource-group $RESOURCEGROUP --name $MACHINENAME_EXTERNAL --query "instanceView.statuses[?code == 'PowerState/running'].displayStatus")
        if [ "$(echo $POLL | grep 'VM running')" == "" ]; then break; fi
        sleep 10
    done

    # Delete the configuration NSG rule and restart the VM
    echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME_EXTERNAL}${END}"
    az network nsg rule delete --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --name configurationOutboundTemporary
    az network nsg rule delete --resource-group $RESOURCEGROUP --nsg-name $NSG_EXTERNAL --name vnetOutboundTemporary
    az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME_EXTERNAL
fi
