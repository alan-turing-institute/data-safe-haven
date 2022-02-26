#! /bin/bash

# Common variables
N_FAILED_TESTS=0
PYTHON_VERSION=$1
VENV_NAME="${PYTHON_VERSION}-test"
echo "Preparing to test Python $PYTHON_VERSION with virtual environment $VENV_NAME"

# Test pyenv
body="Testing that pyenv exists"
echo -ne "[ ] ${body}\r"
which pyenv > /dev/null 2>&1
# if test $?; then echo -e "[\xE2\x9C\x94] ${body}"; else echo -e "[x] ${body}"; N_FAILED_TESTS=$((N_FAILED_TESTS + 1)); fi
if test $?; then echo -e "[x] ${body}"; else echo -e "[\xE2\x9C\x94] ${body}"; N_FAILED_TESTS=$((N_FAILED_TESTS + 1)); fi

# Test pyenv versions
body="Testing pyenv versions"
echo -ne "[ ] ${body}\r"
pyenv versions > /dev/null 2>&1
if test $?; then echo -e "[\xE2\x9C\x94] ${body}"; else echo -e "[x] ${body}"; N_FAILED_TESTS=$((N_FAILED_TESTS + 1)); fi

# Test pyenv virtualenvs
body="Testing pyenv virtualenvs"
echo -ne "[ ] ${body}\r"
pyenv virtualenvs > /dev/null 2>&1
if test $?; then echo -e "[\xE2\x9C\x94] ${body}"; else echo -e "[x] ${body}"; N_FAILED_TESTS=$((N_FAILED_TESTS + 1)); fi

# Test virtualenv creation
body="Testing virtualenv creation"
echo -ne "[ ] ${body}\r"
pyenv virtualenv-delete -f "$VENV_NAME" 2> /dev/null
pyenv virtualenv -f "$PYTHON_VERSION" "$VENV_NAME" > /dev/null 2>&1
if test $?; then echo -e "[\xE2\x9C\x94] ${body}"; else echo -e "[x] ${body}"; N_FAILED_TESTS=$((N_FAILED_TESTS + 1)); fi

# Test virtualenv activation
body="Testing virtualenv activation"
echo -ne "[ ] ${body}\r"
pyenv activate "$VENV_NAME" > /dev/null 2>&1
if test $?; then echo -e "[\xE2\x9C\x94] ${body}"; else echo -e "[x] ${body}"; N_FAILED_TESTS=$((N_FAILED_TESTS + 1)); fi

# Test Python version
body="Testing Python version"
echo -ne "[ ] ${body}\r"
test "$(python --version)" == "Python ${PYTHON_VERSION}" > /dev/null 2>&1
if test $?; then echo -e "[\xE2\x9C\x94] ${body}"; else echo -e "[x] ${body}"; N_FAILED_TESTS=$((N_FAILED_TESTS + 1)); fi

# Test virtualenv packages
body="Testing virtualenv packages"
echo -ne "[ ] ${body}\r"
INSTALLED_PACKAGES=$(pip list --format=freeze | cut -d'=' -f1)
test "$(echo "$INSTALLED_PACKAGES" | wc -w)" -eq 3 > /dev/null 2>&1
if test $?; then echo -e "[\xE2\x9C\x94] ${body}"; else echo -e "[x] ${body}"; N_FAILED_TESTS=$((N_FAILED_TESTS + 1)); fi

# Test virtualenv package installation
body="Testing virtualenv package installation"
echo -ne "[ ] ${body}\r"
pip install matplotlib --quiet
INSTALLED_PACKAGES=$(pip list --format=freeze | cut -d'=' -f1)
test "$(echo "$INSTALLED_PACKAGES" | tr ' ' '\n' | grep "matplotlib")" == "matplotlib" > /dev/null 2>&1
if test $?; then echo -e "[\xE2\x9C\x94] ${body}"; else echo -e "[x] ${body}"; N_FAILED_TESTS=$((N_FAILED_TESTS + 1)); fi

# Tear down a new virtual environment
body="Testing virtualenv deletion"
echo -ne "[ ] ${body}\r"
pyenv virtualenv-delete -f "$VENV_NAME" > /dev/null 2>&1
if test $?; then echo -e "[\xE2\x9C\x94] ${body}"; else echo -e "[x] ${body}"; N_FAILED_TESTS=$((N_FAILED_TESTS + 1)); fi

# Cleanup and print output
if [ $N_FAILED_TESTS = 0 ]; then
    echo "All tests passed for Python ${PYTHON_VERSION}"
else
    echo "$N_FAILED_TESTS tests failed for Python ${PYTHON_VERSION}!"
fi
