#! /bin/bash
# shellcheck disable=SC2046,SC2086

# Ensure environment name is provided
# -----------------------------------
if [ $# -ne 1 ]; then
    echo "FATAL: Incorrect number of arguments"
    exit 1
fi
PYTHON_ENV_NAME=$1
DEBUG=0

# Ensure that pyenv is active and determine which Python version to use
# ---------------------------------------------------------------------
START_TIME=$(date +%s)
echo ">=== ${START_TIME} Installing Python ($PYTHON_ENV_NAME) and packages ===<"
echo "Starting at $(date -u --iso-8601=seconds)"
PYTHON_BASE_VERSION=$(echo "$PYTHON_ENV_NAME" | sed -E "s|py([0-9])([0-9]*)|\1.\2|")  # TODO: revisit this logic if/when Python 10 is released!
eval "$(pyenv init --path)"
eval "$(pyenv init -)"
PYTHON_VERSION=$(pyenv install --list | grep -e "^ *${PYTHON_BASE_VERSION}." | tail -n 1 | sed 's/ //g')

# Prepare the environment
# -----------------------
echo "Preparing $PYTHON_ENV_NAME (Python $PYTHON_VERSION)..."
SECTION_START_TIME=$(date +%s)
if ! (pyenv versions | grep -q "$PYTHON_VERSION"); then
    PYTHON_CONFIGURE_OPTS="--enable-shared" pyenv install "$PYTHON_VERSION"
fi
pyenv shell "$PYTHON_VERSION"
# Ensure that we're using the correct version
if ! (python --version 2>&1 | grep -q "$PYTHON_VERSION"); then
    echo "FATAL: Using $(python --version 2>&1) but expected version ${PYTHON_VERSION}"
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
while read -r LINE; do
    if [ ! "$LINE" ]; then continue; fi
    if (echo $LINE | grep -q -E "[<>=]+"); then
        # If the package has a version specifier then use it
        REQUIREMENT=$LINE
    else
        VERSIONS=$(pip install "$LINE==" 2>&1 | grep "Could not find a version" | sed -E -e 's|.*: ([^)]*).*|\1|' -e 's/[[:space:]]*//g' | tr ',' '\n' | grep -v "macosx")
        if [ "$VERSIONS" ]; then
            # Use the full available range if available
            MIN_VERSION=$(echo $VERSIONS | cut -d ' ' -f 1)
            MAX_VERSION=$(echo $VERSIONS | rev | cut -d ' ' -f 1 | rev)
            REQUIREMENT=$([ "$MAX_VERSION" == "none" ] && echo "$LINE>0.0" || echo "$LINE>=$MIN_VERSION,<=$MAX_VERSION")
        else
            # Otherwise use a default
            REQUIREMENT="$LINE>0.0"
        fi
    fi
    echo "$REQUIREMENT" >> requirements.poetry
done < "/opt/build/python-requirements-${PYTHON_ENV_NAME}.txt"
sed -i '/^$/d' requirements.poetry
if [ $DEBUG -eq 1 ]; then awk '{print "[DEBUG] "$1}' requirements.poetry; fi
# Log time taken
SECTION_ELAPSED=$(date -u -d "0 $(date +%s) seconds - $SECTION_START_TIME seconds" +"%H:%M:%S")
echo "Generating requirements took $SECTION_ELAPSED"

# Solve dependencies and install using poetry
# -------------------------------------------
echo "Installing packages with poetry..."
SECTION_START_TIME=$(date +%s)
sed -e "s/PYTHON_ENV_NAME/$PYTHON_ENV_NAME/g" -e "s/PYTHON_VERSION/$PYTHON_VERSION/" /opt/build/python-pyproject-template.toml > /opt/build/python-pyproject-${PYTHON_ENV_NAME}.toml
poetry config virtualenvs.create false
poetry config virtualenvs.in-project true
rm poetry.lock pyproject.toml 2> /dev/null
ln -s "/opt/build/python-pyproject-${PYTHON_ENV_NAME}.toml" pyproject.toml
poetry add $(tr '\n' ' ' < requirements.poetry) || exit 3
if [ $DEBUG -eq 1 ]; then awk '{print "[DEBUG] "$1}' pyproject.toml; fi
echo "Installed packages:"
poetry show
poetry show > "/opt/verification/python-package-versions-${PYTHON_VERSION}.log"
poetry show --tree >> "/opt/verification/python-package-versions-${PYTHON_VERSION}.log"
rm requirements.poetry poetry.lock pyproject.toml 2> /dev/null
# Log time taken
SECTION_ELAPSED=$(date -u -d "0 $(date +%s) seconds - $SECTION_START_TIME seconds" +"%H:%M:%S")
echo "Installation took $SECTION_ELAPSED"

# Install any post-install package requirements
# ---------------------------------------------
echo "Installing post-install package requirements"
if (grep -q ^spacy /opt/build/python-requirements-${PYTHON_ENV_NAME}.txt); then
    python -m spacy download en_core_web_sm
    python -m spacy download en_core_web_md
    python -m spacy download en_core_web_lg
fi
if (grep -q ^nltk /opt/build/python-requirements-${PYTHON_ENV_NAME}.txt); then
    python -m nltk.downloader all -d /usr/share/nltk_data
fi

# Check that all requested packages are installed
# -----------------------------------------------
MISSING_PACKAGES=""
INSTALLED_PACKAGES=$(pip freeze | cut -d '=' -f 1 | tr '[:upper:]' '[:lower:]')
for REQUESTED_PACKAGE in $(sed -E 's|([^<>=]*).*|\1|' "/opt/build/python-requirements-${PYTHON_ENV_NAME}.txt" | tr '[:upper:]' '[:lower:]'); do
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
    exit 4
else
    echo "All requested Python ${PYTHON_VERSION} packages are installed"
fi

# Run safety check and log any problems
# -------------------------------------
echo "Running safety check on Python ${PYTHON_VERSION} installation..."
safety check --json --output "/opt/verification/python-safety-check-${PYTHON_VERSION}.json"
safety review --full-report -f "/opt/verification/python-safety-check-${PYTHON_VERSION}.json"

# Set the Jupyter kernel name to the full Python version name
# This ensures that different python3 versions show up separately
# ---------------------------------------------------------------
sed -i "s|\"display_name\": \"Python.*\"|\"display_name\": \"Python ${PYTHON_VERSION}\"|" /opt/pyenv/versions/${PYTHON_VERSION}/share/jupyter/kernels/python[2,3]/kernel.json
ln -s /opt/pyenv/versions/${PYTHON_VERSION}/share/jupyter/kernels/python[2,3] /opt/pyenv/versions/${PYTHON_VERSION}/share/jupyter/kernels/${PYTHON_ENV_NAME}

# Finish up
# ---------
rm -rf /root/* /root/.[a-zA-Z_]* /tmp/* /tmp/.[a-zA-Z_]*
ELAPSED=$(date -u -d "0 $(date +%s) seconds - $START_TIME seconds" +"%H:%M:%S")
echo "Finished at $(date -u --iso-8601=seconds) after $ELAPSED"
