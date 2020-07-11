#! /bin/bash

# Require three arguments: environment name; (quoted) list of conda packages; (quoted) list of pip packages
if [ $# -ne 1 ]; then
    echo "FATAL: Incorrect number of arguments"
    exit 1
fi
PYTHON_ENV_NAME=$1

START_TIME=$(date +%s)
echo ">=== ${START_TIME} Creating $PYTHON_ENV_NAME python installation ===<"
echo "Starting at $(date +'%Y-%m-%d %H:%M:%S')"

# Ensure that pyenv is active
PYENV_VERSION="system"
eval "$(pyenv init -)"

# Determine which version to use
# TODO: revisit this logic if/when Python 10 is released!
PYTHON_BASE_VERSION=$(echo $PYTHON_ENV_NAME | sed "s/py\([0-9]\)\([0-9]*\)/\1.\2/")
PYTHON_VERSION=$(pyenv install --list | grep -e "^ *${PYTHON_BASE_VERSION}." | tail -n 1 | sed 's/ //g')


# Prepare the environment
# -----------------------
echo "Preparing $PYTHON_ENV_NAME (Python $PYTHON_VERSION)..."
PREPARATION_START_TIME=$(date +%s)
if [ "$(pyenv versions | grep $PYTHON_VERSION)" = "" ]; then
    pyenv install $PYTHON_VERSION
fi
pyenv shell $PYTHON_VERSION

# Ensure that we're using the correct version
if [ ! "$(echo "$(python --version 2>&1)" | grep $PYTHON_VERSION)" ]; then
    echo "FATAL: Using $(python --version 2>&1) but expected version $PYTHON_VERSION!"
    exit 2
fi

# Install and upgrade installation prerequisites
echo "Installing and upgrading installation prerequisites for Python $PYTHON_VERSION..."
pip install --upgrade pip setuptools > /dev/null 2>&1
pip install pip-tools poetry safety > /dev/null 2>&1

# Log time taken
PREPARATION_ELAPSED=$(date -u -d "0 $(date +%s) seconds - $PREPARATION_START_TIME seconds" +"%H:%M:%S")
echo "Preparing installation took $PREPARATION_ELAPSED"


# Initial solve using pip-compile
# -------------------------------
echo "Performing initial solve using pip-compile..."
SOLVE_START_TIME=$(date +%s)
sort /installation/python-requirements-${PYTHON_ENV_NAME}.txt | sed '/^$/d' > python-requirements-${PYTHON_ENV_NAME}.in

# Remove any packages that cannot be solved with pip-compile
egrep "^(pygrib)$" python-requirements-${PYTHON_ENV_NAME}.in | sort > python-requirements-${PYTHON_ENV_NAME}.unsolvable

# Pre-solve on the reduced input file
comm -23 python-requirements-${PYTHON_ENV_NAME}.in python-requirements-${PYTHON_ENV_NAME}.unsolvable > python-requirements-${PYTHON_ENV_NAME}.solvable
cat python-requirements-${PYTHON_ENV_NAME}.solvable
echo "Attempting to find compatible versions for $(wc -l < python-requirements-${PYTHON_ENV_NAME}.solvable) packages "
pip-compile -r python-requirements-${PYTHON_ENV_NAME}.solvable #2> /dev/null
cat python-requirements-${PYTHON_ENV_NAME}.txt
echo "Solved $(wc -l < python-requirements-${PYTHON_ENV_NAME}.txt) packages "

# Only include packages which were explicitly requested then strip out comments
# Require version to be greater-than-or-equal to this solve so that the poetry solver has some leeway
grep "python-requirements-${PYTHON_ENV_NAME}" python-requirements-${PYTHON_ENV_NAME}.txt | sed -e "s|\(.*\)#.*|\1|" -e "s|==|>=|" > poetry-specification-${PYTHON_ENV_NAME}.txt
# Add unsolvable packages
cat python-requirements-${PYTHON_ENV_NAME}.unsolvable | awk '{print $1">=0.0"}' >> poetry-specification-${PYTHON_ENV_NAME}.txt
# Add constrained packages
egrep "[<>=]+" python-requirements-${PYTHON_ENV_NAME}.in | while read LINE; do
    PACKAGE=$(echo $LINE | sed -E 's|([^<>=]*)[<>=]*.*|\1|')
    sed -i "/^$PACKAGE[<>=].*/d" poetry-specification-${PYTHON_ENV_NAME}.txt
    echo $LINE >> poetry-specification-${PYTHON_ENV_NAME}.txt
done

# Sort package specifications file and remove empty lines
sort -o poetry-specification-${PYTHON_ENV_NAME}.txt poetry-specification-${PYTHON_ENV_NAME}.txt
sed -i '/^$/d' poetry-specification-${PYTHON_ENV_NAME}.txt
cat poetry-specification-${PYTHON_ENV_NAME}.txt
echo "Determined compatible version specifications for $(wc -l < poetry-specification-${PYTHON_ENV_NAME}.txt) packages "

# Log time taken
SOLVE_ELAPSED=$(date -u -d "0 $(date +%s) seconds - $SOLVE_START_TIME seconds" +"%H:%M:%S")
echo "Initial solve took $SOLVE_ELAPSED"


# Generate pyproject.toml
# -----------------------
echo "Generating pyproject.toml for Python $PYTHON_VERSION..."
sed -e "s/<PYTHON_ENV_NAME>/$PYTHON_ENV_NAME/g" -e "s/<PYTHON_VERSION>/$PYTHON_VERSION/" /installation/python-pyproject-template.toml > /installation/python-pyproject-${PYTHON_ENV_NAME}.toml
grep -v '^#' poetry-specification-${PYTHON_ENV_NAME}.txt | while read LINE; do
    PACKAGE_NAME=$(echo $LINE | egrep "[^<>=]+" | cut -d '=' -f1 | cut -d '<' -f1 | cut -d '>' -f1)
    VERSION=$(echo $LINE | sed -E 's|([^<>=]*)([^<>=]*)(.?)|\2\3|')
    # Packages of the form 'name[details]' need to be formatted as 'name = {extras = ["details"], version = "<version-details>"}'
    if [ "$(echo $PACKAGE_NAME | grep '\[')" ]; then
        echo $PACKAGE_NAME | sed -E "s|(.*)\[(.*)\]|\1 = {extras = \[\"\2\"\], version = \"$VERSION\"}|" >> /installation/python-pyproject-${PYTHON_ENV_NAME}.toml
    # Normal packages need to be formatted as 'name = "<version-details>"'
    else
        echo "$PACKAGE_NAME = \"$VERSION\"" >> /installation/python-pyproject-${PYTHON_ENV_NAME}.toml
    fi
    # fi
done
# 'black' is a special case as it only has prereleases
sed -i 's|^black = .*|black = { version = ">0.0.0", allow-prereleases = true }|' /installation/python-pyproject-${PYTHON_ENV_NAME}.toml
rm poetry-specification-${PYTHON_ENV_NAME}.txt


# Solve dependencies and install using poetry
# -------------------------------------------
echo "Installing packages with poetry..."
INSTALLATION_START_TIME=$(date +%s)
poetry config virtualenvs.create false
rm poetry.lock pyproject.toml 2> /dev/null
ln -s  /installation/python-pyproject-${PYTHON_ENV_NAME}.toml pyproject.toml
poetry install
echo "Installed packages:"
poetry show
rm poetry.lock pyproject.toml 2> /dev/null

# Log time taken
INSTALLATION_ELAPSED=$(date -u -d "0 $(date +%s) seconds - $INSTALLATION_START_TIME seconds" +"%H:%M:%S")
echo "Installation took $INSTALLATION_ELAPSED"


# Install any post-install package requirements
# ---------------------------------------------
echo "Installing post-install package requirements"
if [ "$(grep ^spacy /installation/python-requirements-${PYTHON_ENV_NAME}.txt)" ]; then
    python -m spacy download en_core_web_sm
    python -m spacy download en_core_web_md
    python -m spacy download en_core_web_lg
fi
if [ "$(grep ^nltk /installation/python-requirements-${PYTHON_ENV_NAME}.txt)" ]; then
    python -m nltk.downloader all
fi


# Check that all requested packages are installed
# -----------------------------------------------
MISSING_PACKAGES=""
INSTALLED_PACKAGES=$(pip freeze | cut -d '=' -f1 | tr '[A-Z]' '[a-z]')
for REQUESTED_PACKAGE in $(cat /installation/python-requirements-${PYTHON_ENV_NAME}.txt | cut -d '=' -f 1 | cut -d'>' -f 1 | cut -d'<' -f 1 | tr '[A-Z]' '[a-z]'); do
    is_installed=0
    for INSTALLED_PACKAGE in $INSTALLED_PACKAGES; do
        if [ "$REQUESTED_PACKAGE" == "$INSTALLED_PACKAGE" ]; then
            is_installed=1
            break
        fi
    done
    if [ $is_installed -eq 0 ]; then
        MISSING_PACKAGES="$MISSING_PACKAGES $REQUESTED_PACKAGE"
    fi
done
if [ "$MISSING_PACKAGES" ]; then
    echo "FATAL: The following requested packages are missing:"
    echo "$MISSING_PACKAGES"
    exit 3
else
    echo "All requested Python ${PYTHON_VERSION} packages are installed"
fi


# Run safety check and log any problems
# -------------------------------------
echo "Running safety check on Python ${PYTHON_VERSION} installation..."
safety check --json --output /installation/python-safety-check-${PYTHON_VERSION}.json
safety review --full-report -f /installation/python-safety-check-${PYTHON_VERSION}.json


# Set the Jupyter kernel name to the full Python version name and store it as $PYTHON_ENV_NAME so that different python3 versions show up separately
# --------------------------------------------------------------------------------------------------------------------------------------------------
sed -i "s|\"display_name\": \"Python.*\"|\"display_name\": \"Python ${PYTHON_VERSION}\"|" /opt/pyenv/versions/${PYTHON_VERSION}/share/jupyter/kernels/python[2,3]/kernel.json
ln -s /opt/pyenv/versions/${PYTHON_VERSION}/share/jupyter/kernels/python[2,3] /opt/pyenv/versions/${PYTHON_VERSION}/share/jupyter/kernels/${PYTHON_ENV_NAME}


# Finish up
# ---------
ELAPSED=$(date -u -d "0 $(date +%s) seconds - $START_TIME seconds" +"%H:%M:%S")
echo "Finished at $(date +'%Y-%m-%d %H:%M:%S') after $ELAPSED"
