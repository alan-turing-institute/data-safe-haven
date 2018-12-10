#!/usr/bin/env bash

OUTFILE="./cloud_init_pip_package_specs.txt"

# Insert block header
echo "  # ***** START DEFINING PACKAGES FOR PIP ***" > $OUTFILE

# Insert explicitly requested packages
echo "  # Explicitly requested packages" >> $OUTFILE
echo "  - export PYALLREQUESTEDPACKAGES=\"\"" >> $OUTFILE
echo "  - export PY27REQUESTEDPACKAGES=\"\"" >> $OUTFILE
echo "  - export PY35REQUESTEDPACKAGES=\"\"" >> $OUTFILE
echo "  - export PY36REQUESTEDPACKAGES=\"\"" >> $OUTFILE
echo ""  >> $OUTFILE

# Insert packages installed in the Microsoft Azure Data Science VM
# Python 3.5 (pip): Package name only from output of "pip feeeze" in "py35" conda environment in DSVM
# Python 3.6 (pip): Package name only from output of "pip feeeze" in "py36" conda environment in DSVM

# Consolidate packages common to all environments
COMMON_35_36=$(mktemp)
comm -12 dsvm-pip-35.list dsvm-pip-36.list > $COMMON_35_36
DSVM_COMMON=$(tr '\n' ' ' < $COMMON_35_36)

# Generate list in Python 3.5 but not in common list (comm -13 shows only entries unique to file 2)
EXTRA_35=$(mktemp)
comm -13 $COMMON_35_36 dsvm-pip-35.list > $EXTRA_35
DSVM_35=$(tr '\n' ' ' < $EXTRA_35)
# Generate list in Python 3.6 but not in common list (comm -13 shows only entries unique to file 2)
EXTRA_36=$(mktemp)
comm -13 $COMMON_35_36 dsvm-pip-36.list > $EXTRA_36
DSVM_36=$(tr '\n' ' ' < $EXTRA_36)

# Tidy up temp files
rm $COMMON_35_36
rm $EXTRA_35
rm $EXTRA_36

# Insert Azure DSVM pip packages
echo "  # Azure DSVM pip packages" >> $OUTFILE
echo "  - export PYALLDSVM_PACKAGES=\"${DSVM_COMMON}\"" >> $OUTFILE
echo "  - export PY35DSVM_PACKAGES=\"${DSVM_35}\"" >> $OUTFILE
echo "  - export PY36DSVM_PACKAGES=\"${DSVM_36}\"" >> $OUTFILE
echo "" >> $OUTFILE

echo "  # Consolidate package lists for each Python version" >> $OUTFILE
echo "  - export PYTHON27PACKAGES=\"\$PYALLREQUESTEDPACKAGES \$PY27REQUESTEDPACKAGES \$PYALLANACONDAPACKAGES \$PY27ANACONDAPACKAGES \$PYALLDSVM_PACKAGES \$PY27DSVM_PACKAGES\"" >> $OUTFILE
echo "  - export PYTHON35PACKAGES=\"\$PYALLREQUESTEDPACKAGES \$PY35REQUESTEDPACKAGES \$PYALLANACONDAPACKAGES \$PY35ANACONDAPACKAGES \$PYALLDSVM_PACKAGES \$PY35DSVM_PACKAGES\"" >> $OUTFILE
echo "  - export PYTHON36PACKAGES=\"\$PYALLREQUESTEDPACKAGES \$PY36REQUESTEDPACKAGES \$PYALLANACONDAPACKAGES \$PY36ANACONDAPACKAGES \$PYALLDSVM_PACKAGES \$PY36DSVM_PACKAGES\"" >> $OUTFILE


#Insert block footer
echo "  # ***** END DEFINING PACKAGES FOR PIP ***" >> $OUTFILE
echo ""  >> $OUTFILE
