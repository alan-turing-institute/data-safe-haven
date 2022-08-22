#! /bin/bash

echo "Update known hosts on the external server to allow connections to the internal server..."
mkdir -p /home/mirrordaemon/.ssh
echo "$1" >> /home/mirrordaemon/.ssh/known_hosts
ssh-keygen -H -f /home/mirrordaemon/.ssh/known_hosts 2>&1
chown mirrordaemon:mirrordaemon /home/mirrordaemon/.ssh/known_hosts
rm /home/mirrordaemon/.ssh/known_hosts.old 2> /dev/null
echo "This server currently posseses fingerprint for the following internal mirrors..."
cat /home/mirrordaemon/.ssh/known_hosts

echo "Update known IP addresses on the external server to schedule pushing to the internal server..."
echo "$2" >> /home/mirrordaemon/internal_mirror_ip_addresses.txt
cp /home/mirrordaemon/internal_mirror_ip_addresses.txt /home/mirrordaemon/internal_mirror_ip_addresses.bak
sort /home/mirrordaemon/internal_mirror_ip_addresses.bak | uniq > /home/mirrordaemon/internal_mirror_ip_addresses.txt
rm -f /home/mirrordaemon/internal_mirror_ip_addresses.bak
echo "This server is currently aware of internal mirrors at the following locations..."
cat /home/mirrordaemon/internal_mirror_ip_addresses.txt
