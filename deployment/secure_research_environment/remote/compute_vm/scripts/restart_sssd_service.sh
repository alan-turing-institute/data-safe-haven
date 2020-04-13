#!/bin/bash
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

echo -e "${BLUE}Checking SSSD status${END}"
STATUS_CMD="sudo systemctl status sssd.service"

echo "Testing sssd status..."
STATUS=$(${STATUS_CMD})
if [ "$(echo $STATUS | grep 'Active: failed')" != "" ]; then
    echo -e "${RED}SSSD service has failed. Restarting...${END}"
    sudo systemctl stop sssd.service
    # Update sssd settings
    sudo sed -i -E 's/(use_fully_qualified_names = ).*/\1False/' /etc/sssd/sssd.conf
    sudo sed -i -E 's|(fallback_homedir = ).*|\1/home/%u|' /etc/sssd/sssd.conf
    sudo sed -i -E 's/(access_provider = ).*/\1simple/' /etc/sssd/sssd.conf
    # Force re-generation of config files
    sudo rm /var/lib/sss/db/*.ldb
    sudo systemctl restart sssd.service
else
    echo -e "${BLUE} [o] SSSD service is working. No need to restart.${END}"
    echo "SSSD STATUS RESULT:"
    echo "$STATUS"
    exit 0
fi

echo "Retesting sssd status..."
STATUS=$(${STATUS_CMD})
if [ "$(echo $STATUS | grep 'Active: failed')" != "" ]; then
    echo -e "${RED} [x] SSSD service not working after restart.${END}"
    echo "SSSD STATUS RESULT:"
    echo "$STATUS"
    exit 1
else
    echo -e "${BLUE} [o] SSSD service is working after restart.${END}"
    echo "SSSD STATUS RESULT:"
    echo "$STATUS"
    exit 0
fi