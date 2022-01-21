#! /bin/bash
# shellcheck disable=SC2046,SC2086

# Ensure environment name is provided
# -----------------------------------
if [ $# -ne 1 ]; then
    echo "FATAL: Incorrect number of arguments"
    exit 1
fi
PYTHON_VERSION=$1
PYENV_ROOT="$(pyenv root)"
PYPROJECT_TOML="/opt/build/python-${PYTHON_VERSION}-pyproject.toml"
MONITORING_LOG="/opt/monitoring/python-${PYTHON_VERSION}-package-versions.log"
REQUIREMENTS_TXT="/opt/build/python-${PYTHON_VERSION}-requirements.txt"
REQUESTED_PACKAGE_LIST="/opt/build/packages/packages-python-${PYTHON_VERSION}.list"
SAFETY_CHECK_JSON="/opt/monitoring/python-${PYTHON_VERSION}-safety-check.json"


# Ensure that pyenv is active and determine which Python version to use
# ---------------------------------------------------------------------
echo ">=== $(date +%s) Installing Python ($PYTHON_VERSION) and packages ===<"
PYTHON_CONFIGURE_OPTS="--enable-shared" pyenv install --skip-existing "$PYTHON_VERSION"
EXE_PATH="${PYENV_ROOT}/versions/${PYTHON_VERSION}/bin"
echo "Installed $(${EXE_PATH}/python --version)"


# Install and upgrade installation prerequisites
# ----------------------------------------------
echo "Installing and upgrading installation prerequisites for Python ${PYTHON_VERSION}..."
${EXE_PATH}/pip install --upgrade pip poetry


# Solve dependencies and install using poetry
# -------------------------------------------
echo "Installing packages with poetry..."
${EXE_PATH}/poetry config virtualenvs.create false
${EXE_PATH}/poetry config virtualenvs.in-project true
rm poetry.lock pyproject.toml 2> /dev/null
sed -e "s/PYTHON_VERSION/$PYTHON_VERSION/" /opt/build/pyenv/pyproject_template.toml > $PYPROJECT_TOML
ln -s $PYPROJECT_TOML pyproject.toml
${EXE_PATH}/poetry add $(tr '\n' ' ' < $REQUIREMENTS_TXT) || exit 3


# Write package versions to monitoring log
# ----------------------------------------
${EXE_PATH}/poetry show > $MONITORING_LOG
${EXE_PATH}/poetry show --tree >> $MONITORING_LOG


# Run any post-install commands
# -----------------------------
echo "Running post-install commands..."
INSTALLED_PACKAGES=$(${EXE_PATH}/pip list --format columns | tail -n+3 | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
for INSTALLED_PACKAGE in $INSTALLED_PACKAGES; do
    if [ "$INSTALLED_PACKAGE" == "gensim" ]; then
        export GENSIM_DATA_DIR=/usr/share/gensim_data
        for dataset in "text8" "fake-news"; do
            ${EXE_PATH}/python -m gensim.downloader --download $dataset
        done
        sleep 30
    fi
    if [ "$INSTALLED_PACKAGE" == "nltk" ]; then
        ${EXE_PATH}/python -m nltk.downloader all -d /usr/share/nltk_data
    fi
    if [ "$INSTALLED_PACKAGE" == "spacy" ]; then
        ${EXE_PATH}/python -m spacy download en_core_web_sm
        ${EXE_PATH}/python -m spacy download en_core_web_md
        ${EXE_PATH}/python -m spacy download en_core_web_lg
    fi
done


# Check that all requested packages are installed
# -----------------------------------------------
MISSING_PACKAGES=""
while read -r REQUESTED_PACKAGE; do
    REQUESTED_PACKAGE_LOWER=$(echo $REQUESTED_PACKAGE | tr '[:upper:]' '[:lower:]')
    for INSTALLED_PACKAGE in $INSTALLED_PACKAGES; do
        if [ "$REQUESTED_PACKAGE_LOWER" == "$INSTALLED_PACKAGE" ]; then break; fi
    done
    if [ "$REQUESTED_PACKAGE_LOWER" != "$INSTALLED_PACKAGE" ]; then
        MISSING_PACKAGES="$MISSING_PACKAGES $REQUESTED_PACKAGE"
    fi
done < "$REQUESTED_PACKAGE_LIST"
if [ "$MISSING_PACKAGES" ]; then
    echo "FATAL: The following requested packages are missing:"
    echo "$MISSING_PACKAGES"
    exit 1
else
    echo "All requested Python ${PYTHON_VERSION} packages are installed"
fi


# Run safety check and log any problems
# -------------------------------------
echo "Running safety check on Python ${PYTHON_VERSION} installation..."
${EXE_PATH}/safety check --json --output $SAFETY_CHECK_JSON
${EXE_PATH}/safety review --full-report -f $SAFETY_CHECK_JSON


# Clean up
# --------
rm -rf "/root/.pyenv"
