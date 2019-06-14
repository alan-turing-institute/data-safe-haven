
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
- `rgl`: This package is successfully installed, but required a GUI to load
- `clusterProfiler`: Error is `multiple methods tables found for ‘toTable’`. Not yet understood
- `GOSemSim`: False positive - no warning on package load
- `graphite`: False positive - no warning on package load

The expected output for a successful test is:

```
Read <num-r-packages> items
Read <num-bioconductor-packages> items
[1] "The following packages gave a warning:"
[1] "rgl"             "clusterProfiler" "GOSemSim"        "graphite"
[1] "All the packages above gave a warning!"
```

If you get any other warnings or errors, please contact REG to investigate.

### Testing package use

Run the two data science scripts with these commands and this expected result:

```bash
$ Rscript test_clustering.R
[1] "Clustering ran OK"
$ Rscript test_logistic_regression.R
[1] "Logistic regression ran OK"
```

### Testing package mirrors

To test CRAN mirror run: `bash test_cran.sh`

This will attempt to install a few test packages from the internal PyPI mirror.

If all packages install successfully, `**CRAN working OK**` will be displayed as the final line of the output (after the package installation progress).

If one or more packages fail to install, `**CRAN failed**` (followed by a list of failing packages) will be displayed as the final lines of the output (after the package installation progress).

## Python

For each of the three Pyhton versions installed (2.7, 3.6, 3.7), switch to environment `pyMN`, where `M` is the major version number and `N` is the minor version number (e.g. for Python 3.6, use `py36`) and do the following:

Activate the conda environment for each Python version with `conda activate pyMN`

### Testing package installation
- Run the Python tests with `python tests.py`. The following warnings are expected:

  - `Your CPU supports instructions that this TensorFlow binary was not compiled to use`
  - `CUDA_ERROR_NO_DEVICE: no CUDA capable device is detected` (you should **not** get this error on GPU VMs - e.g. NC series)

If you get any otrher errors please contact REG to investigate.

### Testing package use

First, run the test of the data science scripts in R as those generate data for
the Python scripts as well.

Then, run the one data science script with this command and this expected result:

```bash
$ python test_logistic_regression.py
Logistic model ran OK
```

### Testing package mirrors

To test PyPI mirror run: `bash test_pypi.sh`