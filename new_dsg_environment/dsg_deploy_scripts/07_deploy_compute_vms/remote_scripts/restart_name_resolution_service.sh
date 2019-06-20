#!/bin/bash
# $TEST_HOST must be present as an environment variable
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

echo -e "${BLUE}Checking name resolution${END}"

NS_CMD=( nslookup $TEST_HOST )
RESTART_CMD="sudo systemctl restart systemd-resolved.service"

echo "Testing connectivity for '$TEST_HOST'"
NS_RESULT_PRE=$(${NS_CMD[@]})
NS_EXIT_PRE=$?
RETEST_NSLOOKUP=0
if [ "$NS_EXIT_PRE" == "0" ]
then
    # Nslookup succeeded: no need to restart name resolution service
    echo -e "${BLUE}Name resolution working. No need to restart.${END}"
else
    # Nslookup failed
    echo -e "${RED}Name resolution not working.${END}"
    RETEST_NSLOOKUP=1
fi
echo "NS LOOKUP RESULT:"
echo "$NS_RESULT_PRE"

# Check where resolv.conf is pointing
RESOLVE_CONF_LOCATION=$(sudo ls -al /etc/resolv.conf | cut -d'>' -f2 | sed -e 's/ //g')
echo "/etc/resolv.conf is pointing to $RESOLVE_CONF_LOCATION"
if [ "$RESOLVE_CONF_LOCATION" != "/run/systemd/resolve/resolv.conf" ]; then
    echo -e "${RED}Resetting /etc/resolv.conf${END}"
    sudo rm /etc/resolv.conf
    sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
    RETEST_NSLOOKUP=1
fi

if [ $RETEST_NSLOOKUP -eq 0 ]; then exit 0; fi

echo "Restarting systemd-resolved nameservice for '$TEST_HOST'"
$(${RESTART_CMD})
echo "Re-testing connectivity for '$TEST_HOST'"

NS_RESULT_POST=$(${NS_CMD[@]})
NS_EXIT_POST=$?
if [ "$NS_EXIT_POST" == "0" ]
then
    # Nslookup succeeded: name resolution service successfully restarted
    echo -e "${BLUE}Name resolution working. Restart successful.${END}"
    echo "NS LOOKUP RESULT:"
    echo "$NS_RESULT_POST"
    exit 0
else
    # Nslookup failed: print notification and exit
    echo -e "${RED}Name resolution not working after restart.${END}"
    echo "NS LOOKUP RESULT:"
    echo "$NS_RESULT_POST"
    echo "Restart command: $RESTART_CMD"
    exit 1
fi
