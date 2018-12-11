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
cat requested-27.list anaconda-in-installer-27.list dsvm-conda-27.list | sort | uniq > $COMBINED_27
COMBINED_35=$(mktemp)
cat requested-35.list anaconda-in-installer-35.list dsvm-conda-35.list | sort | uniq  > $COMBINED_35
COMBINED_36=$(mktemp)
cat requested-36.list anaconda-in-installer-36.list dsvm-conda-36.list | sort | uniq  > $COMBINED_36
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







# COMMON_ANACONDA=$(mktemp)
# comm -12 anaconda-in-installer-27.list anaconda-in-installer-35.list | comm -12 - anaconda-in-installer-36.list > $COMMON_ANACONDA
# echo "  - export PYALL_ANACONDA=\"$(cat $COMMON_ANACONDA | tr '\n' ' ' | xargs)\""
# echo "  - export PY27_ANACONDA=\"$(comm -23 requested-27.list $COMMON_ANACONDA | tr '\n' ' ' | xargs)\""
# echo "  - export PY35_ANACONDA=\"$(comm -23 requested-35.list $COMMON_ANACONDA | tr '\n' ' ' | xargs)\""
# echo "  - export PY36_ANACONDA=\"$(comm -23 requested-36.list $COMMON_ANACONDA | tr '\n' ' ' | xargs)\""
# rm $COMMON_ANACONDA



# # Generate list common to Python version 2.7, 3.5, 3.6 (comm -12 shows only entries that are in both files)
# COMMON_27_35=$(mktemp)
# comm -12 anaconda-in-installer-27.list anaconda-in-installer-35.list > $COMMON_27_35
# COMMON_27_35_36=$(mktemp)
# comm -12 $COMMON_27_35 anaconda-in-installer-36.list > $COMMON_27_35_36
# CONDA_COMMON=$(tr '\n' ' ' < $COMMON_27_35_36)

# # Generate list in Python 2.7 but not in common list (comm -13 shows only entries unique to file 2)
# EXTRA_27=$(mktemp)
# comm -13 $COMMON_27_35_36 anaconda-in-installer-27.list > $EXTRA_27
# CONDA_27=$(tr '\n' ' ' < $EXTRA_27)
# # Generate list in Python 3.5 but not in common list (comm -13 shows only entries unique to file 2)
# EXTRA_35=$(mktemp)
# comm -13 $COMMON_27_35_36 anaconda-in-installer-35.list > $EXTRA_35
# CONDA_35=$(tr '\n' ' ' < $EXTRA_35)
# # Generate list in Python 3.6 but not in common list (comm -13 shows only entries unique to file 2)
# EXTRA_36=$(mktemp)
# comm -13 $COMMON_27_35_36 anaconda-in-installer-36.list > $EXTRA_36
# CONDA_36=$(tr '\n' ' ' < $EXTRA_36)

# # Tidy up temp files
# rm $COMMON_27_35
# rm $COMMON_27_35_36
# rm $EXTRA_27
# rm $EXTRA_35
# rm $EXTRA_36

# # Insert Anaconda "In installer" packages"
# echo "  # Anaconda \"In installer\" packages"
# echo "  - export PYALL_ANACONDA=\"${CONDA_COMMON}\""
# echo "  - export PY27_ANACONDA=\"${CONDA_27}\""
# echo "  - export PY35_ANACONDA=\"${CONDA_35}\""
# echo "  - export PY36_ANACONDA=\"${CONDA_36}\""

# echo "  # Consolidate package lists for each Python version"
# echo "  - export PYTHON27PACKAGES=\"\$PYALL_REQUESTED \$PY27_REQUESTED \$PYALL_ANACONDA \$PY27_ANACONDA\""
# echo "  - export PYTHON35PACKAGES=\"\$PYALL_REQUESTED \$PY35_REQUESTED \$PYALL_ANACONDA \$PY35_ANACONDA\""
# echo "  - export PYTHON36PACKAGES=\"\$PYALL_REQUESTED \$PY36_REQUESTED \$PYALL_ANACONDA \$PY36_ANACONDA\""

# #Insert block footer
# echo "  # ***** END DEFINING PACKAGES FOR ANACONDA ***"
