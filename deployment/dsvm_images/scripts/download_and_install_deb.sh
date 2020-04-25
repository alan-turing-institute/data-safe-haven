#! /bin/bash

# Require one arguments: config file identifier
if [ $# -ne 1 ]; then
    exit 1
fi
PACKAGE_NAME=$1

# Ensure that the config file exists
CONFIG_FILE="/installation/debinfo_${PACKAGE_NAME}.yaml"
if [ ! -e $CONFIG_FILE ]; then
    exit 2
fi

# Parse the config file
PACKAGE_HASH=$(grep "hash:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||')
PACKAGE_VERSION=$(grep "version:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||')
PACKAGE_DEBFILE=$(grep "debfile:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||' | sed "s/|VERSION|/$PACKAGE_VERSION/")
PACKAGE_REMOTE=$(grep "remote:" $CONFIG_FILE | cut -d':' -f2-99 | sed 's|^ ||' | sed "s/|VERSION|/$PACKAGE_VERSION/" | sed "s/|DEBFILE|/$PACKAGE_DEBFILE/")

# Download and verify the .deb file
echo "Downloading and verifying deb file..."
mkdir -p /installation/
wget -nv $PACKAGE_REMOTE -P /installation/
ls -alh /installation/${PACKAGE_DEBFILE}
echo "$PACKAGE_HASH /installation/${PACKAGE_DEBFILE}" > /tmp/${PACKAGE_NAME}_sha512.hash
if [ "$(sha256sum -c /tmp/${PACKAGE_NAME}_sha512.hash | grep FAILED)" != "" ]; then
    echo "Checksum did not match expected for $PACKAGE_NAME"
    exit 1
fi

# Install and cleanup
echo "Installing deb file..."
gdebi --non-interactive /installation/${PACKAGE_DEBFILE}
rm /installation/${PACKAGE_DEBFILE}

# Check whether the installation was successful
if [ "$(which ${PACKAGE_NAME})" ]; then
    echo "Installed ${PACKAGE_NAME} ${PACKAGE_VERSION}"
else
    echo "Could not install ${PACKAGE_NAME}"
    exit 1
fi
