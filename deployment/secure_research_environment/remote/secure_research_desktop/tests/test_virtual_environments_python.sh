#! /bin/bash -i
# This script must run in interactive mode to ensure that pyenv setup commands are run

# Common variables
N_FAILED_TESTS=0
PYTHON_VERSION=$1
VENV_NAME="${PYTHON_VERSION}-test"

# Test pyenv
echo "Testing that pyenv exists"
which pyenv || N_FAILED_TESTS=$((N_FAILED_TESTS + 1))

# Test pyenv versions
echo "Testing pyenv versions"
pyenv versions || N_FAILED_TESTS=$((N_FAILED_TESTS + 1))

# Test pyenv virtualenvs
echo "Testing pyenv virtualenvs"
pyenv virtualenvs || N_FAILED_TESTS=$((N_FAILED_TESTS + 1))

# Test virtualenv creation
echo "Testing virtualenv creation"
pyenv virtualenv-delete -f "$VENV_NAME" 2> /dev/null
pyenv virtualenv "$PYTHON_VERSION" "$VENV_NAME" || N_FAILED_TESTS=$((N_FAILED_TESTS + 1))
pyenv virtualenvs

# Test virtualenv activation
echo "Testing virtualenv activation"
pyenv activate "$VENV_NAME" || N_FAILED_TESTS=$((N_FAILED_TESTS + 1))

# Test Python version
echo "Testing Python version"
test "$(python --version)" == "Python ${PYTHON_VERSION}" || N_FAILED_TESTS=$((N_FAILED_TESTS + 1))

# Test virtualenv packages
echo "Testing virtualenv packages"
INSTALLED_PACKAGES=$(pip list --format=freeze | cut -d'=' -f1)
test "$(echo "$INSTALLED_PACKAGES" | wc -w)" -eq 3 || N_FAILED_TESTS=$((N_FAILED_TESTS + 1))

# Test virtualenv package installation
echo "Testing virtualenv package installation"
pip install matplotlib
INSTALLED_PACKAGES=$(pip list --format=freeze | cut -d'=' -f1)
test "$(echo "$INSTALLED_PACKAGES" | tr ' ' '\n' | grep "matplotlib")" == "matplotlib" || N_FAILED_TESTS=$((N_FAILED_TESTS + 1))

# Tear down a new virtual environment
echo "Testing virtualenv deletion"
pyenv virtualenv-delete -f "$VENV_NAME" || N_FAILED_TESTS=$((N_FAILED_TESTS + 1))

# Cleanup and print output
if [ $N_FAILED_TESTS = 0 ]; then
    echo "All tests passed for Python ${PYTHON_VERSION}"
else
    echo "$N_FAILED_TESTS tests failed for Python ${PYTHON_VERSION}!"
fi
