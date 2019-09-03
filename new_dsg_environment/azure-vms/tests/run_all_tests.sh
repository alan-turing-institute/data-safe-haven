#! /bin/bash

# Test R packages
R_packages () {
    conda deactivate
    OUTPUT=$(Rscript test_package_installation.R 2>&1)
    echo "$OUTPUT"
    PROBLEMATIC_PACKAGES=$(echo "$OUTPUT" | grep -A1 "The following packages gave a warning" | grep -v "gave a warning" | cut -d']' -f2)
    OUTCOME=0
    for PROBLEMATIC_PACKAGE in $PROBLEMATIC_PACKAGES; do
        if [[ "$PROBLEMATIC_PACKAGE" != *"clusterProfiler"* ]] && [[ "$PROBLEMATIC_PACKAGE" != *"GOSemSim"* ]] && [[ "$PROBLEMATIC_PACKAGE" != *"graphite"* ]] && [[ "$PROBLEMATIC_PACKAGE" != *"tmap"* ]]; then
            echo "Unexpected problem found with: $PROBLEMATIC_PACKAGE"
            OUTCOME=1
        fi
    done
    return $OUTCOME
}


# Test R clustering
R_clustering () {
    OUTPUT=$(Rscript test_clustering.R)
    echo "$OUTPUT"
    TEST_RESULT=$(echo $OUTPUT | grep "Clustering ran OK")
    if [ "$TEST_RESULT" == "" ]; then
        return 1
    fi
    return 0
}


# Test R logistic regression
R_logistic_regression () {
    OUTPUT=$(Rscript test_logistic_regression.R)
    echo "$OUTPUT"
    TEST_RESULT=$(echo $OUTPUT | grep "Logistic regression ran OK")
    if [ "$TEST_RESULT" == "" ]; then
        return 1
    fi
    return 0
}


# Test CRAN access
R_cran () {
    OUTPUT=$(bash test_cran.sh)
    echo "$OUTPUT"
    TEST_RESULT=$(echo $OUTPUT | grep "CRAN working OK")
    if [ "$TEST_RESULT" == "" ]; then
        return 1
    fi
    return 0
}


# Test python packages
_python_packages () {
    conda activate $1
    OUTPUT=$(python tests.py 2>&1)
    echo "$OUTPUT"
    TEST_RESULT=$(echo $OUTPUT | grep "packages are missing")
    if [ "$TEST_RESULT" != "" ]; then
        conda deactivate
        return 1
    fi
    conda deactivate
    return 0
}
python_27_packages() { _python_packages py27; }
python_36_packages() { _python_packages py36; }
python_37_packages() { _python_packages py37; }


# Test python logistic regression
_python_logistic_regression () {
    conda activate $1
    OUTPUT=$(python test_logistic_regression.py 2>&1)
    echo "$OUTPUT"
    TEST_RESULT=$(echo $OUTPUT | grep "Logistic model ran OK")
    if [ "$TEST_RESULT" == "" ]; then
        conda deactivate
        return 1
    fi
    conda deactivate
    return 0
}
python_27_logistic_regression() { _python_logistic_regression py27; }
python_36_logistic_regression() { _python_logistic_regression py36; }
python_37_logistic_regression() { _python_logistic_regression py37; }


# Test PyPI
_python_pypi () {
    conda activate $1
    OUTPUT=$(bash test_pypi.sh 2>&1)
    echo "$OUTPUT"
    TEST_RESULT=$(echo $OUTPUT | grep "PyPI working OK")
    if [ "$TEST_RESULT" == "" ]; then
        conda deactivate
        return 1
    fi
    conda deactivate
    return 0
}
python_27_pypi() { _python_pypi py27; }
python_36_pypi() { _python_pypi py36; }
python_37_pypi() { _python_pypi py37; }



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

# R tests
do_test R_packages
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test R_clustering
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test R_logistic_regression
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test R_cran
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi


# Python 2.7 tests
do_test python_27_packages
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test python_27_logistic_regression
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test python_27_pypi
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi


# Python 3.6 tests
do_test python_36_packages
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test python_36_logistic_regression
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test python_36_pypi
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi


# Python 3.7 tests
do_test python_37_packages
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test python_37_logistic_regression
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi

do_test python_37_pypi
if [[ $? -eq 0 ]]; then N_PASSING=$(($N_PASSING + 1)); else N_FAILING=$(($N_FAILING + 1)); fi


# Summary
N_TESTS=$(($N_PASSING + $N_FAILING))
echo -e "\033[0;36m[ SUMMARY  ]\033[0m Ran $N_TESTS tests."
echo -e "\033[0;36m[ SUMMARY  ]\033[0m $N_PASSING / $N_TESTS [$((100 * $N_PASSING / $N_TESTS))%] passed"

