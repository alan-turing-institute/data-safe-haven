#! /bin/bash

# Initialise the home directory, removing old files
mkdir -p /home/${ADMIN_USERNAME}
cd /home/${ADMIN_USERNAME}
rm -rf smoke_tests*
echo "$PAYLOAD" | base64 -d > smoke_tests.zip

# Unzip and remove the zip file
unzip smoke_tests.zip
rm -rf smoke_tests.zip

# Update file permissions
chown -R ${ADMIN_USERNAME}:${ADMIN_USERNAME} /home/${ADMIN_USERNAME}
chmod -R 644 smoke_tests/
chmod ugo+x smoke_tests/ smoke_tests/tests/ smoke_tests/package_lists/
chmod u+x smoke_tests/tests/*.{py,sh,R}

# Show final outputs
ls -alh /home/${ADMIN_USERNAME}/smoke_tests/*
