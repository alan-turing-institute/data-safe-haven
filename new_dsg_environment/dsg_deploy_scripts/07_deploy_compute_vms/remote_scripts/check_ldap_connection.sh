#!/bin/bash
# $LDAP_USER must be present as an environment variable
# $TEST_HOST must be present as an environment variable
# $SERVICE_PATH must be present as an environment variable
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

echo -e "${BLUE}Checking LDAP connectivity${END}"

LDAP_SECRET=$(sudo cat /etc/ldap.secret)
USER_SEARCH_CMD="ldapsearch -LLL -D \"${LDAP_USER}@${DOMAIN_LOWER}\" -w \"$LDAP_SECRET\" -p 389 -h \"$TEST_HOST\" -b \"$SERVICE_PATH\" -s sub \"(sAMAccountName=${LDAP_USER})\""

#  | grep 'sAMAccountName:' | cut -d' ' -f2)"
echo $USER_SEARCH_CMD
$($USER_SEARCH_CMD)

echo -e "Testing LDAP search..."
STATUS=$(${USER_SEARCH_CMD} 2>&1)
if [ "$STATUS" == "$LDAP_USER" ]; then
    echo -e "${BLUE}LDAP search succeeded: found user '$STATUS'.${END}"
    exit 0
else
    echo -e "${RED}LDAP search failed: '$STATUS'${END}"
    # sudo cat /etc/ldap.secret | sudo realm join --verbose -U $LDAP_USER $DOMAIN_LOWER --install=/
fi

# echo -e "Retesting current realms..."
# STATUS=$(${STATUS_CMD})
# if [ "$STATUS" == "" ]; then
#     echo -e "${RED}No realm memberships found!${END}"
#     exit 1
# else
#     echo -e "${BLUE}Currently a member of realm: '$STATUS'${END}"
#     exit 0
# fi