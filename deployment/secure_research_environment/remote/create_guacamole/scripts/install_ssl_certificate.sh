#! /bin/bash
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables
# It expects the following parameters:
#     USER_FRIENDLY_FQDN
#     CERT_THUMBPRINT

# Remove existing certificates
sudo rm -rf "/opt/ssl/conf/live/${USER_FRIENDLY_FQDN}/*"

# Import the certificates from the VM secret store
sudo cp "/var/lib/waagent/${CERT_THUMBPRINT}.crt" "/opt/ssl/conf/live/${USER_FRIENDLY_FQDN}/cert.pem"
sudo cp "/var/lib/waagent/${CERT_THUMBPRINT}.prv" "/opt/ssl/conf/live/${USER_FRIENDLY_FQDN}/privkey.pem"

# Download the Let's Encrypt intermediate certificate
LETS_ENCRYPT_CERTIFICATE_PATH=/opt/ssl/lets-encrypt-r3.pem
if [ ! -e "$LETS_ENCRYPT_CERTIFICATE_PATH" ]; then
    echo "Downloading Let's Encrypt intermediate certificate..."
    wget -O "$LETS_ENCRYPT_CERTIFICATE_PATH" https://letsencrypt.org/certs/lets-encrypt-r3.pem 2>&1
fi

# Create a certificate chain from the certificate and intermediate certificate
echo "Creating fullchain certificate..."
cd "/opt/ssl/conf/live/${USER_FRIENDLY_FQDN}/" || exit 1
cat cert.pem "$LETS_ENCRYPT_CERTIFICATE_PATH" > fullchain.pem
ls -alh

# Force docker services to reload
docker-compose -f /opt/guacamole/docker-compose.yaml up --force-recreate -d 2>&1
