#! /bin/bash
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables
# It expects the following parameters:
#     ldapSearchPasswordB64 (Base-64 encoded password for the LDAP search user account)

echo "Resetting LDAP password in /etc/ldap.secret..."
echo $ldapSearchPasswordB64 | base64 -d > /etc/ldap.secret
