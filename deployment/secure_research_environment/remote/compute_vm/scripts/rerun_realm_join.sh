#!/bin/bash
# $DOMAIN_JOIN_USER must be present as an environment variable
# $DOMAIN_LOWER must be present as an environment variable
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

echo -e "${BLUE}Checking realm membership${END}"
REALM_LIST_CMD="sudo realm list"
STATUS_CMD="sudo realm list --name-only | grep $DOMAIN_LOWER"

echo -e "Testing current realms..."
STATUS=$(${STATUS_CMD})
if [ "$STATUS" == "" ]; then
    echo -e "${RED}No realm memberships found. Attempting to join $DOMAIN_LOWER${END}"
    sudo cat /etc/ldap.secret | sudo realm join --verbose -U $DOMAIN_JOIN_USER $DOMAIN_LOWER --install=/
    sleep 30  # allow time for the realm join to propagate
else
    echo -e "${BLUE} [o] Currently a member of realm: '$STATUS'. No need to rejoin.${END}"
    echo "REALM LIST RESULT:"
    eval $REALM_LIST_CMD
    exit 0
fi

echo -e "Retesting current realms..."
STATUS=$(${STATUS_CMD})
if [ "$STATUS" == "" ]; then
    echo -e "${RED} [x] No realm memberships found!${END}"
    echo "REALM LIST RESULT:"
    eval $REALM_LIST_CMD
    exit 1
else
    echo -e "${BLUE} [o] Currently a member of realm: '$STATUS'${END}"
    echo "REALM LIST RESULT:"
    eval $REALM_LIST_CMD
    exit 0
fi