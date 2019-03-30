
# Tests

The package installation tests require a copy of the repo, or at least the same
structure with the files in `../new_dsg_environment/azure-vms/package_lists/`.

## R

### Testing package installation

Switch to System R with 

```
conda deactivate
```

Run the tests with:

```
RScript test_package_installation.R
```

If it's right, it should output something like:

```
[1] "All OK"
```

If some packages are not installed, you should see:

```
[1] "The following packages gave an error:"
[1] "realxl"
```

### Testing package use

Run the two data science scripts with these commands and this expected result:

```bash
$ RScript test_clustering.R 
[1] "Clustering ran OK"
$ RScript test_logistic_regression.R 
[1] "Logistic regression ran OK"
```

## Python

### Testing package installation

For each of the three environments (2.7, 3.6, 3.7), switch to environment `pyMN`
with

```
conda activate pyMN
```

then run the Python tests with:

```
python tests.py
```

If it's right, it should output something like:

```
Ran 2 tests in 0.308s

OK
```

### Testing package use

First, run the test of the data science scripts in R as those generate data for
the Python scripts as well.

Then, run the one data science script with this command and this expected result:

```bash
$ python3 test_logistic_regression.py
Logistic model ran OK
```


