#! /usr/bin/env bash

# Ensure that default admin user exists
until su-exec "$USER" /usr/local/bin/gitea admin user list --admin | grep "{{admin_username}}" > /dev/null 2>&1; do
    echo "$(date -Iseconds) Attempting to create default admin user '{{admin_username}}'..." | tee -a /var/log/configuration
    su-exec "$USER" /usr/local/bin/gitea admin user create --admin --username "{{admin_username}}" --random-password --random-password-length 20 --email "{{admin_email}}" 2> /dev/null
    sleep 1
done
