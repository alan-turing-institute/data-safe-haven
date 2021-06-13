#! /usr/bin/env bats
load "../../bats/bats-assert/load"
load "../../bats/bats-file/load"
load "../../bats/bats-support/load"


# Helper functions
# ----------------
setup_python () {
    eval "$(pyenv init - --no-rehash)"
    pyenv shell $(pyenv versions | grep "${1}." | sed -E 's|[^0-9\.]*([0-9\.]+).*|\1|')
    run python --version
    assert_output --partial "${1}."
}

test_python_packages() {
    setup_python "$1"
    run python tests/test_packages_installed_python.py 2> /dev/null
    assert_output --regexp 'All [0-9]+ packages are installed'
    pyenv shell --unset
}

test_python_functionality() {
    setup_python "$1"
    run python tests/test_functionality_python.py 2>&1
    assert_output --partial 'All functionality tests passed'
    pyenv shell --unset
}

test_python_package_mirrors() {
    setup_python "$1"
    run bash tests/test_mirrors_pypi.sh 2>&1
    assert_output --partial 'PyPI working OK'
    pyenv shell --unset
}

# Julia
# -----
# Test Julia packages
@test "Julia packages" {
    run julia tests/test_packages_installed_julia.jl 2>&1
    assert_output --regexp 'All [0-9]+ packages are installed'
}

# Test Julia functionality
@test "Julia functionality" {
    run julia tests/test_functionality_julia.jl 2>&1
    assert_output --partial 'All functionality tests passed'
}


# Python
# ------
# Test Python 3.6
@test "Python packages (3.6)" {
    test_python_packages '3.6'
}
# Test Python functionality
@test "Python functionality (3.6)" {
    test_python_functionality '3.6'
}
@test "Python package mirrors (3.6)" {
    test_python_package_mirrors '3.6'
}

# Test Python 3.7
@test "Python packages (3.7)" {
    test_python_packages '3.7'
}
@test "Python functionality (3.7)" {
    test_python_functionality '3.7'
}
@test "Python package mirrors (3.7)" {
    test_python_package_mirrors '3.7'
}

# Test Python 3.8
@test "Python packages (3.8)" {
    test_python_packages '3.8'
}
@test "Python functionality (3.8)" {
    test_python_functionality '3.8'
}
@test "Python package mirrors (3.8)" {
    test_python_package_mirrors '3.8'
}


# R
# -
# Test R packages
@test "R packages" {
    run Rscript tests/test_packages_installed_R.R 2>&1
    assert_output --regexp 'All [0-9]+ packages are installed'
}

# Test R functionality
@test "R functionality" {
    run Rscript tests/test_functionality_R.R
    assert_output --partial 'All functionality tests passed'
}

# Test R package mirrors
@test "R package mirrors" {
    run bash tests/test_mirrors_cran.sh
    assert_output --partial 'CRAN working OK'
}


# Databases
# ---------
# Test MS SQL database
@test "MS SQL database (Python)" {
    run bash tests/test_databases.sh -d mssql -l python
    assert_output --partial 'All database tests passed'
}
@test "MS SQL database (R)" {
    run bash tests/test_databases.sh -d mssql -l R
    assert_output --partial 'All database tests passed'
}

# Test Postgres database
@test "Postgres database (Python)" {
    run bash tests/test_databases.sh -d postgres -l python
    assert_output --partial 'All database tests passed'
}
@test "Postgres database (R)" {
    run bash tests/test_databases.sh -d postgres -l R
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
@test "Mounted drives (/scratch)" {
    run bash tests/test_mounted_drives.sh -d scratch
    assert_output --partial 'All tests passed'
}
