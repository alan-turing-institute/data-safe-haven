#! /bin/bash
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

# Put the tests into the correct filesystem location
mv /opt/tests/smoke_tests/* /opt/tests
rmdir /opt/tests/smoke_tests/

# Update file permissions
chmod -R 644 /opt/tests/
chmod ugo+x /opt/tests/ /opt/tests/tests/ /opt/tests/package_lists/
chmod ugo+rx /opt/tests/tests/*.{jl,py,sh,R}

# If packages lists were uploaded during the the build then we should use those
if [ -n "$(ls -A /opt/build/packages 2>/dev/null)" ]; then
    rm -rf /opt/tests/package_lists/*
    ln -s /opt/build/packages/* /opt/tests/package_lists/
fi

# Show final outputs
ls -alh /opt/tests/*
