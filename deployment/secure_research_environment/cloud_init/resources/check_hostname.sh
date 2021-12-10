#! /bin/bash

# Check /etc/hostname
grep -v -e '^[[:space:]]*$' /etc/hostname | grep -v "^#" | sed 's|^| /etc/hostname |'

# Check /etc/hosts
grep -v -e '^[[:space:]]*$' /etc/hosts | grep -v "^#" | sed 's|^| /etc/hosts |'
