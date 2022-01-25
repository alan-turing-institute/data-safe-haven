#! /bin/bash
# Generate a keytab and verify by getting a Kerberos ticket
echo ">=== Generating service principal credentials... ===<"
SERVICE_PRINCIPAL="POSTGRES/{{postgres.vmName}}.{{shm.domain.fqdnLower}}"
KEYTAB_PATH="/var/lib/postgresql/data/postgres.keytab"
install -g postgres -o postgres -d /var/lib/postgresql/data/ # create the directory with correct ownership
echo "ldapsearch -b '{{postgres.ldapPostgresServiceAccountDn}}' -h {{shm.dc.hostnameUpper}}.{{shm.domain.fqdnLower}} -D '{{{postgres.ldapSearchUserDn}}}' -W msDS-KeyVersionNumber"
KVNO=$(ldapsearch -b "{{postgres.ldapPostgresServiceAccountDn}}" -h {{shm.dc.hostnameUpper}}.{{shm.domain.fqdnLower}} -D "{{{postgres.ldapSearchUserDn}}}" -w $(cat /etc/ldap.secret) msDS-KeyVersionNumber | grep "msDS-KeyVersionNumber:" | cut -d' ' -f2)
echo "Current KVNO is $KVNO"
# Use the same encryption methods and ordering as ktpass on Windows. The Active Directory default is RC4-HMAC.
# NB. Kerberos will preferentially choose AES-256, but Active Directory does not support it without configuration changes. We therefore do not include it in the keytab
DESCRC="add_entry -password -p $SERVICE_PRINCIPAL -k $KVNO -e des-cbc-crc\n$(cat /etc/postgres-service-account.secret)"
DESMD5="add_entry -password -p $SERVICE_PRINCIPAL -k $KVNO -e des-cbc-md5\n$(cat /etc/postgres-service-account.secret)"
A4HMAC="add_entry -password -p $SERVICE_PRINCIPAL -k $KVNO -e arcfour-hmac\n$(cat /etc/postgres-service-account.secret)"
AES128="add_entry -password -p $SERVICE_PRINCIPAL -k $KVNO -e aes128-cts-hmac-sha1-96\n$(cat /etc/postgres-service-account.secret)"
printf "%b" "$DESCRC\n$DESMD5\n$A4HMAC\n$AES128\nwrite_kt $KEYTAB_PATH" | ktutil
echo "" # for appropriate spacing after the ktutil command
# Set correct permissions for the keytab file
chown postgres:postgres $KEYTAB_PATH
chmod 0400 $KEYTAB_PATH
echo ">=== Testing credentials with kinit... ===<"
echo "klist -e -t -k $KEYTAB_PATH"
klist -e -t -k $KEYTAB_PATH
echo "kinit -t $KEYTAB_PATH $SERVICE_PRINCIPAL"
kinit -t $KEYTAB_PATH $SERVICE_PRINCIPAL
klist
# Set the appropriate keytab file
sed -i "s|#krb_server_keyfile|krb_server_keyfile = '$KEYTAB_PATH'\n#krb_server_keyfile|g" /etc/postgresql/12/main/postgresql.conf
grep krb_server_keyfile /etc/postgresql/12/main/postgresql.conf