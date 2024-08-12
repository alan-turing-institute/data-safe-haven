#! /bin/bash
# We need to test packages that are:
# - *not* pre-installed
# - on the tier-3 list (so we can test all tiers)
# - alphabetically early and late (so we can test the progress of the mirror synchronisation)
packages=("cli" "withr")
uninstallable_packages=("aws.s3")

# Create a temporary library directory
TEST_INSTALL_PATH="${HOME}/.local/bats-r-environment"
# TEST_INSTALL_PATH="${HOME}/test-repository-R"
# rm -rf "$TEST_INSTALL_PATH"
# mkdir -p "$TEST_INSTALL_PATH"

# Install sample packages to local user library
N_FAILURES=0
for package in "${packages[@]}"; do
    echo "Attempting to install ${package}..."
    Rscript -e "options(warn=-1); install.packages('${package}', lib='${TEST_INSTALL_PATH}', quiet=TRUE)"
    if (Rscript -e "library('${package}', lib.loc='${TEST_INSTALL_PATH}')"); then
        echo "... $package installation succeeded"
    else
        echo "... $package installation failed"
        N_FAILURES=$((N_FAILURES + 1))
    fi
done
# If requested, demonstrate that installation fails for packages *not* on the approved list
TEST_FAILURE=0
if [ $TEST_FAILURE -eq 1 ]; then
    for package in "${uninstallable_packages[@]}"; do
        echo "Attempting to install ${package}..."
        Rscript -e "options(warn=-1); install.packages('${package}', lib='${TEST_INSTALL_PATH}', quiet=TRUE)"
        if (Rscript -e "library('${package}', lib.loc='${TEST_INSTALL_PATH}')"); then
            echo "... $package installation unexpectedly succeeded!"
            N_FAILURES=$((N_FAILURES + 1))
        else
            echo "... $package installation failed as expected"
        fi
    done
fi
rm -rf "$TEST_INSTALL_PATH"

if [ $N_FAILURES -eq 0 ]; then
    echo "All package installations behaved as expected"
    exit 0
else
    echo "One or more package installations did not behave as expected!"
    exit $N_FAILURES
fi
