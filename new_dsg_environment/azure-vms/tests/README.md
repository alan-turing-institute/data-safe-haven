
# Tests

## Prerequisites
The package installation tests require a copy of the `package_lists` folder in the `<safe-haven-repository>/new_dsg_environment/azure-vms/` folder to exist at the same level as the folder containing this README file.

## R

### Testing package installation

Switch to System R with 

```
conda deactivate
```

Run the tests with:

```
Rscript test_package_installation.R
```

The installation check will take several minutes to run.

There are a few known packages that will cause warnings and errors during this test.
- rgl: This package is successfully installed, but required a GUI to load
- ballgown: This package cannot currently be installed
- DMRate: This package cannot currently be installed
- maftools: This package cannot currently be installed
- RCGAbiolinks: This package cannot currently be installed

The expected output for a successful test is:

```
[1] "The following packages gave a warning:"
[1] "rgl"
[1] "All the above gave a warning!"
[1] "The following packages gave an error:"
[1] "ballgown"    "DMRate"    "maftools"    "RCGAbiolinks"
[1] "All the above gave an error!"
```

If any additonal packages appear on the warning or error list, please contact REG to investigate:

### Testing package use

Run the two data science scripts with these commands and this expected result:

```bash
$ Rscript test_clustering.R 
[1] "Clustering ran OK"
$ Rscript test_logistic_regression.R 
[1] "Logistic regression ran OK"
```

## Python

### Testing package installation

For each of the three Pyhton versions installed (2.7, 3.6, 3.7), switch to environment `pyMN`, where `M` is the major version number and `N` is the minor version number (e.g. for Python 3.6, use `py36`) and do the following:

Activate the conda environment for the Python version.

```
conda activate pyMN
```

Run the Python tests with:

```
python tests.py
```

The expected outcome for a successful test is:

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


