#! /usr/bin/env bash

# Ensure that default admin user exists
until su-exec "$USER" /usr/local/bin/gitea admin user list --admin | grep "{{admin_username}}" > /dev/null 2>&1; do
    echo "$(date -Iseconds) Attempting to create default admin user '{{admin_username}}'..." | tee -a /var/log/configuration
    su-exec "$USER" /usr/local/bin/gitea admin user create --admin --username "{{admin_username}}" --random-password --random-password-length 20 --email "{{admin_email}}" 2> /dev/null
    sleep 1
done

# Ensure that LDAP authentication is enabled
until su-exec "$USER" /usr/local/bin/gitea admin auth list | grep "DataSafeHavenLDAP" > /dev/null 2>&1; do
    echo "$(date -Iseconds) Attempting to register LDAP authentication..." | tee -a /var/log/configuration
    su-exec "$USER" /usr/local/bin/gitea admin auth add-ldap \
        --name DataSafeHavenLDAP \
        --bind-dn "{{ldap_bind_dn}}" \
        --bind-password "{{ldap_search_password}}" \
        --security-protocol "unencrypted" \
        --host "{{ldap_server_ip}}" \
        --port "389" \
        --user-search-base "{{ldap_user_search_base}}" \
        --user-filter "(&(objectClass=user)(memberOf=CN={{ldap_security_group_name}},OU=Data Safe Haven Security Groups,{{ldap_root_dn}})(sAMAccountName=%[1]s))" \
        --email-attribute "mail"
    sleep 1
done
