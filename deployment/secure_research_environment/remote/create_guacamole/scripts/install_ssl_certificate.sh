#! /bin/bash
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables
# It expects the following parameters:
#     USER_FRIENDLY_FQDN
#     CERT_THUMBPRINT

sudo rm -rf /opt/ssl/conf/live/${USER_FRIENDLY_FQDN}/*
sudo cp /var/lib/waagent/${CERT_THUMBPRINT}.crt /opt/ssl/conf/live/${USER_FRIENDLY_FQDN}/fullchain.pem
sudo cp /var/lib/waagent/${CERT_THUMBPRINT}.prv /opt/ssl/conf/live/${USER_FRIENDLY_FQDN}/privkey.pem
ls -alh /opt/ssl/conf/live/${USER_FRIENDLY_FQDN}/
docker-compose -f /opt/guacamole/docker-compose.yml up --force-recreate -d