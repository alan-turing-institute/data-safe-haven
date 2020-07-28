#! /bin/bash
# Test "cvxopt" as it is an early package on the Tier-3 whitelist (in the "00/02" package directory) and is not pre-installed
# Test "reportlab" as it a late package on the Tier-3 whitelist (in the "ff/fb" package directory) and is not pre-installed
# Test "abed" and "zope.interface" which are alphabetically early and late in the Tier-3 list and are not pre-installed
packages=("abed" "cvxopt" "reportlab" "zope.interface")

# Install sample packages to local user library
OUTCOME=0
for package in "${packages[@]}"; do
    echo "Attempting to install $package"
    failure=0
    pip install $package --user --quiet || failure=1
    if [ $failure -eq 1 ]; then
        echo "... $package installation failed"
        OUTCOME=1
    else
        echo "... $package installation succeeded"
    fi
done

if [ $OUTCOME -eq 0 ]; then
    echo "PyPI working OK"
else
    echo "PyPI installation failed"
fi
