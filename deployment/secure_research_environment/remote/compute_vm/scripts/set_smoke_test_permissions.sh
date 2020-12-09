#! /bin/bash

# Update file permissions
chmod -R 644 /opt/verification/smoke_tests/
chmod ugo+x /opt/verification/smoke_tests/ /opt/verification/smoke_tests/tests/ /opt/verification/smoke_tests/package_lists/
chmod ugo+rx /opt/verification/smoke_tests/tests/*.{jl,py,sh,R}

# Show final outputs
ls -alh /opt/verification/smoke_tests/*
