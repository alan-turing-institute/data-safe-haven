#! /bin/bash

# Add FQDN to the hostname file (without using the FQDN we cannot set service principals when joining the Windows domain)
echo ">=== Setting hostname in /etc/hostname... ===<"
hostnamectl set-hostname "<vm-hostname>.<shm-fqdn-lower>"

# Add localhost information to /etc/hosts
echo ">=== Adding <vm-hostname> [<vm-ipaddress>] to /etc/hosts... ===<"
echo "<vm-ipaddress> <vm-hostname> $(cat /etc/hostname)" > /etc/hosts.tmp
grep -v "<vm-hostname>" /etc/hosts >> /etc/hosts.tmp
mv /etc/hosts.tmp /etc/hosts

# Output current settings to check that they are correct
echo ">=== /etc/hosts ===<"
grep -v "^$" /etc/hosts
echo ">=== end of /etc/hosts ===<"
