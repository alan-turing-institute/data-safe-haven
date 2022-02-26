#! /bin/bash
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables
# It expects the following parameters:
#     DOMAIN_CONTROLLER
#     LDAP_SEARCH_USER
#     LDAP_TEST_USER
#     SERVICE_PATH

RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

echo -e "${BLUE}Checking LDAP connectivity${END}"

LDAP_SECRET=$(sudo cat /etc/ldap.secret)
LDAPSEARCH_CMD="ldapsearch -LLL -D \"${LDAP_SEARCH_USER}@${DOMAIN_LOWER}\" -w \"$LDAP_SECRET\" -p 389 -h \"$DOMAIN_CONTROLLER\" -b \"$SERVICE_PATH\" -s sub \"(sAMAccountName=${LDAP_TEST_USER})\""

echo -e "Testing LDAP search..."
LDAP_SEARCH_OUTPUT=$(eval ${LDAPSEARCH_CMD} 2>&1)  # NB. eval is OK here since we control the inputs
STATUS=$(echo "${LDAP_SEARCH_OUTPUT}" | grep 'sAMAccountName:' | cut -d' ' -f2)
if [ "$STATUS" == "$LDAP_TEST_USER" ]; then
    echo -e "${BLUE} [o] LDAP search succeeded: found user '$STATUS'.${END}"
    echo "LDAP SEARCH RESULT:"
    echo "$LDAP_SEARCH_OUTPUT"
    exit 0
else
    echo -e "${RED} [x] LDAP search failed.${END}"
    echo "LDAP SEARCH RESULT:"
    echo "$LDAP_SEARCH_OUTPUT"
    exit 1
fi