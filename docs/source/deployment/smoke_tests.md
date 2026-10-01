(workspace_smoke_tests)=

# Run workspace smoke tests

After deploying an SRE, you can run the installed smoke-test suite from each workspace virtual machine to check that the environment is functioning correctly.

Wait for cloud-init to finish on a workspace before running the smoke tests. The deployment CLI can return control before cloud-init and the initial desired-state configuration have completed, so a newly deployed virtual machine may not be ready immediately.

Run the smoke tests separately on every deployed workspace virtual machine. In the Azure portal, open the virtual machine's **Serial console** and sign in as `dshadmin`, which is the workspace administrator account with `sudo` access. The password is stored in the SRE `secrets` Key Vault in the `password-workspace-admin` secret.

The tests are installed in `/usr/local/smoke_tests` and should be run as root from that directory. Running them from the smoke-test directory is required because the suite invokes several companion scripts using relative paths.

:::{code} shell
$ sudo -i
# cd /usr/local/smoke_tests
# ./run_all_tests.bats
:::

The suite checks workspace mounts, Python and R package repositories and functionality, and database connectivity. A full run typically takes six minutes or more and requires no user interaction after it starts.

The database tests are included even when a particular database service is not deployed. If credentials are available but that service is absent, the corresponding database tests can report `not ok`; this is expected. Focus on failures for functionality that is actually installed in the SRE. For example, an SRE without MS SQL may produce output like:

:::{code} text
1..13
ok 1 Mounted drives (/mnt/input)
ok 2 Mounted drives (/home)
ok 3 Mounted drives (/mnt/output)
ok 4 Mounted drives (/mnt/shared)
ok 5 Mounted drives (/var/local/ansible)
ok 6 Python package repository
ok 7 R package repository
ok 8 Python functionality
ok 9 R functionality
not ok 10 MS SQL database (Python)
not ok 11 MS SQL database (R)
ok 12 Postgres database (Python)
ok 13 Postgres database (R)
:::
