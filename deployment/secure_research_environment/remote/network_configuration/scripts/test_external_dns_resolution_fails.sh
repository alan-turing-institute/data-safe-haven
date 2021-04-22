#!/bin/bash
# Test DNS resolution lockdown
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables
#
# The following variables are expected by the script
#     SHM_DOMAIN_FQDN
#     SHM_DC1_FQDN
#     SHM_DC2_FQDN
#     OUTBOUND_INTERNET

confirm_dns_lookup_fails() {
    FQDN=$1
    DNS_SERVER=$2
    if [ -z "$DNS_SERVER" ]; then
        DNS_SERVER_MSG="default DNS servers"
    else
        DNS_SERVER_MSG="$DNS_SERVER"
    fi
    sudo systemd-resolve --flush-caches
    NS_RESULT=$(nslookup $FQDN $DNS_SERVER)
    if [ $? -eq 0 ]; then
        echo -e " [x] DNS lookup for '$FQDN' unexpectedly succeeded via $DNS_SERVER_MSG."
        echo -e "$NS_RESULT\n"
        return 1
    else
        echo -e " [o] DNS lookup for '$FQDN' failed as expected via $DNS_SERVER_MSG."
        return 0
    fi
}

confirm_dns_lookup_succeeds() {
    FQDN=$1
    DNS_SERVER=$2
    if [ -z "$DNS_SERVER" ]; then
        DNS_SERVER_MSG="default DNS servers"
    else
        DNS_SERVER_MSG="$DNS_SERVER"
    fi
    sudo systemd-resolve --flush-caches
    NS_RESULT=$(nslookup $FQDN $DNS_SERVER)
    if [ $? -eq 0 ]; then
        echo -e " [o] DNS lookup for '$FQDN' succeeded as expected via $DNS_SERVER_MSG."
        return 0
    else
        echo -e " [x] DNS lookup for '$FQDN' unexpectedly failed via $DNS_SERVER_MSG."
        echo -e "$NS_RESULT\n"
        return 1
    fi
}

echo "Testing DNS resolution lockdown"
echo "-------------------------------"
echo "$HOSTNAME $(date +"%Y-%m-%dT%H:%M:%S")"

FAILED_TESTS=0
echo -e "\nTesting DNS lookup for internal FQDNs via default DNS servers..."
confirm_dns_lookup_succeeds "$SHM_DOMAIN_FQDN" || FAILED_TESTS=$(($FAILED_TESTS + 1))
confirm_dns_lookup_succeeds "$SHM_DC1_FQDN" || FAILED_TESTS=$(($FAILED_TESTS + 1))
confirm_dns_lookup_succeeds "$SHM_DC2_FQDN" || FAILED_TESTS=$(($FAILED_TESTS + 1))

echo -e "\nTesting DNS lookup for non-existent external domains via default DNS servers..."
confirm_dns_lookup_fails "fail.example.com" || FAILED_TESTS=$(($FAILED_TESTS + 1))

echo -e "\nTesting DNS lookup for resolvable external domains via default DNS servers..."
if [ "$OUTBOUND_INTERNET" == "Deny" ]; then
    confirm_dns_lookup_fails "example.com" || FAILED_TESTS=$(($FAILED_TESTS + 1))
    confirm_dns_lookup_fails "doi.org" || FAILED_TESTS=$(($FAILED_TESTS + 1))
    confirm_dns_lookup_fails "google.com" || FAILED_TESTS=$(($FAILED_TESTS + 1))
    confirm_dns_lookup_fails "facebook.com" || FAILED_TESTS=$(($FAILED_TESTS + 1))
elif [ "$OUTBOUND_INTERNET" == "Allow" ]; then
    confirm_dns_lookup_succeeds "example.com" || FAILED_TESTS=$(($FAILED_TESTS + 1))
    confirm_dns_lookup_succeeds "doi.org" || FAILED_TESTS=$(($FAILED_TESTS + 1))
    confirm_dns_lookup_succeeds "google.com" || FAILED_TESTS=$(($FAILED_TESTS + 1))
    confirm_dns_lookup_succeeds "facebook.com" || FAILED_TESTS=$(($FAILED_TESTS + 1))
fi

echo -e "\nTesting DNS lookup for non-existent external domains via Azure Platform DNS servers..."
confirm_dns_lookup_fails "fail.example.com" "168.63.129.16" || FAILED_TESTS=$(($FAILED_TESTS + 1))

echo -e "\nTesting DNS lookup for resolvable external domains via Azure Platform DNS servers..."
if [ "$OUTBOUND_INTERNET" == "Deny" ]; then
    confirm_dns_lookup_fails "example.com" "168.63.129.16" || FAILED_TESTS=$(($FAILED_TESTS + 1))
    confirm_dns_lookup_fails "doi.org" "168.63.129.16" || FAILED_TESTS=$(($FAILED_TESTS + 1))
    confirm_dns_lookup_fails "google.com" "168.63.129.16" || FAILED_TESTS=$(($FAILED_TESTS + 1))
    confirm_dns_lookup_fails "facebook.com" "168.63.129.16" || FAILED_TESTS=$(($FAILED_TESTS + 1))
elif [ "$OUTBOUND_INTERNET" == "Allow" ]; then
    confirm_dns_lookup_succeeds "example.com" "168.63.129.16" || FAILED_TESTS=$(($FAILED_TESTS + 1))
    confirm_dns_lookup_succeeds "doi.org" "168.63.129.16" || FAILED_TESTS=$(($FAILED_TESTS + 1))
    confirm_dns_lookup_succeeds "google.com" "168.63.129.16" || FAILED_TESTS=$(($FAILED_TESTS + 1))
    confirm_dns_lookup_succeeds "facebook.com" "168.63.129.16" || FAILED_TESTS=$(($FAILED_TESTS + 1))
fi

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n *** SUCCESS: All tests passed! ***"
else
    echo -e "\n *** ERROR: $FAILED_TESTS test(s) failed! ***"
fi
