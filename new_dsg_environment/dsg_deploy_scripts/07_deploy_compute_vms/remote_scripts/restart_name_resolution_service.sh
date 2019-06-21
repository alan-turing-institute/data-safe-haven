#!/bin/bash
# $TEST_HOST must be present as an environment variable
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

RESOLVE_CONF_TARGET="/run/systemd/resolve/resolv.conf"

# Test nslookup
test_dnslookup () {
    local NS_RESULT=$(nslookup $TEST_HOST)
    local NS_EXIT=$?

    echo "NS LOOKUP RESULT:"
    echo "$NS_RESULT"

    if [ $NS_EXIT -eq 0 ]; then
        echo -e "${BLUE}Name resolution working.${END}"
    else
        echo -e "${RED}Name resolution not working. Testing with systemd${END}"
        systemd-resolve $TEST_HOST
    fi
    return $NS_EXIT
}

# Test the /etc/resolv.conf file
test_resolve_conf() {
    local RESOLVE_CONF_LOCATION=$(sudo ls -al /etc/resolv.conf | cut -d'>' -f2 | sed -e 's/ //g')
    sudo cat /etc/resolv.conf
    if [ "${RESOLVE_CONF_LOCATION}" != "${RESOLVE_CONF_TARGET}" ]; then
        echo -e "${RED}/etc/resolv.conf is currently pointing to ${RESOLVE_CONF_LOCATION}${END}"
        return 1
    else
        echo -e "${BLUE}/etc/resolv.conf is currently pointing to ${RESOLVE_CONF_LOCATION}${END}"
    fi
    return 0
}

# Restart the systemd-resolved.service
restart_resolved () {
    echo "Restarting systemd-resolved nameservice"
    sudo systemctl restart systemd-resolved.service
}

# Reset /etc/resolv.conf
reset_resolv_conf () {
    echo -e "${BLUE}Resetting /etc/resolv.conf symlink${BLUE}"
    sudo rm /etc/resolv.conf
    sudo ln -s "$RESOLVE_CONF_TARGET" /etc/resolv.conf
    test_resolve_conf
}



# Run name resolution checks
# --------------------------
echo -e "${BLUE}Checking name resolution${END}"

# Check nslookup
echo "Testing connectivity for '$TEST_HOST'"
test_dnslookup
DNS_STATUS=$?

# Check where resolv.conf is pointing
echo "Testing /etc/resolv.conf"
test_resolve_conf
RESOLVE_CONF_STATUS=$?
if [ "$RESOLVE_CONF_STATUS" != "0" ]; then
    reset_resolv_conf
    test_dnslookup
    DNS_STATUS=$?
fi

# If the DNS problem is not solved then restart the service
if [ "$DNS_STATUS" != "0" ]; then
    restart_resolved
    test_dnslookup
fi