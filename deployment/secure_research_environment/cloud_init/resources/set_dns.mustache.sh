#! /bin/bash

# Ensure that the correct DNS servers are being used
sed -i -e "s/^[#]*DNS=.*/DNS={{shm.dc.ip}}/" -e "s/^[#]*FallbackDNS=.*/FallbackDNS={{shm.dcb.ip}}/" -e "s/^[#]Domains=.*/Domains={{shm.domain.fqdnLower}}/" /etc/systemd/resolved.conf

# Add systemd-resolved to list of services to start on boot
systemctl enable systemd-resolved

# Restart systemd networking
systemctl daemon-reload
systemctl restart systemd-networkd
systemctl restart systemd-resolved

# Check DNS settings
ln -rsf /run/systemd/resolve/resolv.conf /etc/resolv.conf
grep -v "^#" /etc/resolv.conf
