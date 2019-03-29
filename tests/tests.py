import os
import sys
import unittest

import pkg_resources


PY_VERSIONS_DSG = ["2.7", "3.6", "3.7"]  # tuples with version numbers
PY_VERSIONS_LOCAL = ["2.7", "3.6"]

def is_linux():
    """Returns true if running on Linux.
    """
    return "Linux" == os.uname()[0]

def get_version():
    """Gets the current Python version in a string.
    """
    return ".".join(sys.version_info[:2])

def get_package()

class Tests(unittest.TestCase):
    """Run tests for installation of Python."""
        
    def test_python_version(self):
        py_version = get_version()
        expected_py_versions = PY_VERSIONS_DSG if is_linux() else PY_VERSIONS_LOCAL
        self.assertTrue(py_version in expected_py_versions)

    def test_packages(self):
        for p in PACKAGES:
            try:
                dist_info = pkg_resources.get_distribution(p)
            except pkg_resources.DistributionNotFound:
                self.fail("Package %s not installed" %p)

if '__main__' == __name__:
    import unittest
    unittest.main()
