
# Tests

## R

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

## Python

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

