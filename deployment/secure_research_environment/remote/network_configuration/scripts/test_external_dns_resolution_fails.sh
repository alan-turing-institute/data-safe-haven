#!/bin/bash
# Test DNS resolution lockdown

confirm_external_dns_lookup_fails () {
    FQDN=$1
    sudo systemd-resolve --flush-caches;
    NS_RESULT=$(nslookup $FQDN)
    if [ $? -eq 0 ]; then
        echo " [x] DNS lookup for '$FQDN' unexpectedly succeeded."
        echo "$NS_RESULT"
    else
        echo " [o] DNS lookup for '$FQDN' failed as expected."
    fi
}

confirm_internal_dns_lookup_succeeds () {
    FQDN=$1
    sudo systemd-resolve --flush-caches;
    NS_RESULT=$(nslookup $FQDN)
    if [ $? -eq 0 ]; then
        echo " [o] DNS lookup for '$FQDN' succeeded as expected."
    else
        echo " [o] DNS lookup for '$FQDN' unexpectedly failed."
        echo "$NS_RESULT"
    fi
}

echo " Testing DNS resolution lockdown"
echo " -------------------------------"
echo " $HOSTNAME> $(date +"%Y-%m-%dT%H:%M:%S")"

SHM_DOMAIN_FQDN="mortest.dsgroupdev.co.uk"
SHM_DC1_FQDN="DC1-SHM-MORTEST.mortest.dsgroupdev.co.uk"
SHM_DC2_FQDN="DC2-SHM-MORTEST.mortest.dsgroupdev.co.uk"
echo "Testing DNS lookup for internal FQDNs..."
confirm_internal_dns_lookup_succeeds "$SHM_DOMAIN_FQDN"
confirm_internal_dns_lookup_succeeds "$SHM_DC1_FQDN"
confirm_internal_dns_lookup_succeeds "$SHM_DC2_FQDN"

echo "Testing DNS lookup for non-existent external domains'..."
confirm_external_dns_lookup_fails "fail.example.com"

echo "Testing DNS lookup for resolvable external domains..."
confirm_external_dns_lookup_fails "example.com"
confirm_external_dns_lookup_fails "doi.org"
confirm_external_dns_lookup_fails "bbc.co.uk"
confirm_external_dns_lookup_fails "google.com"
confirm_external_dns_lookup_fails "facebook.com"
