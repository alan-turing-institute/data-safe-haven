#!/bin/bash
# $LDAP_USER must be present as an environment variable
# $DOMAIN_LOWER must be present as an environment variable
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

# Write config to placeholder used by cloud-init (to ensure consistency of this copy)
sudo echo $HACKMD_CONFIG > /tmp/docker-compose-hackmd.yml
# Copy config placeholder to location used by docker
sudo cp /docker-compose-hackmd.yml /src/docker-hackmd/docker-compose.yml
echo "HackMD configuration updated"
sudo docker-compose -f /src/docker-hackmd/docker-compose.yml up -d
echo "HackMD restarted"
