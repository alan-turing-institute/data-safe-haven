These tests should be run **after** the network lock down and peering the SRE and package mirror VNets.
They are automatically uploaded to the SRD during the deployment step.

![Remote: five minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=five%20minutes)

- Use the remote desktop interface at `https://<SRE ID>.<safe haven domain>` to log in to the **SRD** (`SRE-<SRE ID>-<IP last octet>-<version number>`) that you have deployed using the scripts above
- Open a terminal session
- Enter the test directory using `cd /opt/tests`
- Run `bats run_all_tests.bats` .
- If all test results are expected you are done! Otherwise check the `README.md` in this folder for help diagnosing test failures.
