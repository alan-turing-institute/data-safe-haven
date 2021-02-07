#! /bin/bash

# Update file permissions
chmod -R 644 /opt/verification/smoke_tests/
chmod ugo+x /opt/verification/smoke_tests/ /opt/verification/smoke_tests/tests/ /opt/verification/smoke_tests/package_lists/
chmod ugo+rx /opt/verification/smoke_tests/tests/*.{jl,py,sh,R}

# If packages lists were uploaded during the the build then we should use those
if [ -n "$(ls -A /opt/build/packages 2>/dev/null)" ]; then
    rm -rf /opt/verification/smoke_tests/package_lists/*
    ln -s /opt/build/packages/* /opt/verification/smoke_tests/package_lists/
fi

# Show final outputs
ls -alh /opt/verification/smoke_tests/*
