#!/usr/bin/env bash

# Options which are configurable at the command line
DSG_ID=""
FIXED_IP=""
VM_SIZE="Standard_DS2_v2"

# Document usage for this script
print_usage_and_exit() {
    echo "usage: $0 -g dsg_group_id [-h] [-i source_image] [-x source_image_version] [-z vm_size]"
    echo "  -h                        display help"
    echo "  -d dsg_group_id           specify the DSG group to deploy to ('TEST' for test or 1-6 for production)"
    echo "  -z vm_size                specify a VM size to use (defaults to 'Standard_DS2_v2')"
    echo "  -q fixed_ip               Last part of IP address (first three parts are fixed for each DSG group)"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "d:hz:q:" opt; do
    case $opt in
        d)
            DSG_ID=$OPTARG
            ;;
        h)
            print_usage_and_exit
            ;;
        z)
            VM_SIZE=$OPTARG
            ;;
        q)
            FIXED_IP=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done

# Check that a DSG group ID has been provided
if [ "$DSG_ID" = "" ]; then
    echo -e "${RED}DSG Group ID is a required argument!${END}"
    print_usage_and_exit
fi
# Check DSG group ID is valid
DSG_ID_UPPER=$(echo "$DSG_ID" | tr '[:lower:]' '[:upper:]')
DSG_ID_LOWER=$(echo "$DSG_ID" | tr '[:upper:]' '[:lower:]')
if [ "$DSG_ID_UPPER" != "TEST" -a "$DSG_ID_UPPER" != "1" -a "$DSG_ID_UPPER" != "2" -a "$DSG_ID_UPPER" != "3" \
 -a "$DSG_ID_UPPER" != "4" -a "$DSG_ID_UPPER" != "5" -a "$DSG_ID_UPPER" != "6" -a "$DSG_ID_UPPER" != "9" ]; then
    echo -e "${RED}DSG Group ID is not valid!${END}"
    print_usage_and_exit
fi

# Deployed VM parameters
USERNAME="atiadmin"

# Deployment environment
RESOURCEGROUP="RG_DSG_COMPUTE"
DSG_SUBNET="Subnet-Data"
DSG_NSG="NSG_Linux_Servers"

# Secrets
MANAGEMENT_VAULT_NAME="dsg-management-test"
LDAP_SECRET_NAME="ldap-secret-dsg${DSG_ID_LOWER}"
ADMIN_PASSWORD_SECRET_NAME="vm-admin-password"

# Set defaults for test and production environments
if [ "$DSG_ID_UPPER" = "TEST" ] ; then
    DSG_VNET="DSG_DSGROUPTEST_VNet1"
    SUBSCRIPTIONSOURCE="Safe Haven Management Testing"
    SUBSCRIPTIONTARGET="Data Study Group Testing"
    LDAP_USER="dsgpuldap"
    DOMAIN="dsgroupdev.co.uk"
    AD_DC_NAME="MGMTDEVDC"
    LDAP_BASE_DN="ou=safe haven research users,dc=dsgroupdev,dc=co,dc=uk"
    LDAP_BIND_DN="cn=data science ldap,ou=safe haven service accounts,dc=dsgroupdev,dc=co,dc=uk"
    LDAP_FILTER="(&(objectClass=user)(memberOf=CN=SG DSGROUP$DSG_ID_UPPER Research Users,OU=Safe Haven Security Groups,DC=dsgroupdev,DC=co,DC=uk))"
elif [ "$DSG_ID_UPPER" = "9" ] ; then
    DSG_VNET="DSG_DSGROUP9_VNet1"
    SUBSCRIPTIONSOURCE="Safe Haven Management Testing"
    SUBSCRIPTIONTARGET="DSG Template Testing"
    LDAP_USER="DSGROUP9dsgpuldap"
    DOMAIN="dsgroupdev.co.uk"
    AD_DC_NAME="MGMTDEVDC"
    LDAP_BASE_DN="ou=safe haven research users,dc=dsgroupdev,dc=co,dc=uk"
    LDAP_BIND_DN="cn=DSGGROUP9 Data Science LDAP,ou=safe haven service accounts,dc=dsgroupdev,dc=co,dc=uk"
    LDAP_FILTER="(&(objectClass=user)(memberOf=CN=SG DSGROUP$DSG_ID_UPPER Research Users,OU=Safe Haven Security Groups,DC=dsgroupdev,DC=co,DC=uk))"
else
    DSG_VNET="DSG_DSGROUP${DSG_ID_UPPER}_VNET1"
    SUBSCRIPTIONSOURCE="Safe Haven Management Testing"
    SUBSCRIPTIONTARGET="Data Study Group ${DSG_ID_LOWER}"
    LDAP_USER="dsg${DSG_ID_LOWER}dsgpuldap"
    DOMAIN="turingsafehaven.ac.uk"
    AD_DC_NAME="SHMDC1"
    LDAP_BASE_DN="OU=Safe Haven Research Users,DC=turingsafehaven,DC=ac,DC=uk"
    LDAP_BIND_DN="CN=DSG${DSG_ID_UPPER} Data Science LDAP,OU=Safe Haven Service Accounts,DC=turingsafehaven,DC=ac,DC=uk"
    LDAP_FILTER="(&(objectClass=user)(memberOf=CN=SG DSGROUP$DSG_ID_UPPER Research Users,OU=Safe Haven Security Groups,DC=turingsafehaven,DC=ac,DC=uk))"
fi

# ComputeVM-DsgBase version 0.0.2018121000 is a direct copy of Ubuntu version 0.0.2018120701 (/subscriptions/1e79c270-3126-43de-b035-22c3118dd488/resourceGroups/RG_SH_IMAGEGALLERY/providers/Microsoft.Compute/images/ImageComputeVM-Ubuntu1804Base-201812071437)

# Overwite defaults for per-DSG settings
if [ "$DSG_ID_UPPER" = "TEST" ]; then
    IP_PREFIX="10.250.250."
    CLOUD_INIT_YAML="DSG_configs/cloud-init-compute-vm-DSG-TEST.yaml"
    # Only change settings below here during a DSG
    SOURCEIMAGE="Ubuntu"
    VERSION="0.0.2018120701"
fi
if [ "$DSG_ID_UPPER" = "1" ]; then
    DSG_VNET="DSG_EXTREMISM_VNET1"
    IP_PREFIX="10.250.2."
    CLOUD_INIT_YAML="DSG_configs/cloud-init-compute-vm-DSG-1.yaml"
    # Only change settings below here during a DSG
    SOURCEIMAGE="Ubuntu"
    VERSION="0.0.2018120701"
fi
if [ "$DSG_ID_UPPER" = "2" ]; then
    DSG_VNET="DSG_NEWS_VNET1"
    IP_PREFIX="10.250.10."
    CLOUD_INIT_YAML="DSG_configs/cloud-init-compute-vm-DSG-2.yaml"
    # Only change settings below here during a DSG
    SOURCEIMAGE="Ubuntu"
    VERSION="0.0.2018120701"
fi
if [ "$DSG_ID_UPPER" = "3" ]; then
    IP_PREFIX="10.250.18."
    CLOUD_INIT_YAML="DSG_configs/cloud-init-compute-vm-DSG-3.yaml"
    # Only change settings below here during a DSG
    SOURCEIMAGE="Ubuntu"
    VERSION="0.0.2018120701"
fi
if [ "$DSG_ID_UPPER" = "4" ]; then
    IP_PREFIX="10.250.26."
    CLOUD_INIT_YAML="DSG_configs/cloud-init-compute-vm-DSG-4.yaml"
    # Only change settings below here during a DSG
    SOURCEIMAGE="Ubuntu"
    VERSION="0.0.2018120701"
fi
if [ "$DSG_ID_UPPER" = "6" ]; then
    IP_PREFIX="10.250.42."
    CLOUD_INIT_YAML="DSG_configs/cloud-init-compute-vm-DSG-6.yaml"
    # Only change settings below here during a DSG
    SOURCEIMAGE="Ubuntu"
    VERSION="0.0.2018120701"
fi
if [ "$DSG_ID_UPPER" = "9" ]; then
    IP_PREFIX="10.250.66."
    CLOUD_INIT_YAML="DSG_configs/cloud-init-compute-vm-DSG-9.yaml"
    # Only change settings below here during a DSG
    SOURCEIMAGE="Ubuntu"
    VERSION="0.0.2018120701"
fi


if [ "$FIXED_IP" = "" ]; then
    ./deploy_azure_dsg_vm.sh -s "$SUBSCRIPTIONSOURCE" -t "$SUBSCRIPTIONTARGET" -i "$SOURCEIMAGE" -x "$VERSION" -g "$DSG_NSG" \
        -r "$RESOURCEGROUP" -v "$DSG_VNET" -w "$DSG_SUBNET" -z "$VM_SIZE" -m "$MANAGEMENT_VAULT_NAME" -l "$LDAP_SECRET_NAME" \
        -p "$ADMIN_PASSWORD_SECRET_NAME" -j "$LDAP_USER" -d "$DOMAIN" -a "$AD_DC_NAME" -b "$LDAP_BASE_DN" -c "$LDAP_BIND_DN" \
        -y $CLOUD_INIT_YAML -f "$LDAP_FILTER"
else
    IP_ADDRESS="${IP_PREFIX}${FIXED_IP}"
    ./deploy_azure_dsg_vm.sh -s "$SUBSCRIPTIONSOURCE" -t "$SUBSCRIPTIONTARGET" -i "$SOURCEIMAGE" -x "$VERSION" -g "$DSG_NSG" \
        -r "$RESOURCEGROUP" -v "$DSG_VNET" -w "$DSG_SUBNET" -z "$VM_SIZE" -m "$MANAGEMENT_VAULT_NAME" -l "$LDAP_SECRET_NAME" \
        -p "$ADMIN_PASSWORD_SECRET_NAME" -j "$LDAP_USER" -d "$DOMAIN" -a "$AD_DC_NAME" -b "$LDAP_BASE_DN" -c "$LDAP_BIND_DN" \
        -q "$IP_ADDRESS" -y $CLOUD_INIT_YAML -f "$LDAP_FILTER"
fi