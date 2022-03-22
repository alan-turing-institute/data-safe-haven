#! /bin/bash

# Load libraries
. /opt/bitnami/scripts/liblog.sh
. /opt/bitnami/scripts/libopenldap.sh

# Start LDAP
info "Starting LDAP"
ldap_start_bg
while ! is_ldap_running; do sleep 1; done

# Update ACLs
info "Updating ACLs"
ldapmodify -Y EXTERNAL -H "ldapi:///" -f "/docker-entrypoint-initdb.d/acls.ldif"

# Stop LDAP
info "Stopping LDAP"
ldap_stop
while is_ldap_running; do sleep 1; done