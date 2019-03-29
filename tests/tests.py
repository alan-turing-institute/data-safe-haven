import os
import sys
import unittest

import numpy as np

PY_VERSIONS_DSG = [(2, 7, 16), (3, 6, 8), (3, 7, 2)]  # tuples with version numbers
PY_VERSIONS_LOCAL = [(3, 6, 7)]

def is_linux():
    """Returns true if running on Linux.
    """
    return "Linux" == os.uname()[0]

class Tests(unittest.TestCase):
    """Run tests for installation of Python."""
        
    def test_python_version(self):
        py_version = sys.version_info[:3]
        expected_py_versions = PY_VERSIONS_DSG if is_linux() else PY_VERSIONS_LOCAL
        self.assertTrue(py_version in expected_py_versions)

if '__main__' == __name__:
    import unittest
    unittest.main()
