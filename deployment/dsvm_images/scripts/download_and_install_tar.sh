#! /bin/bash

# Require one arguments: config file identifier
if [ $# -ne 1 ]; then
    exit 1
fi
PACKAGE_NAME=$1

# Ensure that the config file exists
CONFIG_FILE="/installation/tarinfo_${PACKAGE_NAME}.yaml"
if [ ! -e $CONFIG_FILE ]; then
    exit 2
fi

# Parse the config file
PACKAGE_HASH=$(grep "hash:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||')
PACKAGE_VERSION_MAJOR=$(grep "version_major:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||')
PACKAGE_VERSION=$(grep "version:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||' | sed "s/|VERSION_MAJOR|/$PACKAGE_VERSION_MAJOR/")
PACKAGE_PATHDIR=$(grep "pathdir:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||' | sed "s/|VERSION|/$PACKAGE_VERSION/")
PACKAGE_TARFILE=$(grep "tarfile:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||' | sed "s/|VERSION|/$PACKAGE_VERSION/" | sed "s/|PATHDIR|/$PACKAGE_PATHDIR/")
PACKAGE_REMOTE=$(grep "remote:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||' | sed "s/|VERSION_MAJOR|/$PACKAGE_VERSION_MAJOR/" | sed "s/|VERSION|/$PACKAGE_VERSION/" | sed "s/|TARFILE|/$PACKAGE_TARFILE/")
PACKAGE_EXECUTABLE=$(grep "executable:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||')

# Download and verify the .deb file
echo "Downloading and verifying tar file..."
mkdir -p /opt/${PACKAGE_NAME}
wget $PACKAGE_REMOTE -P /opt/${PACKAGE_NAME}
ls -alh /opt/${PACKAGE_NAME}/${PACKAGE_TARFILE}
echo "$PACKAGE_HASH /opt/${PACKAGE_NAME}/${PACKAGE_TARFILE}" > /tmp/${PACKAGE_NAME}_sha512.hash
if [ "$(sha256sum -c /tmp/${PACKAGE_NAME}_sha512.hash | grep FAILED)" != "" ]; then
    echo "Checksum did not match expected for $PACKAGE_NAME"
    exit 1
fi

# Install and cleanup
echo "Installing tar file..."
cd /opt/${PACKAGE_NAME}
tar -zxf ${PACKAGE_TARFILE}
rm -rf ${PACKAGE_TARFILE}
PATH=$PATH:/opt/${PACKAGE_NAME}/${PACKAGE_PATHDIR}/bin

# Check whether the installation was successful
if [ "$(which ${PACKAGE_EXECUTABLE})" = "" ]; then echo "Could not install ${PACKAGE_NAME}"; exit 1; fi