#! /usr/bin/env bash

BACKUP=$(echo "${BACKUP_B64}" | base64 --decode)
EGRESS=$(echo "${EGRESS_B64}" | base64 --decode)
INGRESS=$(echo "${INGRESS_B64}" | base64 --decode)

sed -i "s|^sasToken|sasToken ${BACKUP}|" /opt/configuration/credentials-backup.secret
sed -i "s|^sasToken|sasToken ${EGRESS}|" /opt/configuration/credentials-egress.secret
sed -i "s|^sasToken|sasToken ${INGRESS}|" /opt/configuration/credentials-ingress.secret

systemd restart backup.mount
systemd restart data.mount
systemd restart output.mount
