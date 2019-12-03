#!/bin/bash
# $ldapPassword must be present as an environment variable
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables
echo "Previous LDAP password '$(cat /etc/ldap.secret)''"
echo $ldapPassword > /etc/ldap.secret
echo "New LDAP password '$(cat /etc/ldap.secret)''"
