#!/usr/bin/env bash

# Insert block header
echo "  # ***** START DEFINING PACKAGES FOR ANACONDA ***"
echo "  # DO NOT EDIT BY HAND: Update the generate_cloud_init_conda_package_specs.sh script and run it to re-generate this section"

# Construct combined lists
# These consist of
#  1. requested packages
#  2. packages marked as "In installer" on Anaconda website package lists
#     Python 2.7: https://docs.anaconda.com/anaconda/packages/py2.7_linux-64/
#     Python 3.5: https://docs.anaconda.com/anaconda/packages/py3.5_linux-64/
#     Python 3.6: https://docs.anaconda.com/anaconda/packages/py3.6_linux-64/
#  3. packages present in the Microsoft DataScience VM
COMBINED_27=$(mktemp)
cat requested-27.list anaconda-in-installer-27.list dsvm-installed-27.list | sort | uniq > $COMBINED_27
COMBINED_35=$(mktemp)
cat requested-35.list anaconda-in-installer-35.list dsvm-installed-35.list | sort | uniq  > $COMBINED_35
COMBINED_36=$(mktemp)
cat requested-36.list anaconda-in-installer-36.list dsvm-installed-36.list | sort | uniq  > $COMBINED_36
COMMON_REQUESTED=$(mktemp)
comm -12 $COMBINED_27 $COMBINED_35 | comm -12 - $COMBINED_36 > $COMMON_REQUESTED

# Construct minimal common and environment specific lists
echo "  - export PY_COMMON_PACKAGES=\"$(cat $COMMON_REQUESTED | tr '\n' ' ' | xargs)\""
echo "  - export PY_27_PACKAGES=\"$(comm -23 $COMBINED_27 $COMMON_REQUESTED | tr '\n' ' ' | xargs)\""
echo "  - export PY_35_PACKAGES=\"$(comm -23 $COMBINED_35 $COMMON_REQUESTED | tr '\n' ' ' | xargs)\""
echo "  - export PY_36_PACKAGES=\"$(comm -23 $COMBINED_36 $COMMON_REQUESTED | tr '\n' ' ' | xargs)\""
rm $COMBINED_27 $COMBINED_35 $COMBINED_36 $COMMON_REQUESTED

# Use lists to construct appropriate environment variables
echo "  # Consolidate package lists for each Python version"
echo "  - export PYTHON27PACKAGES=\"\$PY_COMMON_PACKAGES \$PY_27_PACKAGES\""
echo "  - export PYTHON35PACKAGES=\"\$PY_COMMON_PACKAGES \$PY_35_PACKAGES\""
echo "  - export PYTHON36PACKAGES=\"\$PY_COMMON_PACKAGES \$PY_36_PACKAGES\""

# Insert block footer
echo "  # ***** END DEFINING PACKAGES FOR ANACONDA ***"
