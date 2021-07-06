#! /bin/bash
if [ $# -ne 3 ]; then
    echo "FATAL: Incorrect number of arguments"
    exit 1
fi
HOSTNAME=$1
IP_ADDRESS=$2
SHM_FQDN=$3

# Add FQDN to the hostname file (without using the FQDN we cannot set service principals when joining the Windows domain)
echo ">=== Setting hostname... ===<"
hostnamectl set-hostname "${HOSTNAME}.${SHM_FQDN}"
echo ">=== /etc/hostname ===<"
cat /etc/hostname
echo ">=== end of /etc/hostname ===<"

# Add localhost information to /etc/hosts
echo ">=== Adding ${HOSTNAME} [${IP_ADDRESS}] to /etc/hosts... ===<"
echo "${IP_ADDRESS} ${HOSTNAME} $(cat /etc/hostname)" > /etc/hosts.tmp
grep -v "${HOSTNAME}" /etc/hosts >> /etc/hosts.tmp
mv /etc/hosts.tmp /etc/hosts

# Output current settings to check that they are correct
echo ">=== /etc/hosts ===<"
grep -v "^$" /etc/hosts
echo ">=== end of /etc/hosts ===<"
