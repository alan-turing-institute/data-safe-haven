#!/bin/bash
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

echo -e "${BLUE}Checking xrdp status${END}"
XRDP_CMD="systemctl status xrdp"
XRDP_SESMAN_CMD="systemctl status xrdp-sesman"


echo "Testing xrdp status..."
XRDP_STATUS=$(sudo ${XRDP_CMD} | grep 'Active: failed')
XRDP_SESMAN_STATUS=$(sudo ${XRDP_SESMAN_CMD} | grep 'Active: failed')
if [[ ("$XRDP_STATUS" != "") || ("$XRDP_SESMAN_STATUS" != "") ]]; then
    echo -e "${RED}xrdp services have failed. Restarting...${END}"
    sudo systemctl restart xrdp
    sudo systemctl restart xrdp-sesman
else
    echo -e "${BLUE}xrdp services are working. No need to restart.${END}"
    echo "XRDP STATUS RESULT:"
    sudo ${XRDP_CMD}
    sudo ${XRDP_SESMAN_CMD}
    exit 0
fi

echo "Retesting xrdp status..."
XRDP_STATUS=$(sudo ${XRDP_CMD} | grep 'Active: failed')
XRDP_SESMAN_STATUS=$(sudo ${XRDP_SESMAN_CMD} | grep 'Active: failed')
if [[ ("$XRDP_STATUS" != "") || ("$XRDP_SESMAN_STATUS" != "") ]]; then
    echo -e "${RED}xrdp services are not working after restart.${END}"
    echo "XRDP STATUS RESULT:"
    sudo ${XRDP_CMD}
    sudo ${XRDP_SESMAN_CMD}
    exit 1
else
    echo -e "${BLUE}xrdp services are working after restart.${END}"
    echo "XRDP STATUS RESULT:"
    sudo ${XRDP_CMD}
    sudo ${XRDP_SESMAN_CMD}
    exit 0
fi
