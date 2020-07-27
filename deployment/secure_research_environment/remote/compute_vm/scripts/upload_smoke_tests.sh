#! /bin/bash

# Initialise the home directory, removing old files
mkdir -p /opt/installation
cd /opt/installation
rm -rf smoke_tests*
echo "$PAYLOAD" | base64 -d > smoke_tests.zip

# Unzip and remove the zip file
unzip smoke_tests.zip > /dev/null 2>&1
rm -rf smoke_tests.zip

# Update file permissions
chmod -R 644 smoke_tests/
chmod ugo+x smoke_tests/ smoke_tests/tests/ smoke_tests/package_lists/
chmod ugo+rx smoke_tests/tests/*.{jl,py,sh,R}

# Install bats
git clone https://github.com/bats-core/bats-core /opt/bats/bats-core
git clone https://github.com/bats-core/bats-support /opt/bats/bats-support
git clone https://github.com/bats-core/bats-assert /opt/bats/bats-assert
git clone https://github.com/bats-core/bats-file /opt/bats/bats-file
/opt/bats/bats-core/install.sh /usr/local

# Show final outputs
ls -alh /opt/installation/smoke_tests/*
