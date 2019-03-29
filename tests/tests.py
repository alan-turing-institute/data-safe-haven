import re
import os
import sys
import unittest

import pkg_resources


PY_VERSIONS_DSG = ["27", "36", "37"]  # version numbers in remote
PY_VERSIONS_LOCAL = ["27", "36"]

PACKAGE_DIR = "../new_dsg_environment/azure-vms/package_lists/"
PACKAGE_PREFIXES = ["requested-", "utility-packages-"]
PACKAGE_SUFFIX = ".list"

def is_linux():
    """Returns true if running on Linux.
    """
    return "Linux" == os.uname()[0]

def get_version():
    """Gets the current Python version in a string.
    """
    return "".join([str(n) for n in sys.version_info[:2]])

def get_missing_packages():
    """Gets the packages required and optional for this version that are
    not installed.
    """
    version = get_version()
    required_missing = []
    optional_missing = []
    for prefix in PACKAGE_PREFIXES:
        path = os.path.join(PACKAGE_DIR, prefix + version + PACKAGE_SUFFIX)
        with open(path) as f:
            contents = f.read(-1)
            lines = re.split('\r|\n', contents)
            packages = [l for l in lines if "" != l]

            for p in packages:
                try:
                    dist_info = pkg_resources.get_distribution(p)
                except pkg_resources.DistributionNotFound:
                    if prefix.startswith("requested"):
                        required_missing.append(p)
                    else:
                        optional_missing.append(p)
    return (required_missing, optional_missing)

class Tests(unittest.TestCase):
    """Run tests for installation of Python."""
        
    def test_python_version(self):
        py_version = get_version()
        expected_py_versions = PY_VERSIONS_DSG if is_linux() else PY_VERSIONS_LOCAL
        self.assertTrue(py_version in expected_py_versions)

    def test_packages(self):
        required_missing, optional_missing = get_missing_packages()
        if required_missing:
            print("\n\n** The following required packages are missing: **")
            print("\n".join(required_missing))
            print("** The above required packages are missing! **\n\n")
        if optional_missing:
            print("\n\n** The following optional packages are missing: **")
            print("\n".join(optional_missing))
            print("** The above optional packages are missing! **\n\n")
        if optional_missing or required_missing:
            self.fail("Required and/or optional packages are missing")

if '__main__' == __name__:
    import unittest
    unittest.main()
