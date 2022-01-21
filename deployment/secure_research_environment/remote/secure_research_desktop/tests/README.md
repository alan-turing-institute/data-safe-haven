# Tests

## Prerequisites

The package installation tests require the following layout:

```none
├── README.md
├── run_all_tests.bats
├── package_lists
│   ├── packages-julia.list
│   ├── packages-python-3.10.2.list
│   ├── packages-python-3.8.12.list
│   ├── packages-python-3.9.10.list
│   ├── packages-python-system.txt
│   ├── packages-r-bioconductor.list
│   └── packages-r-cran.list
└── tests
    ├── test_databases_python.py
    ├── test_databases_R.R
    ├── test_databases.sh
    ├── test_functionality_julia.jl
    ├── test_functionality_python.py
    ├── test_functionality_R.R
    ├── test_mounted_drives.sh
    ├── test_packages_installed_julia.jl
    ├── test_packages_installed_python.py
    ├── test_packages_installed_R.R
    ├── test_repository_python.sh
    ├── test_repository_R.sh
    └── test_virtual_environments_python.sh
```

## Test everything

You can run all the non-interactive tests using

```bash
bats run_all_tests.bats
```

Alternatively, you can run individual tests as described below.

In order to test Jupyter run the following for each Python version you want to test:

```bash
pyenv shell <version number>
jupyter notebook
```

and run `test_jupyter.ipynb` ensuring that the detected Python version matches throughout.

## Testing mounted drives

In order to test that all remote drives are correctly mounted you can run the following for each drive you want to test:

```bash
> bash tests/test_mounted_drives.sh -d <drive name>
```

The expected output for a successful test is:

```none
All tests passed for '<drive name>'
```

## Julia

The installed Julia version can be seen by running `julia --version`.

### Testing whether all packages are installed

Run the tests with:

```bash
> julia tests/test_packages_installed_julia.jl
```

The installation check will take several minutes to run.
The expected output for a successful test is:

```none
Testing <number of packages> Julia packages
[several messages of the form: Testing '<package name>' ...]
All <number of packages> packages are installed
```

### Minimal functionality testing

Run the minimal functionality tests with:

```bash
> julia tests/test_functionality_julia.jl
```

The expected output for a successful test is:

```none
All functionality tests passed
```

## Python

The list of available Python versions can be seen by typing `pyenv versions`
For each of the Python versions that you want to test (eg. 3.8.x, 3.9.x, 3.10.x), activate the appropriate version with `pyenv shell <version number>`.

### Testing whether all packages are installed

Run the tests with:

```bash
> pyenv shell <version number>
> python tests/test_packages_installed_python.py
```

The installation check will take several minutes to run.
The expected output for a successful test is:

```none
Python version <version number> found
Testing <number of packages> Python packages
[several messages of the form: Testing '<package name>' ...]
Tensorflow can see the following devices: [<list of devices>]
All <number of packages> packages are installed
```

The message `CUDA_ERROR_NO_DEVICE: no CUDA capable device is detected` is **not** expected if you are using a GPU-enabled VM e.g. NC series

### Minimal functionality testing

Run the minimal functionality tests with:

```bash
> python tests/test_functionality_python.py
```

The expected output for a successful test is:

```none
Logistic model ran OK
All functionality tests passed
```

### Testing package mirrors

To test the PyPI mirror run:

```bash
> bash tests/test_repository_python.sh
```

This will attempt to install a few packages from the internal PyPI mirror.
The expected output for a successful test is:

```none
Successfully installed pip-21.3.1
Attempting to install absl-py...
... absl-py installation succeeded
Attempting to install zope.interface...
... zope.interface installation succeeded
All packages installed successfully
```

### Testing databases

To test database connectivity you will need to know the connection details and can then run something like:

```
> python tests/test_databases_python.py --db-type mssql --db-name master --port 1433 --server-name MSSQL-T3MSRDS.testc.dsgroupdev.co.uk
```

This will attempt to connect to the relevant database server
The expected output for a successful test is:

```none
Attempting to connect to 'master' on 'MSSQL-T3MSRDS.testc.dsgroupdev.co.uk' via port 1433
  TABLE_CATALOG TABLE_SCHEMA        TABLE_NAME  TABLE_TYPE
0        master          dbo   spt_fallback_db  BASE TABLE
1        master          dbo  spt_fallback_dev  BASE TABLE
2        master          dbo  spt_fallback_usg  BASE TABLE
3        master          dbo        spt_values        VIEW
4        master          dbo       spt_monitor  BASE TABLE
All database tests passed
```

### Testing Python virtual environments

To test the creation and management of virtual environments run the following for each Python version you want to test:

```bash
> bash -i tests/test_virtual_environments_python.sh <python version>
```

This will attempt to create, use and destroy a `pyenv` virtual environment.
The expected output for a successful test is:

```none
Preparing to test Python 3.8.12  with virtual environment 3.8.12-test
[✔] Testing that pyenv exists
[✔] Testing pyenv versions
[✔] Testing pyenv virtualenvs
[✔] Testing virtualenv creation
[✔] Testing virtualenv activation
[✔] Testing Python version
[✔] Testing virtualenv packages
[✔] Testing virtualenv package installation
[✔] Testing virtualenv deletion
All tests passed for Python 3.8.12
```

## R

The installed R version can be seen by running `R --version`.

### Testing whether all packages are installed

Run the tests with:

```bash
> Rscript tests/test_packages_installed_R.R
```

The installation check will take several minutes to run.
The expected output for a successful test is:

```none
[1] "Testing <number of CRAN packages> CRAN packages"
[several messages of the form: [1] "Testing '<package name>' ..."]
[1] "Testing <number of BioConductor packages> Bioconductor packages"
[several messages of the form: [1] "Testing '<package name>' ..."]
[1] "All <total number of packages> packages are installed"
```

### Minimal functionality testing

Run the minimal functionality tests with:

```bash
> Rscript tests/test_functionality_R.R
```

The expected output for a successful test is:

```none
[1] "Logistic regression ran OK"
[1] "Clustering ran OK"
[1] "All functionality tests passed"
```

### Testing package mirrors

To test the CRAN mirror run:

```bash
> bash tests/test_repository_R.sh
```

This will attempt to install a few test packages from the internal CRAN mirror.
The expected output for a successful test is:

```none
Attempting to install argon2...
... argon2 installation succeeded
Attempting to install zeallot...
... zeallot installation succeeded
All packages installed successfully
```

### Testing databases

To test database connectivity you will need to know the connection details and can then run something like:

```
> Rscript tests/test_databases_R.R mssql master 1433 MSSQL-T3MSRDS.testc.dsgroupdev.co.uk
```

This will attempt to connect to the relevant database server
The expected output for a successful test is:

```none
[1] "Attempting to connect to 'master' on 'MSSQL-T3MSRDS.testc.dsgroupdev.co.uk' via port '1433"
  TABLE_CATALOG TABLE_SCHEMA       TABLE_NAME TABLE_TYPE
1        master          dbo  spt_fallback_db BASE TABLE
2        master          dbo spt_fallback_dev BASE TABLE
3        master          dbo spt_fallback_usg BASE TABLE
4        master          dbo       spt_values       VIEW
5        master          dbo      spt_monitor BASE TABLE
[1] "All database tests passed"
```
