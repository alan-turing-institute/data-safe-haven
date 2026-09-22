#! /usr/bin/env bash

# Ensure that default admin user exists
until su-exec "$USER" /usr/local/bin/gitea admin user list --admin | grep "{{admin_username}}" > /dev/null 2>&1; do
    echo "$(date -Iseconds) [mirror-manager] Attempting to create default admin user '{{admin_username}}'..." | tee -a /var/log/configuration
        su-exec "$USER" /usr/local/bin/gitea admin user create --admin --username "{{admin_username}}" --password "$ADMIN_SERVER_PASSWORD" --must-change-password=false --email "{{admin_email}}" 2> /dev/null
    sleep 1
done

echo "$(date -Iseconds) [mirror-manager] Attempting to set password for user '{{admin_username}}'..." | tee -a /var/log/configuration
su-exec "$USER" /usr/local/bin/gitea admin user change-password --username "{{admin_username}}" --password "$ADMIN_SERVER_PASSWORD" --must-change-password=false

# Ensure that the mirror user exists
until su-exec "$USER" /usr/local/bin/gitea admin user list | grep "{{mirror_username}}" > /dev/null 2>&1; do
    echo "$(date -Iseconds) [mirror-manager] Attempting to create default mirror user '{{mirror_username}}'..." | tee -a /var/log/configuration
    su-exec "$USER" /usr/local/bin/gitea admin user create --username "{{mirror_username}}" --password "$MIRROR_SERVER_PASSWORD" --must-change-password=false --email "{{mirror_email}}" 2> /dev/null
    sleep 1
done

echo "$(date -Iseconds) [mirror-manager] Users '{{mirror_username}}' and '{{admin_username}}' created successfully" | tee -a /var/log/configuration

echo "$(date -Iseconds) [mirror-manager]  Attempting to set password for user '{{mirror_username}}'..." | tee -a /var/log/configuration
su-exec "$USER" /usr/local/bin/gitea admin user change-password  --username "{{mirror_username}}" --password "$MIRROR_SERVER_PASSWORD" --must-change-password=false