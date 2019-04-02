import re
import os
import sys
import unittest

import pkg_resources


PY_VERSIONS_DSG = ["27", "36", "37"]  # version numbers in remote
PY_VERSIONS_LOCAL = ["27", "36"]

PACKAGE_DIR = "../new_dsg_environment/azure-vms/package_lists/"
PACKAGE_DIR = "./"
PACKAGE_PREFIXES = ["requested-", "utility-packages-"]
PACKAGE_SUFFIX = ".list"

# Some packages cannot be called by `import p`, such as
# `numpy-base`. Skip them.
PACKAGES_TO_SKIP = ["numpy-base",
                    "r-irkernel",
                    "backports",
]
PACKAGE_REPLACEMENTS = {"pytorch": "torch",
                        "pytables": "tables",
                        "sqlite": "sqlite3",
                        "tensorflow-gpu": "tensorflow",
}

def is_linux():
    """Returns true if running on Linux.
    """
    return "Linux" == os.uname()[0]

def get_version():
    """Gets the current Python version in a string.
    """
    return "".join([str(n) for n in sys.version_info[:2]])

def clean_package_name(p):
    """Cleans up the package name, e.g. removing hyphens and doing common
    replacements.
    """
    if p in PACKAGES_TO_SKIP:
        return None

    if p in PACKAGE_REPLACEMENTS:
        return PACKAGE_REPLACEMENTS[p]
    
    q = p.replace("-", "_")
    return q

def clean_prefix(p):
    """Cleans prefix of packages to avoid maintaining different variables,
    so we save into a variable depending on the value of the prefix, 
    e.g., "requested-" -> "requested" and "utility-packages-" -> "utility"
    """
    return p[:p.find("-")]
    

def get_package_lists():
    """Reads the package lists and returns a tuple with required and optional
    packages.
    """
    result = dict()
    version = get_version()
    for prefix in PACKAGE_PREFIXES:
        path = os.path.join(PACKAGE_DIR, prefix + version + PACKAGE_SUFFIX)
        with open(path) as f:
            contents = f.read(-1)
            lines = re.split('\r|\n', contents)
            packages = [l for l in lines if "" != l]

            key = clean_prefix(prefix)
            result[key] = packages
            
    return result


def get_missing_packages():
    """Gets the packages required and optional for this version that are
    not installed.
    """
    version = get_version()
    all_packages = get_package_lists()
    missing = dict()

    for key in all_packages:
        packages = all_packages[key]
        missing[key] = []
        for p in packages:

            q = clean_package_name(p)

            if not q:
                continue

            try:
                dist_info = pkg_resources.get_distribution(q)
            except pkg_resources.DistributionNotFound:
                full_name = p
                if q != p:
                    full_name += " (%s)" % q

                missing[key].append(full_name)
                
    return missing

class Tests(unittest.TestCase):
    """Run tests for installation of Python."""
        
    def test_python_version(self):
        py_version = get_version()
        expected_py_versions = PY_VERSIONS_DSG if is_linux() else PY_VERSIONS_LOCAL
        self.assertTrue(py_version in expected_py_versions)

    def test_packages(self):
        missing = get_missing_packages()
        fail = False
        for key in missing:
            packages = missing[key]
            if packages:
                print("\n** The following %s packages are missing: **" % key)
                print("\n".join(packages))
                print("** The above %s packages are missing! **\n" % key)
                fail = True
        if fail:
            self.fail("Required and/or optional packages are missing")

    def test_sqlite3(self):
        try:
            import sqlite3
        except ModuleNotFoundError as e:
            self.fail("Unable to import sqlite3")

    def test_graph_tool(self):
        try:
            import graph_tool
        except ModuleNotFoundError as e:
            self.fail("Unable to import graph_tool")
        

if '__main__' == __name__:
    import unittest
    unittest.main()
