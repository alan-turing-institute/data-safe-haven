#!/usr/bin/env bash

OUTFILE="./cloud_init_conda_package_specs.txt"

# Insert block header
echo "  # ***** START DEFINING PACKAGES FOR ANACONDA ***" > $OUTFILE
echo "  # DO NOT EDIT BY HAND: Update the generate_cloud_init_conda_package_specs.sh script and run it to re-generate this section in could_init_conda_package_specs.txt" >> $OUTFILE
echo "" >> $OUTFILE

# Insert explicitly requested packages
echo "  # Explicitly requested packages" >> $OUTFILE
echo "  - export PYALLREQUESTEDPACKAGES=\"ipykernel jupyter_client jupyterlab keras notebook pandas pandas-datareader pandas-profiling pandasql plotly spacy pystan pytorch r-irkernel scikit-image scikit-learn tensorflow torchvision\"" >> $OUTFILE
echo "  - export PY27REQUESTEDPACKAGES=\"monocle\"" >> $OUTFILE
echo "  - export PY35REQUESTEDPACKAGES=\"jupyterhub jupyterhub-ldapauthenticator\"" >> $OUTFILE
echo "  - export PY36REQUESTEDPACKAGES=\"jupyterhub jupyterhub-ldapauthenticator\"" >> $OUTFILE
echo ""  >> $OUTFILE

# Insert packages marked as "In installer" on Anaconda website package lists
# Python 2.7: https://docs.anaconda.com/anaconda/packages/py2.7_linux-64/
# Python 3.5: https://docs.anaconda.com/anaconda/packages/py3.5_linux-64/
# Python 3.6: https://docs.anaconda.com/anaconda/packages/py3.6_linux-64/

# Generate list common to Python version 2.7, 3.5, 3.6 (comm -12 shows only entries that are in both files)
COMMON_27_35=$(mktemp)
comm -12 anaconda-in-installer-27.list anaconda-in-installer-35.list > $COMMON_27_35
COMMON_27_35_36=$(mktemp)
comm -12 $COMMON_27_35 anaconda-in-installer-36.list > $COMMON_27_35_36
CONDA_COMMON=$(tr '\n' ' ' < $COMMON_27_35_36)

# Generate list in Python 2.7 but not in common list (comm -13 shows only entries unique to file 2)
EXTRA_27=$(mktemp)
comm -13 $COMMON_27_35_36 anaconda-in-installer-27.list > $EXTRA_27
CONDA_27=$(tr '\n' ' ' < $EXTRA_27)
# Generate list in Python 3.5 but not in common list (comm -13 shows only entries unique to file 2)
EXTRA_35=$(mktemp)
comm -13 $COMMON_27_35_36 anaconda-in-installer-35.list > $EXTRA_35
CONDA_35=$(tr '\n' ' ' < $EXTRA_35)
# Generate list in Python 3.6 but not in common list (comm -13 shows only entries unique to file 2)
EXTRA_36=$(mktemp)
comm -13 $COMMON_27_35_36 anaconda-in-installer-36.list > $EXTRA_36
CONDA_36=$(tr '\n' ' ' < $EXTRA_36)

# Tidy up temp files
rm $COMMON_27_35
rm $COMMON_27_35_36
rm $EXTRA_27
rm $EXTRA_35
rm $EXTRA_36

# Insert Anaconda "In installer" packages"
echo "  # Anaconda \"In installer\" packages" >> $OUTFILE
echo "  - export PYALLANACONDA_PACKAGES=\"${CONDA_COMMON}\"" >> $OUTFILE
echo "  - export PY27ANACONDA_PACKAGES=\"${CONDA_27}\"" >> $OUTFILE
echo "  - export PY35ANACONDA_PACKAGES=\"${CONDA_35}\"" >> $OUTFILE
echo "  - export PY36ANACONDA_PACKAGES=\"${CONDA_36}\"" >> $OUTFILE
echo "" >> $OUTFILE

echo "  # Consolidate package lists for each Python version" >> $OUTFILE
echo "  - export PYTHON27PACKAGES=\"\$PYALLREQUESTEDPACKAGES \$PY27REQUESTEDPACKAGES \$PYALLANACONDAPACKAGES \$PY27ANACONDAPACKAGES\"" >> $OUTFILE
echo "  - export PYTHON35PACKAGES=\"\$PYALLREQUESTEDPACKAGES \$PY35REQUESTEDPACKAGES \$PYALLANACONDAPACKAGES \$PY35ANACONDAPACKAGES\"" >> $OUTFILE
echo "  - export PYTHON36PACKAGES=\"\$PYALLREQUESTEDPACKAGES \$PY36REQUESTEDPACKAGES \$PYALLANACONDAPACKAGES \$PY36ANACONDAPACKAGES\"" >> $OUTFILE

#Insert block footer
echo "  # ***** END DEFINING PACKAGES FOR ANACONDA ***" >> $OUTFILE
echo ""  >> $OUTFILE
