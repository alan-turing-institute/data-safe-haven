#! /bin/bash

# Require three arguments: environment name; (quoted) list of conda packages; (quoted) list of pip packages
if [ $# -ne 1 ]; then
    echo "FATAL: Incorrect number of arguments"
    exit 1
fi
PYTHON_ENV_NAME=$1
DEBUG=0

START_TIME=$(date +%s)
echo ">=== ${START_TIME} Installing Python ($PYTHON_ENV_NAME) and packages ===<"
echo "Starting at $(date -u --iso-8601=seconds)"

# Ensure that pyenv is active
PYENV_VERSION="system"
eval "$(pyenv init -)"

# Determine which version to use
PYTHON_BASE_VERSION=$(echo $PYTHON_ENV_NAME | sed -E "s|py([0-9])([0-9]*)|\1.\2|")  # TODO: revisit this logic if/when Python 10 is released!
PYTHON_VERSION=$(pyenv install --list | grep -e "^ *${PYTHON_BASE_VERSION}." | tail -n 1 | sed 's/ //g')


# Prepare the environment
# -----------------------
echo "Preparing $PYTHON_ENV_NAME (Python $PYTHON_VERSION)..."
SECTION_START_TIME=$(date +%s)
if [ "$(pyenv versions | grep $PYTHON_VERSION)" = "" ]; then
    PYTHON_CONFIGURE_OPTS="--enable-shared" pyenv install $PYTHON_VERSION
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
pip install poetry safety > /dev/null 2>&1
# Log time taken
SECTION_ELAPSED=$(date -u -d "0 $(date +%s) seconds - $SECTION_START_TIME seconds" +"%H:%M:%S")
echo "Preparing installation took $SECTION_ELAPSED"


# Extract maximum available version for each package using pip
# ------------------------------------------------------------
echo "Generating package requirements for Python $PYTHON_VERSION..."
SECTION_START_TIME=$(date +%s)
echo "" > requirements.poetry
while read LINE; do
    if [ ! "$LINE" ]; then continue; fi
    if [ "$(echo $LINE | egrep "[<>=]+")" ]; then
        # If the package has a version specifier then use it
        REQUIREMENT=$LINE
    else
        # Otherwise use the full available range
        # NB. the option to use the legacy solver will be removed in pip 21: https://github.com/pypa/pip/issues/9139
        VERSIONS=$(pip install --use-deprecated=legacy-resolver $LINE==any 2>&1 | grep "Could not find a version" | sed -E -e 's|.*: ([^)]*).*|\1|' -e 's/[[:space:]]*//g' | tr ',' '\n' | grep -v "macosx")
        MIN_VERSION=$(echo $VERSIONS | cut -d ' ' -f 1)
        MAX_VERSION=$(echo $VERSIONS | rev | cut -d ' ' -f 1 | rev)
        REQUIREMENT="$LINE>=$MIN_VERSION,<=$MAX_VERSION"
        if [ "$MAX_VERSION" == "none" ]; then REQUIREMENT="$LINE>0.0"; fi
    fi
    echo $REQUIREMENT >> requirements.poetry
done < /opt/build/python-requirements-${PYTHON_ENV_NAME}.txt
sed -i '/^$/d' requirements.poetry
if [ $DEBUG -eq 1 ]; then cat requirements.poetry | awk '{print "[DEBUG] "$1}'; fi
# Log time taken
SECTION_ELAPSED=$(date -u -d "0 $(date +%s) seconds - $SECTION_START_TIME seconds" +"%H:%M:%S")
echo "Generating requirements took $SECTION_ELAPSED"


# Solve dependencies and install using poetry
# -------------------------------------------
echo "Installing packages with poetry..."
SECTION_START_TIME=$(date +%s)
sed -e "s/<PYTHON_ENV_NAME>/$PYTHON_ENV_NAME/g" -e "s/<PYTHON_VERSION>/$PYTHON_VERSION/" /opt/build/python-pyproject-template.toml > /opt/build/python-pyproject-${PYTHON_ENV_NAME}.toml
poetry config virtualenvs.create false
poetry config virtualenvs.in-project true
rm poetry.lock pyproject.toml 2> /dev/null
ln -s /opt/build/python-pyproject-${PYTHON_ENV_NAME}.toml pyproject.toml
poetry add $(cat requirements.poetry | tr '\n' ' ')
if [ $DEBUG -eq 1 ]; then cat pyproject.toml | awk '{print "[DEBUG] "$1}'; fi
echo "Installed packages:"
poetry show
poetry show > /opt/verification/python-package-versions-${PYTHON_VERSION}.log
poetry show --tree >> /opt/verification/python-package-versions-${PYTHON_VERSION}.log
rm requirements.poetry poetry.lock pyproject.toml 2> /dev/null
# Log time taken
SECTION_ELAPSED=$(date -u -d "0 $(date +%s) seconds - $SECTION_START_TIME seconds" +"%H:%M:%S")
echo "Installation took $SECTION_ELAPSED"


# Install any post-install package requirements
# ---------------------------------------------
echo "Installing post-install package requirements"
if [ "$(grep ^spacy /opt/build/python-requirements-${PYTHON_ENV_NAME}.txt)" ]; then
    python -m spacy download en_core_web_sm
    python -m spacy download en_core_web_md
    python -m spacy download en_core_web_lg
fi
if [ "$(grep ^nltk /opt/build/python-requirements-${PYTHON_ENV_NAME}.txt)" ]; then
    python -m nltk.downloader all -d /usr/share/nltk_data
fi


# Check that all requested packages are installed
# -----------------------------------------------
MISSING_PACKAGES=""
INSTALLED_PACKAGES=$(pip freeze | cut -d '=' -f 1 | tr '[A-Z]' '[a-z]')
for REQUESTED_PACKAGE in $(cat /opt/build/python-requirements-${PYTHON_ENV_NAME}.txt | sed -E 's|([^<>=]*).*|\1|' | tr '[A-Z]' '[a-z]'); do
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
safety check --json --output /opt/verification/python-safety-check-${PYTHON_VERSION}.json
safety review --full-report -f /opt/verification/python-safety-check-${PYTHON_VERSION}.json


# Set the Jupyter kernel name to the full Python version name and store it as $PYTHON_ENV_NAME so that different python3 versions show up separately
# --------------------------------------------------------------------------------------------------------------------------------------------------
sed -i "s|\"display_name\": \"Python.*\"|\"display_name\": \"Python ${PYTHON_VERSION}\"|" /opt/pyenv/versions/${PYTHON_VERSION}/share/jupyter/kernels/python[2,3]/kernel.json
ln -s /opt/pyenv/versions/${PYTHON_VERSION}/share/jupyter/kernels/python[2,3] /opt/pyenv/versions/${PYTHON_VERSION}/share/jupyter/kernels/${PYTHON_ENV_NAME}


# Finish up
# ---------
rm -rf /root/* /root/.[a-zA-Z_]* /tmp/* /tmp/.[a-zA-Z_]*
ELAPSED=$(date -u -d "0 $(date +%s) seconds - $START_TIME seconds" +"%H:%M:%S")
echo "Finished at $(date -u --iso-8601=seconds) after $ELAPSED"
