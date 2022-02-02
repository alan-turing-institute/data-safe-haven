#! /bin/bash
# Restart the postgresql service
echo ">=== Restarting postgres... ===<"
systemctl restart postgresql@12-main
sleep 10
systemctl status postgresql@12-main

# Show postgres users and roles
echo ">=== List postgres users and roles... ===<"
echo "USERS:"
sudo -i -u postgres psql -q -c "SELECT * FROM pg_user;"
echo "ROLES:"
sudo -i -u postgres psql -q -c "SELECT rolname, rolsuper, rolinherit, rolinherit, rolcreatedb, rolcanlogin, oid FROM pg_roles;"
echo "SCHEMAS:"
sudo -i -u postgres psql -q -c "SELECT schema_name FROM information_schema.schemata;"