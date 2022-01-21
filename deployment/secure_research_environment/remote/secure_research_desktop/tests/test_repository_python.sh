#! /bin/bash
# shellcheck disable=SC1091

# We need to test packages that are:
# - *not* pre-installed
# - on the tier-3 list (so we can test all tiers)
# - alphabetically early and late (so we can test the progress of the mirror synchronisation)
packages=("absl-py" "zope.interface")

# Set up a virtual environment for testing
TEST_INSTALL_PATH="${HOME}/test-repository-python"
rm -rf "$TEST_INSTALL_PATH"
python -m venv "$TEST_INSTALL_PATH"
source "${TEST_INSTALL_PATH}/bin/activate"
pip install --upgrade pip

# Install sample packages to local user library
OUTCOME=0
for package in "${packages[@]}"; do
    echo "Attempting to install ${package}..."
    if (pip install "$package"); then
        echo "... $package installation succeeded"
    else
        echo "... $package installation failed"
        OUTCOME=1
    fi
done
rm -rf "$TEST_INSTALL_PATH"

if [ $OUTCOME -eq 0 ]; then
    echo "All packages installed successfully"
else
    echo "One or more package installations failed!"
fi
