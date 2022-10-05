#! /bin/bash
# shellcheck disable=SC1091

# We need to test packages that are:
# - *not* pre-installed
# - on the tier-3 list (so we can test all tiers)
# - alphabetically early and late (so we can test the progress of the mirror synchronisation)
installable_packages=("{{SmokeTests.PyPIPackageFirst}}" "{{SmokeTests.PyPIPackageLast}}")
uninstallable_packages=("awscli")

# Set up a virtual environment for testing
TEST_INSTALL_PATH="${HOME}/test-repository-python"
rm -rf "$TEST_INSTALL_PATH"
python -m venv "$TEST_INSTALL_PATH"
source "${TEST_INSTALL_PATH}/bin/activate"
pip install --upgrade pip --quiet

# Install sample packages to local user library
OUTCOME=0
for package in "${installable_packages[@]}"; do
    echo "Attempting to install ${package}..."
    if (pip install "$package" --quiet); then
        echo "... $package installation succeeded"
    else
        echo "... $package installation failed"
        OUTCOME=1
    fi
done
# If requested, demonstrate that installation fails for packages *not* on the approved list
TEST_FAILURE={{SmokeTests.TestFailures}}
if [ $TEST_FAILURE -eq 1 ]; then
    for package in "${uninstallable_packages[@]}"; do
        echo "Attempting to install ${package}..."
        if (pip install "$package" --quiet); then
            echo "... $package installation unexpectedly succeeded!"
            OUTCOME=1
        else
            echo "... $package installation failed as expected"
        fi
    done
fi
rm -rf "$TEST_INSTALL_PATH"

if [ $OUTCOME -eq 0 ]; then
    echo "All package installations behaved as expected"
else
    echo "One or more package installations did not behave as expected!"
fi
