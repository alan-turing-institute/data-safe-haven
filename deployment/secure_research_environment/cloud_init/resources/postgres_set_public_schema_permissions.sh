#! /bin/bash
# Set appropriate permissions on public schema
# - Remove privileges from PUBLIC (everyone)
# - Create the 'data' schema belonging to data-admins and grant read access to research users
# - Grant all privileges on the 'public' schema to research users
# - Grant superuser privileges to sysadmins
echo ">=== Setting appropriate permissions on public schema... ===<"
sudo -i -u postgres psql -f /opt/configuration/create-postgres-triggers.sql