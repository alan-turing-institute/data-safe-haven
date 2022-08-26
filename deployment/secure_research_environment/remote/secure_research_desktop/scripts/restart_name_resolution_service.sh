#! /bin/bash
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables
# It expects the following parameters:
#     DOMAIN_CONTROLLER
#     DOMAIN_LOWER

RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

SYSTEMD_RESOLV_CONF="/run/systemd/resolve/resolv.conf"

# Test nslookup
test_dnslookup () {
    local NS_RESULT
    NS_RESULT="$(nslookup "$DOMAIN_CONTROLLER")"
    local NS_EXIT=$?

    echo "NS LOOKUP RESULT:"
    echo "$NS_RESULT"

    if [ $NS_EXIT -eq 0 ]; then
        echo -e "${BLUE}Name resolution working.${END}"
    else
        echo -e "${RED}Name resolution not working. Testing with systemd${END}"
        systemd-resolve "$DOMAIN_CONTROLLER"
    fi
    return $NS_EXIT
}

# Test the /etc/resolv.conf file
test_resolve_conf() {
    local RESOLVE_CONF_LOCATION
    RESOLVE_CONF_LOCATION=$(realpath /etc/resolv.conf)
    sed -e 's|^|/etc/resolv.conf: |g' /etc/resolv.conf
    if [ "${RESOLVE_CONF_LOCATION}" != "${SYSTEMD_RESOLV_CONF}" ]; then
        echo -e "${RED}/etc/resolv.conf is currently pointing to ${RESOLVE_CONF_LOCATION}${END}"
        return 1
    else
        echo -e "${BLUE}/etc/resolv.conf is currently pointing to ${RESOLVE_CONF_LOCATION}${END}"
    fi
    return 0
}

# Update systemd resolv.conf
update_systemd_resolv_conf () {
    cp ${SYSTEMD_RESOLV_CONF} /tmp/resolved.conf
    sudo sed -i -e "s/^[#]DNS=.*/DNS=/" -e "s/^[#]FallbackDNS=.*/FallbackDNS=/" -e "s/^[#]Domains=.*/Domains=${DOMAIN_FQDN_LOWER}/" ${SYSTEMD_RESOLV_CONF}
    if (cmp ${SYSTEMD_RESOLV_CONF} /tmp/resolved.conf); then
        echo "No updates needed"
    else
        echo "Previous ${SYSTEMD_RESOLV_CONF}:"
        grep -v -e '^[[:space:]]*$' /tmp/resolved.conf | grep -v "^#"
        echo "Updated ${SYSTEMD_RESOLV_CONF}:"
        grep -v -e '^[[:space:]]*$' ${SYSTEMD_RESOLV_CONF} | grep -v "^#"
        restart_resolved
    fi
}

# Restart the systemd-resolved service
restart_resolved () {
    echo "Restarting systemd-resolved name service"
    sudo systemctl restart systemd-resolved
}

# Reset /etc/resolv.conf
reset_resolv_conf () {
    echo -e "${BLUE}Resetting /etc/resolv.conf symlink${END}"
    sudo rm /etc/resolv.conf
    sudo ln -rsf "${SYSTEMD_RESOLV_CONF}" /etc/resolv.conf
    test_resolve_conf
}


# Run name resolution checks
# --------------------------
echo -e "${BLUE}Checking name resolution${END}"

# Check nslookup
echo -e "\nTesting connectivity for '$DOMAIN_CONTROLLER'"
test_dnslookup
DNS_STATUS=$?

# Update ${SYSTEMD_RESOLV_CONF} if necessary
echo -e "\nTesting ${SYSTEMD_RESOLV_CONF}"
update_systemd_resolv_conf

# Check where resolv.conf is pointing
echo -e "\nTesting /etc/resolv.conf"
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