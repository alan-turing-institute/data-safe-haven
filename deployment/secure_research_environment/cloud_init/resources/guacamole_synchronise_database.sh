#! /bin/bash
echo "Running LDAP synchronisation..." | tee >(logger -t SafeHaven)
/usr/local/bin/pg_ldap_sync -vvv -c /opt/pg-ldap-sync/configuration.yaml 2>&1 | logger -t SafeHaven
echo "Updating database..." | tee >(logger -t SafeHaven)
su guacamoledaemon -c "docker compose -f /opt/guacamole/docker-compose.yaml exec -T postgres psql -U guacamole -f /scripts/db_update.sql" | logger -t SafeHaven
echo "Finished database synchronisation" | tee >(logger -t SafeHaven)
