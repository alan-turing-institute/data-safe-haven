#!/bin/bash
# $LDAP_USER must be present as an environment variable
# $DOMAIN_LOWER must be present as an environment variable
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

# Check if admin role exists and create if it does not
(sudo -i -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DBADMINROLE}'" | grep -q 1 \
    && echo "Role '${DBADMINROLE}' already exists, skipping creation.") \
|| sudo -i -u postgres psql -c "CREATE ROLE admin WITH CREATEDB CREATEROLE;"
# Check if dbadmin user exists and (a) create if it does not or (ii) update its password if it does
(sudo -i -u postgres psql -tc "SELECT 1 FROM pg_user WHERE usename='${DBADMINUSER}'" | grep -q 1 \
    && echo "User '${DBADMINUSER}' already exists." \
    && sudo -i -u postgres psql -c "ALTER USER ${DBADMINUSER} WITH PASSWORD '${DBADMINPWD}';" \
    && echo "Password for user '${DBADMINUSER}' reset to provided value.") \
|| sudo -i -u postgres psql -c "CREATE USER dbadmin IN ROLE admin INHERIT PASSWORD '${DBADMINPWD}';"
# Show current user table
sudo -i -u postgres psql -c "SELECT * FROM pg_user"
