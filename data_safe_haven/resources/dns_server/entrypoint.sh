#! /usr/bin/env sh

# Copy the read-only config file to the expected location
CONFIG_TARGET="/opt/adguardhome/conf/AdGuardHome.yaml"
echo "$(date '+%Y/%m/%d %H:%M:%S.000000') [info] Copying configuration file to ${CONFIG_TARGET}."
mkdir -p /opt/adguardhome/conf
cp /opt/adguardhome/custom/AdGuardHome.yaml "$CONFIG_TARGET"

# Run the usual entrypoint with command line arguments
if [ $# -gt 0 ]; then
    echo "$(date '+%Y/%m/%d %H:%M:%S.000000') [info] Running AdGuardHome with arguments: $*."
    /opt/adguardhome/AdGuardHome "$@"
else
    echo "$(date '+%Y/%m/%d %H:%M:%S.000000') [info] Running AdGuardHome with default arguments."
    /opt/adguardhome/AdGuardHome --no-check-update -c /opt/adguardhome/conf/AdGuardHome.yaml -w /opt/adguardhome/work
fi

