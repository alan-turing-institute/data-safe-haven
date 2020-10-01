#!/bin/sh

# Get command line arguments
if [ $# -ne 5 ]; then
    echo "$(basename $0) requires five arguments!";
fi
DOMAIN_FQDN_LOWER=$1
DOMAIN_JOIN_OU=$2
DOMAIN_JOIN_USER=$3
VM_HOSTNAME=$4
VM_IPADDRESS=$5

# Check timezone and NTP server
echo ">=== Checking timezone... ===<"
echo "Date:     $(date)"
echo "Timezone: $(timedatectl | grep "Time zone" | cut -d ':' -f 2 | xargs)"
echo ">=== Checking NTP servers... ===<"
grep NTP /etc/systemd/timesyncd.conf.d/cloud-init.conf

# Add FQDN to the hostname file (without using the FQDN we cannot set service principals when joining the Windows domain)
echo ">=== Setting hostname in /etc/hostname... ===<"
hostnamectl set-hostname ${VM_HOSTNAME}.${DOMAIN_FQDN_LOWER}
cat /etc/hostname

# Update DNS settings
echo ">=== Updating DNS settings in /etc/resolv.conf... ===<"
rm /etc/resolv.conf
sed -i -e "s/^#DNS=.*/DNS=/" -e "s/^#FallbackDNS=.*/FallbackDNS=/" -e "s/^#Domains=.*/Domains=${DOMAIN_FQDN_LOWER}/" /etc/systemd/resolved.conf
ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
# Restart systemd-resolved to ensure that these settings get propagated
systemctl enable systemd-resolved
systemctl restart systemd-resolved
sleep 10
systemctl status systemd-resolved
# Output current settings to check that they are correct
grep -v "^#" /etc/resolv.conf | grep -v "^$"

# Add localhost information to /etc/hosts
echo ">=== Adding ${VM_HOSTNAME} [${VM_IPADDRESS}] to /etc/hosts... ===<"
HOST_INFORMATION="${VM_IPADDRESS} ${VM_HOSTNAME} ${VM_HOSTNAME}.${DOMAIN_FQDN_LOWER}"
sed -i "/127.0.0.1/ a $HOST_INFORMATION" /etc/hosts
cat /etc/hosts

# Initialise sssd
echo ">=== Setting up basic sssd configuration... ===<"
cp /usr/share/doc/sssd-common/examples/sssd-example.conf /etc/sssd/sssd.conf
chmod 0600 /etc/sssd/sssd.conf
systemctl enable sssd

# Join realm
echo ">=== Joining realm... ===<"
cat /etc/domain-join.secret | realm join --verbose --computer-ou="${DOMAIN_JOIN_OU}" -U ${DOMAIN_JOIN_USER} ${DOMAIN_FQDN_LOWER} --install=/
