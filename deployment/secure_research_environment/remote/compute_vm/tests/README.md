
# Tests

## Prerequisites
The package installation tests require a copy of the `package_lists` folder from the `<safe-haven-repository>/environment_configs/` folder to exist at the same level as the folder containing this README file.


## Test everything
You can run all the following tests using
```
bats run_all_tests.bats
```

Alternatively, you can run individual tests as described below.


## Julia
The installed Julia version can be seen by running `julia --version`.

### Testing whether all packages are installed
Run the tests with:
```bash
$ julia test_packages_installed_julia.jl
```

The installation check will take several minutes to run.
The expected output for a successful test is:
```
Testing <number of packages> Julia packages
[ Info: JavaCall could not determine javapath from `which java`
All <number of packages> packages are installed
```

### Minimal functionality testing
Run the minimal functionality tests with:
```bash
$ julia test_functionality_julia.jl
```

The expected output for a successful test is:
```
All functionality tests passed
```


## Python
The list of available Python versions can be seen by typing `pyenv versions`
For each of the three Python versions that we want to test (2.7.X, 3.6.X, 3.7.X), activate the appropriate version with `pyenv shell <version number>`.

### Testing whether all packages are installed
Run the tests with:
```bash
$ pyenv shell <version number>
$ python test_packages_installed_python.py
```

The installation check will take several minutes to run.
The expected output for a successful test is:
```
Python version <version number> found
Testing <number of packages> Python packages
[... possible warning/deprecation messages]
Tensorflow can see the following devices: [<list of devices>]
All <number of packages> packages are installed
```

The message `CUDA_ERROR_NO_DEVICE: no CUDA capable device is detected` is **not** expected if you are using a GPU-enabled VM e.g. NC series

### Minimal functionality testing
Run the minimal functionality tests with:
```bash
$ python test_functionality_python.py
```

The expected output for a successful test is:
```
Logistic model ran OK
All functionality tests passed
```

### Testing package mirrors
To test the PyPI mirror run:

```bash
$ ./test_mirrors_pypi.sh
```

This will attempt to install a few packages from the internal PyPI mirror.
The expected output for a successful test is:
```
Logistic model ran OK
All functionality tests passed
```


## R
The installed R version can be seen by running `R --version`.

### Testing whether all packages are installed
Run the tests with:
```bash
$ Rscript test_packages_installed_R.R
```

The installation check will take several minutes to run.

There are a few known packages that will cause warnings and errors during this test.
- `BiocManager`: False positive - warning about not being able to connect to the internet
- `clusterProfiler`: Error is `multiple methods tables found for ‘toTable’`. Not yet understood
- `flowUtils`: False positive - warning about string translations
- `GOSemSim`: False positive - no warning when package is loaded manually
- `graphite`: False positive - no warning when package is loaded manually
- `rgl`: Error is because the X11 server could not be loaded
- `tmap`: False positive - no warning when package is loaded manually

Any other warnings or errors are unexpected.
The expected output for a successful test is:

```
[1] "Testing <number of CRAN packages> CRAN packages"
[1] "Testing <number of BioConductor packages> Bioconductor packages"
[1] "All <total number of packages> packages are installed"
```

### Minimal functionality testing
Run the minimal functionality tests with:
```bash
$ Rscript test_functionality_R.R
```

The expected output for a successful test is:
```
[1] "Logistic regression ran OK"
[1] "Clustering ran OK"
[1] "All functionality tests passed"
```

### Testing package mirrors
To test the CRAN mirror run:

```bash
$ ./test_mirrors_cran.sh
```

This will attempt to install a few test packages from the internal CRAN mirror.
The expected output for a successful test is:

```
Attempting to install ahaz...
... ahaz installation succeeded
Attempting to install yum...
... yum installation succeeded
CRAN working OK
```

If one or more packages fail to install, the list of failing packages will be displayed, followed by `CRAN installation failed`
