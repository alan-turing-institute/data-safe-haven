#! /bin/bash

# Require three arguments: remote name, debfile name and sha256 hash
if [ $# -ne 3 ]; then
    echo "FATAL: Incorrect number of arguments"
    exit 1
fi
PACKAGE_REMOTE=$1
PACKAGE_DEBFILE=$2
PACKAGE_HASH=$3

# Download and verify the .deb file
echo "Downloading and verifying deb file ${PACKAGE_DEBFILE}"
mkdir -p /tmp/build/
wget -nv "${PACKAGE_REMOTE}/${PACKAGE_DEBFILE}" -P /tmp/build/
ls -alh "/tmp/build/${PACKAGE_DEBFILE}"
echo "$PACKAGE_HASH /tmp/build/${PACKAGE_DEBFILE}" > "/tmp/${PACKAGE_DEBFILE}_sha256.hash"
if [ "$(sha256sum -c "/tmp/${PACKAGE_DEBFILE}_sha256.hash" | grep FAILED)" != "" ]; then
    echo "FATAL: Checksum did not match expected for $PACKAGE_DEBFILE"
    exit 1
fi

# Wait until the package repository is not in use
while ! apt-get check >/dev/null 2>&1; do
    echo "Waiting for another installation process to finish..."
    sleep 1
done

# Install and cleanup
echo "Installing deb file: ${PACKAGE_DEBFILE}"
apt install -y "/tmp/build/${PACKAGE_DEBFILE}"
echo "Cleaning up"
rm "/tmp/build/${PACKAGE_DEBFILE}"
