#! /bin/bash

# Clean up temporary files
rm -rf /root/* /root/.[a-zA-Z_]* /tmp/* /tmp/.[a-zA-Z_]*

# Disconnect omsagent from default workspace if it exists
if [ -d "/opt/microsoft/omsagent/" ]; then
    # Disconnecting omsagent from default workspace
    echo "Connected workspaces:"
    /opt/microsoft/omsagent/bin/omsadmin.sh -l
    echo "Disconnecting omsagent from connected workspace:"
    /opt/microsoft/omsagent/bin/omsadmin.sh -X
else 
    echo "omsagent not found, continuing..."
fi

# Deprovision this VM
echo -e "\n$(date -u --iso-8601=seconds): Calling deprovisioner on this VM"
waagent -deprovision+user -force 2>&1

# Fix internet connectivity that is broken by waagent deprovisioning (needed in older Ubuntu versions)
echo -e "\n$(date -u --iso-8601=seconds): Fixing internet connectivity"
if [ ! -e /etc/resolv.conf ]; then ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf; fi

# Remove execute permissions from this file
echo -e "\n$(date -u --iso-8601=seconds): Removing execute permissions from this script"
chmod ugo-x /opt/build/deprovision_vm.sh
ls -alh /opt/build/deprovision_vm.sh