#!/bin/bash
# $LDAP_USER must be present as an environment variable
# $DOMAIN_LOWER must be present as an environment variable
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

create_role(){
    local ROLE=$1
    # Check if role exists and create if it does not
    (sudo -i -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${ROLE}'" | grep -q 1 \
        && echo "Role '${ROLE}' already exists, skipping creation.") \
    || (sudo -i -u postgres psql -q -c "CREATE ROLE ${ROLE};" \
        && echo "Role '${ROLE}' created.")
}

create_user(){
    local USER=$1
    local ROLE=$2
    local PWD=$3
    # Check if dbadmin user exists and (a) create if it does not or (ii) update its password if it does
    (sudo -i -u postgres psql -tc "SELECT 1 FROM pg_user WHERE usename='${USER}'" | grep -q 1 \
        && sudo -i -u postgres psql -q -c "ALTER USER ${USER} WITH INHERIT PASSWORD '${PWD}';" \
        && echo "User '${USER}' already exists - password reset to value provided.") \
    || (sudo -i -u postgres psql -q -c "CREATE USER ${USER} IN ROLE ${ROLE} INHERIT PASSWORD '${PWD}';" \
        && echo "User '${USER}' created.")
}

create_role "${DBADMINROLE}"
create_role "${DBWRITERROLE}"
create_role "${DBREADERROLE}"
create_user "${DBADMINUSER}" "${DBADMINROLE}" "${DBADMINPWD}"
create_user "${DBWRITERUSER}" "${DBWRITERROLE}" "${DBWRITERPWD}"
create_user "${DBREADERUSER}" "${DBREADERROLE}" "${DBREADERPWD}"

# Ensure admin user has create rights for Databases and Roles
sudo -i -u postgres psql -q -c "ALTER USER ${DBADMINUSER} WITH CREATEDB CREATEROLE;" \
    && echo "User '${DBADMINUSER}' granted rights to create databases and users / roles"

# Show current user and roles tables
echo "\nUSERS:"
sudo -i -u postgres psql -q -c "SELECT * FROM pg_user"
echo "ROLES:"
sudo -i -u postgres psql -q -c "SELECT rolname, rolsuper, rolinherit, rolinherit, rolcreatedb, rolcanlogin, oid FROM pg_roles"

