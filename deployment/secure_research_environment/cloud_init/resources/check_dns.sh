#! /bin/bash

# Add systemd-resolved to list of services to start on boot
systemctl enable systemd-resolved

# Restart systemd networking
systemctl daemon-reload
systemctl restart systemd-networkd
systemctl restart systemd-resolved

# Output current settings
grep -v -e '^[[:space:]]*$' /etc/resolv.conf | grep -v "^#" | sed 's|^| /etc/resolv.conf |'

# Check DNS settings
systemd-resolve --status
