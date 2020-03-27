#!/bin/bash
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

echo -e "${BLUE}Checking xrdp status${END}"
STATUS_CMD="sudo systemctl status xrdp; sudo systemctl status xrdp-sesman"

echo "Testing xrdp status..."
STATUS=$(${STATUS_CMD})
if [ "$(echo $STATUS | grep 'Active: failed')" != "" ]; then
    echo -e "${RED}xrdp service has failed. Restarting...${END}"
    sudo systemctl restart xrdp
    sudo systemctl restart xrdp-sesman
else
    echo -e "${BLUE}xrdp service is working. No need to restart.${END}"
    echo "XRDP STATUS RESULT:"
    echo "$STATUS"
    exit 0
fi

echo "Retesting xrdp status..."
STATUS=$(${STATUS_CMD})
if [ "$(echo $STATUS | grep 'Active: failed')" != "" ]; then
    echo -e "${RED}xrdp service not working after restart.${END}"
    echo "XRDP STATUS RESULT:"
    echo "$STATUS"
    exit 1
else
    echo -e "${BLUE}xrdp service is working after restart.${END}"
    echo "XRDP STATUS RESULT:"
    echo "$STATUS"
    exit 0
fi