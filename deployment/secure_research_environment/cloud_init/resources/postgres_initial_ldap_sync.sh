#! /bin/bash
echo ">=== Ensuring that LDAP sync has run... ===<"
sudo -i -u postgres pg_ldap_sync -c /etc/postgresql/12/main/pg-ldap-sync.yaml -vv 2>&1