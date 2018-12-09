#!/usr/bin/env bash

# Document usage for this script
print_usage_and_exit() {
    echo "usage: $0 -g dsg_group_id [-h] [-i source_image] [-x source_image_version] [-z vm_size]"
    echo "  -h                        display help"
    echo "  -d dsg_group_id            specify the DSG group to deploy to ('TEST' for test or 1-6 for production)"
    echo "  -i source_image           specify source_image: either 'Ubuntu' (default) 'UbuntuTorch' (as default but with Torch included) or 'DataScience'"
    echo "  -x source_image_version   specify the version of the source image to use (defaults to prompting to select from available versions)"
    echo "  -z vm_size                specify a VM size to use (defaults to 'Standard_DS2_v2')"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "d:hi:x:z:" opt; do
    case $opt in
        d)
            DSG_ID=$OPTARG
            ;;
        h)
            print_usage_and_exit
            ;;
        i)
            SOURCEIMAGE=$OPTARG
            ;;
        x)
            VERSION=$OPTARG
            ;;
        z)
            VM_SIZE=$OPTARG
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
 -a "$DSG_ID_UPPER" != "4" -a "$DSG_ID_UPPER" != "5" -a "$DSG_ID_UPPER" != "6" ]; then
    echo -e "${RED}DSG Group ID is not valid!${END}"
    print_usage_and_exit
fi

# Gallery image details
SOURCEIMAGE="Ubuntu"
VERSION="0.0.2018120701"
RESOURCEGROUP="RG_DSG_COMPUTE"

# Deployed VM parameters
VM_SIZE="Standard_DS2_v2"
USERNAME="atiadmin"

# Deployment environment
DSG_SUBNET="Subnet-Data"
DSG_NSG="NSG_Linux_Servers"

# Secrets
MANAGEMENT_VAULT_NAME="dsg-management-test"
LDAP_SECRET_NAME="ldap-secret-dsg${DSG_ID_LOWER}"
ADMIN_PASSWORD_SECRET_NAME="vm-admin-password"

if [ "$DSG_ID_UPPER" = "TEST" ]; then
    DSG_VNET="DSG_DSGROUPTEST_VNet1"
    SUBSCRIPTIONSOURCE="Safe Haven Management Testing"
    SUBSCRIPTIONTARGET="Data Study Group Testing"
    LDAP_USER="dsgpuldap"
    DOMAIN="dsgroupdev.co.uk"
    AD_DC_NAME="MGMTDEVDC"
    LDAP_BASE_DN="ou=safe haven research users,dc=dsgroupdev,dc=co,dc=uk"
    LDAP_BIND_DN="cn=data science ldap,ou=safe haven service accounts,dc=dsgroupdev,dc=co,dc=uk"
else
    DSG_VNET="DSG_DSGROUP${DSG_ID_UPPER}_VNET1"
    SUBSCRIPTIONSOURCE="Safe Haven Management Testing"
    SUBSCRIPTIONTARGET="Data Study Group ${DSG_ID_LOWER}"
    LDAP_USER="dsg${DSG_ID_LOWER}dsgpuldap"
    DOMAIN="turingsafehaven.ac.uk"
    AD_DC_NAME="SHMDC1"
    LDAP_BASE_DN="OU=Safe Haven Research Users,DC=turingsafehaven,DC=ac,DC=uk"
    LDAP_BIND_DN="CN=DSG${DSG_ID_LOWER} Data Science LDAP,OU=Safe Haven Service Accounts,DC=turingsafehaven,DC=ac,DC=uk"
fi
# Overwite defaults for DSG 1 and 2
if [ "$DSG_ID_UPPER" = "1" ]; then
    DSG_VNET="DSG_EXTREMISM_VNET1"
fi
if [ "$DSG_ID_UPPER" = "2" ]; then
    DSG_VNET="DSG_NEWS_VNET1"
fi

./deploy_azure_dsg_vm.sh -s "$SUBSCRIPTIONSOURCE" -t "$SUBSCRIPTIONTARGET" -i "$SOURCEIMAGE" -x "$VERSION" -g "$DSG_NSG" \
 -r "$RESOURCEGROUP" -v "$DSG_VNET" -w "$DSG_SUBNET" -z "$VM_SIZE" -m "$MANAGEMENT_VAULT_NAME" -l "$LDAP_SECRET_NAME" \
 -p "$ADMIN_PASSWORD_SECRET_NAME" -j "$LDAP_USER" -d "$DOMAIN" -a "$AD_DC_NAME" -b "$LDAP_BASE_DN" -c "$LDAP_BIND_DN"