import os
import sys
import unittest

import numpy as np

VERSIONS_DSG = [(2, 7, 16), (3, 6, 8), (3, 7, 2)]  # tuples with version numbers
VERSIONS_LOCAL = [(3, 6, 7)]

def is_mac():
    """Returns true if running on macOS.
    """
    return "posix" == os.name

class Tests(unittest.TestCase):
    """Run tests for installation of Python."""
        
    def test_version(self):
        version = sys.version_info[:3]
        expected_versions = VERSIONS_LOCAL if is_mac() else VERSIONS_DSG
        self.assertTrue(version in expected_versions)

if '__main__' == __name__:
    import unittest
    unittest.main()
