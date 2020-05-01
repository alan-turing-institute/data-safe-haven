#! /bin/bash

# Deprovision this VM
echo -e "\n$(date +'%Y-%m-%d %H:%M:%S'): Calling deprovisioner on this VM"
waagent -deprovision+user -force 2>&1

# Fix internet connectivity that is broken by waagent deprovisioning (needed in older Ubuntu versions)
echo -e "\n$(date +'%Y-%m-%d %H:%M:%S'): Fixing internet connectivity"
if [ ! -e /etc/resolv.conf ]; then ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf; fi

# Remove execute permissions from this file
echo -e "\n$(date +'%Y-%m-%d %H:%M:%S'): Removing execute permissions from this script"
chmod ugo-x /installation/deprovision_vm.sh
ls -alh /installation/deprovision_vm.sh