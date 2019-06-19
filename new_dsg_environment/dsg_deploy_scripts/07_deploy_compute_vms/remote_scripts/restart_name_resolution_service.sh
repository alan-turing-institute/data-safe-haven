#!/bin/bash
# $TEST_HOST must be present as an environment variable
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

NS_CMD=( nslookup $TEST_HOST )
RESTART_CMD="sudo systemctl restart systemd-resolved.service"

echo "Testing connectivity for '$TEST_HOST'"
NS_RESULT_PRE=$(${NS_CMD[@]})
NS_EXIT_PRE=$?
if [ "$NS_EXIT_PRE" == "0" ]
then
    # Nslookup succeeded: no need to restart name resolution service
    echo -e "${BLUE}Name resolution working. No need to restart.${END}"
    echo "NS LOOKUP RESULT:"
    echo "$NS_RESULT_PRE"
    exit 0
else
    # Nslookup failed: try restarting name resolution service
    echo -e "${RED}Name resolution not working. Restarting name resolution service.${END}"
    echo "NS LOOKUP RESULT:"
    echo "$NS_RESULT_PRE"
    $(${RESTART_CMD})
fi

echo "Re-testing connectivity for '$TEST_HOST'"
NS_RESULT_POST=$(${NS_CMD[@]})
NS_EXIT_POST=$?
if [ "$NS_EXIT_POST" == "0" ]
then
    # Nslookup succeeded: name resolution service successfully restarted
    echo -e "${BLUE}Name resolution working. Restart successful.${END}"
    echo "NS LOOKUP RESULT:"
    echo $NS_RESULT_POST
    exit 0
else
    # Nslookup failed: print notification and exit
    echo -e "${RED}Name resolution not working after restart.${END}"
    echo "NS LOOKUP RESULT:"
    echo "$NS_RESULT_POST"
    echo "Restart command: $RESTART_CMD"
    exit 1
fi
