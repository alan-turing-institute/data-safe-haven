#! /usr/bin/env bats
load "../../../bats/bats-assert/load"
load "../../../bats/bats-file/load"
load "../../../bats/bats-support/load"


# Helper functions
# ----------------
setup_python () {
    eval "$(pyenv init -)"
    pyenv shell $(pyenv versions | grep "${1}." | sed -E 's|[^0-9\.]*([0-9\.]+).*|\1|')
    run python --version
    assert_output --partial "${1}."
}


# Julia
# -----
# Test Julia packages
@test "Julia packages" {
    run julia test_packages_installed_julia.jl 2>&1
    assert_output --regexp 'All [0-9]+ packages are installed'
}

# Test Julia functionality
@test "Julia functionality" {
    run julia test_functionality_julia.jl 2>&1
    assert_output --partial 'All functionality tests passed'
}


# Python
# ------
# Test Python packages
@test "Python 2.7 packages" {
    setup_python '2.7'
    run python test_packages_installed_python.py 2> /dev/null
    assert_output --regexp 'All [0-9]+ packages are installed'
    # refute_output --partial 'packages are missing'
    pyenv shell system
}
@test "Python 3.6 packages" {
    setup_python '3.6'
    run python test_packages_installed_python.py 2> /dev/null
    assert_output --regexp 'All [0-9]+ packages are installed'
    # refute_output --partial 'packages are missing'
    pyenv shell system
}
@test "Python 3.7 packages" {
    setup_python '3.7'
    run python test_packages_installed_python.py 2> /dev/null
    assert_output --regexp 'All [0-9]+ packages are installed'
    # refute_output --partial 'packages are missing'
    pyenv shell system
}

# Test Python functionality
@test "Python 2.7 functionality" {
    setup_python '2.7'
    run python test_functionality_python.py 2>&1
    assert_output --partial 'All functionality tests passed'
    pyenv shell system
}
@test "Python 3.6 functionality" {
    setup_python '3.6'
    run python test_functionality_python.py 2>&1
    assert_output --partial 'All functionality tests passed'
    pyenv shell system
}
@test "Python 3.7 functionality" {
    setup_python '3.7'
    run python test_functionality_python.py 2>&1
    assert_output --partial 'All functionality tests passed'
    pyenv shell system
}

# Test Python package mirrors
@test "Python 2.7 package mirrors" {
    setup_python '2.7'
    run bash test_mirrors_pypi.sh 2>&1
    assert_output --partial 'PyPI working OK'
    pyenv shell system
}
@test "Python 3.6 package mirrors" {
    setup_python '3.6'
    run bash test_mirrors_pypi.sh 2>&1
    assert_output --partial 'PyPI working OK'
    pyenv shell system
}
@test "Python 3.7 package mirrors" {
    setup_python '3.7'
    run bash test_mirrors_pypi.sh 2>&1
    assert_output --partial 'PyPI working OK'
    pyenv shell system
}


# R
# -
# Test R packages
@test "R packages" {
    run Rscript test_packages_installed_R.R 2>&1 | grep -v "Warning message:" | grep -v "call dbDisconnect()"
    assert_output --regexp 'All [0-9]+ packages are installed'
}

# Test R functionality
@test "R functionality" {
    run Rscript test_functionality_R.R
    assert_output --partial 'All functionality tests passed'
}

# Test R package mirrors
@test "R package mirrors" {
    run bash test_mirrors_cran.sh
    assert_output --partial 'CRAN working OK'
}
