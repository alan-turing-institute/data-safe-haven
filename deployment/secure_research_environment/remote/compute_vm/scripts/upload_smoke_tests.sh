#! /bin/bash

# Initialise the home directory, removing old files
mkdir -p /opt/verification
cd /opt/verification
rm -rf smoke_tests*
echo "$PAYLOAD" | base64 -d > smoke_tests.zip

# Unzip and remove the zip file
unzip smoke_tests.zip > /dev/null 2>&1
rm -rf smoke_tests.zip

# Update file permissions
chmod -R 644 smoke_tests/
chmod ugo+x smoke_tests/ smoke_tests/tests/ smoke_tests/package_lists/
chmod ugo+rx smoke_tests/tests/*.{jl,py,sh,R}

# Show final outputs
ls -alh /opt/verification/smoke_tests/*
