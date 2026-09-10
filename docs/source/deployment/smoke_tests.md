(workspace_smoke_tests)=

# Run workspace smoke tests

After deploying an SRE, you can run the installed smoke-test suite from a workspace to check that the environment is functioning correctly.

The tests are installed in `/usr/local/smoke_tests` and should be run as root from that directory. Running them from the smoke-test directory is required because the suite invokes several companion scripts using relative paths.

:::{code} shell
$ sudo -i
# cd /usr/local/smoke_tests
# ./run_all_tests.bats
:::

The suite checks workspace mounts, Python and R package repositories and functionality, and database connectivity when database credentials are available.
