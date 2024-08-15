#! /usr/bin/env bats


# Helper functions
# ----------------
initialise_python_environment() {
    ENV_PATH="${HOME}/.local/bats-python-environment"
    rm -rf "$ENV_PATH"
    python -m venv "$ENV_PATH"
    source "${ENV_PATH}/bin/activate"
    pip install --upgrade pip --quiet
}

initialise_r_environment() {
    ENV_PATH="${HOME}/.local/bats-r-environment"
    rm -rf "$ENV_PATH"
    mkdir -p "$ENV_PATH"
}

install_r_package() {
    PACKAGE_NAME="$1"
    ENV_PATH="${HOME}/.local/bats-r-environment"
    Rscript -e "install.packages('$PACKAGE_NAME', lib='$ENV_PATH');"
}

install_r_package_version() {
    PACKAGE_NAME="$1"
    PACKAGE_VERSION="$2"
    ENV_PATH="${HOME}/.local/bats-r-environment"
    Rscript -e "install.packages('remotes', lib='$ENV_PATH');"
    Rscript -e "library('remotes', lib='$ENV_PATH'); remotes::install_version(package='$PACKAGE_NAME', version='$PACKAGE_VERSION', lib='$ENV_PATH');"
}

check_db_credentials() {
    db_password="$(cat /etc/database_credential 2> /dev/null)"
    if [ -z "$db_password" ]; then
        return 1
    fi
    return 0
}


# Mounted drives
# --------------
@test "Mounted drives (/data)" {
    run bash test_mounted_drives.sh -d data
    [ "$status" -eq 0 ]
}
@test "Mounted drives (/home)" {
    run bash test_mounted_drives.sh -d home
    [ "$status" -eq 0 ]
}
@test "Mounted drives (/output)" {
    run bash test_mounted_drives.sh -d output
    [ "$status" -eq 0 ]
}
@test "Mounted drives (/shared)" {
    run bash test_mounted_drives.sh -d shared
    [ "$status" -eq 0 ]
}


# Package repositories
# --------------------
@test "Python package repository" {
    initialise_python_environment
    run bash test_repository_python.sh 2>&1
    [ "$status" -eq 0 ]
}
@test "R package repository" {
    initialise_r_environment
    run bash test_repository_R.sh
    [ "$status" -eq 0 ]
}


# Language functionality
# ----------------------
@test "Python functionality" {
    initialise_python_environment
    pip install numpy pandas scikit-learn --quiet
    run python test_functionality_python.py 2>&1
    [ "$status" -eq 0 ]
}
@test "R functionality" {
    initialise_r_environment
    install_r_package_version "MASS" "7.3-52"
    run Rscript test_functionality_R.R
    [ "$status" -eq 0 ]
}


# Databases
# ---------
# Test MS SQL database
@test "MS SQL database (Python)" {
    check_db_credentials || skip "No database credentials available"
    initialise_python_environment
    pip install pandas psycopg pymssql --quiet
    run bash test_databases.sh -d mssql -l python
    [ "$status" -eq 0 ]
}
@test "MS SQL database (R)" {
    check_db_credentials || skip "No database credentials available"
    initialise_r_environment
    install_r_package "DBI"
    install_r_package "odbc"
    install_r_package "RPostgres"
    run bash test_databases.sh -d mssql -l R
    [ "$status" -eq 0 ]
}
# Test Postgres database
@test "Postgres database (Python)" {
    check_db_credentials || skip "No database credentials available"
    initialise_python_environment
    pip install pandas psycopg pymssql --quiet
    run bash test_databases.sh -d postgresql -l python
    [ "$status" -eq 0 ]
}
@test "Postgres database (R)" {
    check_db_credentials || skip "No database credentials available"
    initialise_r_environment
    install_r_package "DBI"
    install_r_package "odbc"
    install_r_package "RPostgres"
    run bash test_databases.sh -d postgresql -l R
    [ "$status" -eq 0 ]
}
