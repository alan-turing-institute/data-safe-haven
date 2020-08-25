#! /bin/bash

# Clean up temporary files
rm -rf /root/* /root/.[a-zA-Z_]* /tmp/* /tmp/.[a-zA-Z_]*

# Deprovision this VM
echo -e "\n$(date +'%Y-%m-%d %H:%M:%S'): Calling deprovisioner on this VM"
waagent -deprovision+user -force 2>&1

# Fix internet connectivity that is broken by waagent deprovisioning (needed in older Ubuntu versions)
echo -e "\n$(date +'%Y-%m-%d %H:%M:%S'): Fixing internet connectivity"
if [ ! -e /etc/resolv.conf ]; then ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf; fi

# Remove execute permissions from this file
echo -e "\n$(date +'%Y-%m-%d %H:%M:%S'): Removing execute permissions from this script"
chmod ugo-x /opt/build/deprovision_vm.sh
ls -alh /opt/build/deprovision_vm.sh