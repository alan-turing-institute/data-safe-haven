#! /bin/bash
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables
# It expects the following parameters:
#     USER_FRIENDLY_FQDN
#     CERT_THUMBPRINT

# Remove existing certificates
sudo rm -rf /opt/ssl/conf/live/${USER_FRIENDLY_FQDN}/*
# Import the certificates from the VM secret store
sudo cp /var/lib/waagent/${CERT_THUMBPRINT}.crt /opt/ssl/conf/live/${USER_FRIENDLY_FQDN}/cert.pem
sudo cp /var/lib/waagent/${CERT_THUMBPRINT}.prv /opt/ssl/conf/live/${USER_FRIENDLY_FQDN}/privkey.pem
# Create a certificate chain from the certificate and intermediate certificate
cd /opt/ssl/conf/live/${USER_FRIENDLY_FQDN}/
if [ ! -e lets-encrypt-r3.pem ]; then
    wget https://letsencrypt.org/certs/lets-encrypt-r3.pem
fi
cat cert.pem lets-encrypt-r3.pem > fullchain.pem
ls -alh /opt/ssl/conf/live/${USER_FRIENDLY_FQDN}/
# Force docker services to reload
docker-compose -f /opt/guacamole/docker-compose.yml up --force-recreate -d
