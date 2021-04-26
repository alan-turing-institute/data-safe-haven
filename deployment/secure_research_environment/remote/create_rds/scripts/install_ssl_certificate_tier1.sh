#! /bin/bash
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables
# It expects the following parameters:
#     CERT_THUMBPRINT

sudo mkdir -p /opt/ssl
sudo chmod 0700 /opt/ssl
sudo rm -rf /opt/ssl/letsencrypt*
sudo cp /var/lib/waagent/${CERT_THUMBPRINT}.crt /opt/ssl/letsencrypt.cert
sudo cp /var/lib/waagent/${CERT_THUMBPRINT}.prv /opt/ssl/letsencrypt.key
sudo chown -R root:root /opt/ssl/
sudo chmod 0600 /opt/ssl/*.*
ls -alh /opt/ssl/