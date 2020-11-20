#! /bin/bash

# Update resolv.conf
echo ">=== Updating DNS settings in /etc/resolv.conf... ===<"
rm /etc/resolv.conf
sed -i -e "s/^#DNS=.*/DNS=/" -e "s/^#FallbackDNS=.*/FallbackDNS=/" -e "s/^#Domains=.*/Domains=<shm-fqdn-lower>/" /etc/systemd/resolved.conf
ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

# Output current settings to check that they are correct
echo ">=== /etc/resolv.conf ===<"
grep -v "^#" /etc/resolv.conf | grep -v "^$"
echo ">=== end of /etc/resolv.conf ===<"

# Add systemd-resolved to list of services to start on boot
systemctl enable systemd-resolved