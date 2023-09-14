#! /usr/bin/env bats
load "../bats/bats-assert/load"
load "../bats/bats-file/load"
load "../bats/bats-support/load"


# Helper functions
# ----------------
install_requirements_python() {
    pip install pandas psycopg pymssql
}

install_requirements_R() {
    Rscript -e "install.packages(c('DBI', 'odbc', 'RPostgres'))"
}


# Python
# ------
# Test Python functionality
@test "Python functionality" {
    run python tests/test_functionality_python.py 2>&1
    assert_output --partial 'All functionality tests passed'
}
# Test Python package repository
@test "Python package repository" {
    run bash tests/test_repository_python.sh 2>&1
    assert_output --partial 'All package installations behaved as expected'
}


# R
# -
# Test R packages
# Test R functionality
@test "R functionality" {
    run Rscript tests/test_functionality_R.R
    assert_output --partial 'All functionality tests passed'
}

# Test R package repository
@test "R package repository" {
    run bash tests/test_repository_R.sh
    assert_output --partial 'All package installations behaved as expected'
}


# Databases
# ---------
# Test MS SQL database
@test "MS SQL database (Python)" {
    install_requirements_python
    run bash tests/test_databases.sh -d mssql -l python
    assert_output --partial 'All database tests passed'
}
@test "MS SQL database (R)" {
    install_requirements_R
    run bash tests/test_databases.sh -d mssql -l R
    assert_output --partial 'All database tests passed'
}

# Test Postgres database
@test "Postgres database (Python)" {
    install_requirements_python
    run bash tests/test_databases.sh -d postgresql -l python
    assert_output --partial 'All database tests passed'
}
@test "Postgres database (R)" {
    install_requirements_R
    run bash tests/test_databases.sh -d postgresql -l R
    assert_output --partial 'All database tests passed'
}


# Mounted drives
# --------------
@test "Mounted drives (/data)" {
    run bash tests/test_mounted_drives.sh -d data
    assert_output --partial 'All tests passed'
}
@test "Mounted drives (/home)" {
    run bash tests/test_mounted_drives.sh -d home
    assert_output --partial 'All tests passed'
}
@test "Mounted drives (/output)" {
    run bash tests/test_mounted_drives.sh -d output
    assert_output --partial 'All tests passed'
}
@test "Mounted drives (/shared)" {
    run bash tests/test_mounted_drives.sh -d shared
    assert_output --partial 'All tests passed'
}
