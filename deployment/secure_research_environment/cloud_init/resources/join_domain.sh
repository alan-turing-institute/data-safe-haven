#! /bin/sh

# Get command line arguments
if [ $# -ne 4 ]; then
    echo "$(basename $0) requires four arguments!";
fi
DOMAIN_FQDN_LOWER=$1
DOMAIN_JOIN_OU=$2
DOMAIN_JOIN_USER=$3
VM_HOSTNAME=$4

# Ensure that  /etc/resolv.conf has the correct settings
echo "Ensuring that /etc/resolv.conf has the correct settings..."
sed -i -e "s/^[#]DNS=.*/DNS=/" -e "s/^[#]FallbackDNS=.*/FallbackDNS=/" -e "s/^[#]Domains=.*/Domains=${DOMAIN_FQDN_LOWER}/" /etc/systemd/resolved.conf
ln -rsf /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl restart systemd-resolved

# Check that hostname is correct
echo "Ensuring that hostname is correct..."
if [ "$(hostnamectl --static)" != "${VM_HOSTNAME}.${DOMAIN_FQDN_LOWER}" ] || (! grep -q "$VM_HOSTNAME" /etc/hosts); then
    /opt/configuration/configure-hostname.sh > /dev/null
fi

# Check the NTP service
echo "Ensuring that NTP service is running..."
if [ "$(systemctl is-active systemd-timesyncd)" != "active" ] && [ "$(systemctl is-enabled systemd-timesyncd)" = "enabled" ]; then
    systemctl restart systemd-timesyncd
    sleep 10
fi
if [ "$(systemctl is-active chronyd)" != "active" ] && [ "$(systemctl is-enabled chronyd)" = "enabled" ]; then
    systemctl restart chronyd
    sleep 10
fi

# Check the DNS service
echo "Ensuring that DNS service is running..."
if [ "$(systemctl is-active systemd-resolved)" != "active" ]; then
    systemctl restart systemd-resolved
    sleep 10
fi

# Check the SSSD service
echo "Ensuring that SSSD service is running..."
if [ "$(systemctl is-active sssd)" != "active" ]; then
    if [ -f /etc/sssd/sssd.conf ]; then rm -f /etc/sssd/sssd.conf; fi
    systemctl restart sssd
    sleep 10
fi

# Join realm - creating the SSSD config if it does not exist
echo "Joining realm '${DOMAIN_FQDN_LOWER}'..."
/usr/sbin/realm leave 2> /dev/null
cat /etc/domain-join.secret | /usr/sbin/realm join --verbose --computer-ou="${DOMAIN_JOIN_OU}" -U "${DOMAIN_JOIN_USER}" "${DOMAIN_FQDN_LOWER}" --install=/ 2>&1

# Update SSSD settings
echo "Updating SSSD settings..."
sed -i -E 's|(access_provider = ).*|\1simple|' /etc/sssd/sssd.conf
systemctl restart sssd
