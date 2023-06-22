#! /usr/bin/env sh

# Add configuration as an s6 target
mkdir -p /etc/s6/setup
rm /etc/s6/setup/run 2> /dev/null
ln -s /app/custom/configure.sh /etc/s6/setup/run

# Run the usual entrypoint
/usr/bin/entrypoint
