#! /bin/bash

# Test Julia packages
julia_packages () {
    if [ "$(conda info | grep 'active environment' | cut -d':' -f2)" != " None" ]; then
        conda deactivate
    fi
    OUTPUT=$(julia test_packages_installed_julia.jl 2>&1)
    echo "$OUTPUT" | sed "s/^/[ DEBUG    ] /g"
    TEST_RESULT=$(echo $OUTPUT | grep "Packages not installed")
    if [ "$TEST_RESULT" != "" ]; then
        return 1
    fi
    return 0
}


# Test Julia functionality
julia_functionality () {
    if [ "$(conda info | grep 'active environment' | cut -d':' -f2)" != " None" ]; then
        conda deactivate
    fi
    OUTPUT=$(julia test_functionality_julia.jl 2>&1)
    echo "$OUTPUT" | sed "s/^/[ DEBUG    ] /g"
    TEST_RESULT=$(echo $OUTPUT | grep "All functionality tests passed")
    if [ "$TEST_RESULT" == "" ]; then
        return 1
    fi
    return 0
}


# Test python packages
_python_packages () {
    conda activate $1
    OUTPUT=$(python test_packages_installed_python.py 2> /dev/null)
    echo "$OUTPUT" | sed "s/^/[ DEBUG    ] /g"
    TEST_RESULT=$(echo $OUTPUT | grep "packages are missing")
    conda deactivate
    if [ "$TEST_RESULT" != "" ]; then
        return 1
    fi
    return 0
}
python_27_packages() { _python_packages py27; }
python_36_packages() { _python_packages py36; }
python_37_packages() { _python_packages py37; }


# Test python logistic regression
_python_functionality () {
    conda activate $1
    OUTPUT=$(python test_functionality_python.py 2>&1)
    echo "$OUTPUT" | sed "s/^/[ DEBUG    ] /g"
    TEST_RESULT=$(echo $OUTPUT | grep "All functionality tests passed")
        conda deactivate
    if [ "$TEST_RESULT" == "" ]; then
        return 1
    fi
    return 0
}
python_27_functionality() { _python_functionality py27; }
python_36_functionality() { _python_functionality py36; }
python_37_functionality() { _python_functionality py37; }


# Test PyPI
_python_mirrors_pypi () {
    conda activate $1
    OUTPUT=$(bash test_mirrors_pypi.sh 2>&1)
    echo "$OUTPUT" | sed "s/^/[ DEBUG    ] /g"
    TEST_RESULT=$(echo $OUTPUT | grep "PyPI working OK")
    conda deactivate
    if [ "$TEST_RESULT" == "" ]; then
        return 1
    fi
    return 0
}
python_27_mirrors_pypi() { _python_mirrors_pypi py27; }
python_36_mirrors_pypi() { _python_mirrors_pypi py36; }
python_37_mirrors_pypi() { _python_mirrors_pypi py37; }


# Test R packages
R_packages () {
    if [ "$(conda info | grep 'active environment' | cut -d':' -f2)" != " None" ]; then
        conda deactivate
    fi
    # Suppress a known spurious warning about database connections from BiocManager
    OUTPUT=$(Rscript test_packages_installed_R.R 2>&1 | grep -v "Warning message:" | grep -v "call dbDisconnect()")
    echo "$OUTPUT" | sed "s/\(^[^\[]\)/[1]   \1/g" | sed "s/\[1\]/[ DEBUG    ]/g" | sed 's/"//g'
    PROBLEMATIC_PACKAGES=$(echo "$OUTPUT" | grep -v "^\[")
    OUTCOME=0
    for PROBLEMATIC_PACKAGE in $PROBLEMATIC_PACKAGES; do
        if [ "$PROBLEMATIC_PACKAGE" != "" ]; then
            echo "Unexpected problem found with: $PROBLEMATIC_PACKAGE"
            OUTCOME=1
        fi
    done
    return $OUTCOME
}


# Test R functionality
R_functionality () {
    if [ "$(conda info | grep 'active environment' | cut -d':' -f2)" != " None" ]; then
        conda deactivate
    fi
    OUTPUT=$(Rscript test_functionality_R.R)
    echo "$OUTPUT" | sed "s/\[1\]/[ DEBUG    ]/g" | sed 's/"//g'
    TEST_RESULT=$(echo $OUTPUT | grep "All functionality tests passed")
    if [ "$TEST_RESULT" == "" ]; then
        return 1
    fi
    return 0
}


# Test CRAN access
R_mirrors_cran () {
    if [ "$(conda info | grep 'active environment' | cut -d':' -f2)" != " None" ]; then
        conda deactivate
    fi
    OUTPUT=$(bash test_mirrors_cran.sh)
    echo "$OUTPUT" | sed "s/^/[ DEBUG    ] /g"
    TEST_RESULT=$(echo $OUTPUT | grep "CRAN working OK")
    if [ "$TEST_RESULT" == "" ]; then
        return 1
    fi
    return 0
}


do_test() {
    TEST_NAME=$1
    echo -e "\033[0;36m[ RUNNING  ]\033[0m $TEST_NAME"
    START_TIME=$(date +%s)
    $TEST_NAME; TEST_RESULT=$?
    DURATION=$(($(date +%s) - $START_TIME))
    if [[ $TEST_RESULT -eq 0 ]]; then
        echo -e "\033[0;32m[       OK ]\033[0m $TEST_NAME ($DURATION s)"
        return 0
    else
        echo -e "\033[0;31m[   FAILED ]\033[0m $TEST_NAME ($DURATION s)"
        return 1
    fi
}


# Run all tests
N_PASSING=0
N_FAILING=0


# Julia tests
do_test julia_packages
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test julia_functionality
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi


# Python 2.7 tests
do_test python_27_packages
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test python_27_functionality
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test python_27_mirrors_pypi
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi


# Python 3.6 tests
do_test python_36_packages
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test python_36_functionality
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test python_36_mirrors_pypi
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi


# Python 3.7 tests
do_test python_37_packages
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test python_37_functionality
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test python_37_mirrors_pypi
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi


# R tests
do_test R_packages
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test R_functionality
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test R_mirrors_cran
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi


# Summary
N_TESTS=$(($N_PASSING + $N_FAILING))
echo -e "\033[0;36m[ SUMMARY  ]\033[0m Ran $N_TESTS tests."
echo -e "\033[0;36m[ SUMMARY  ]\033[0m $N_PASSING / $N_TESTS [$((100 * $N_PASSING / $N_TESTS))%] passed"

