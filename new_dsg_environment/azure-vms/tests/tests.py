import re
import os
import sys
import unittest

import pkg_resources


PY_VERSIONS_DSG = ["27", "36", "37"]  # version numbers in remote
PY_VERSIONS_LOCAL = ["27", "36"]

PACKAGE_DIR = os.path.join(os.path.realpath(".."), "package_lists")
PACKAGE_SUFFIXES = ["-requested-packages.list", "-other-useful-packages.list"]

# Some packages cannot be imported so we skip them.
PACKAGES_TO_SKIP = [
    "jupyter",        # not a python package
    "numpy-base",     # not an importable package
    "r-irkernel",     # not a python package
    "backports",      # not an importable package
    "tensorflow-gpu", # add a special test for this
]

# Some packages have different names in conda from the importable name
PACKAGE_REPLACEMENTS = {
    "pytables": "tables",
    "pytorch": "torch",
    "sqlite": "sqlite3",
    "yaml": "pyyaml",
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

def clean_suffix(p):
    """Cleans suffix of packages to avoid maintaining different variables,
    so we save into a variable depending on the value of the prefix, 
    e.g., "-requested-packages.list" -> "requested" and "-other-useful-packages.list" -> "other-useful"
    """
    return p[1:p.find("-packages")]


def import_package(package_name):
    """Explicitly test imports."""
    if package_name == "graph_tool":
        try:
            import graph_tool
            return True
        except ModuleNotFoundError as e:
            return False
    if package_name == "sqlite3":
        try:
            import sqlite3
            return True
        except ModuleNotFoundError as e:
            return False
    return False


def get_package_lists():
    """Reads the package lists and returns a tuple with required and optional
    packages.
    """
    result = dict()
    version = get_version()
    for suffix in PACKAGE_SUFFIXES:
        path = os.path.join(PACKAGE_DIR, "python" + version + suffix)
        with open(path) as f:
            contents = f.read(-1)
            lines = re.split('\r|\n', contents)
            packages = [l for l in lines if "" != l]

            result[clean_suffix(suffix)] = packages
            
    return result

def check_tensorflow():
    print("Testing tensorflow...")
    try:
        from tensorflow.python.client import device_lib
        device_names = [d.name for d in device_lib.list_local_devices()]
        print("Tensorflow can see the following devices:\n{}".format(device_names))
        return True
    except ImportError:
        return False


def get_missing_packages():
    """Gets the packages required and optional for this version that are
    not installed.
    """
    version = get_version()
    all_packages = get_package_lists()
    warning, missing = {}, {}

    for key in all_packages:
        packages = all_packages[key]
        warning[key], missing[key] = [], []
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
                # Test whether we can import
                if import_package(q):
                    warning[key].append(full_name)
                else:
                    missing[key].append(full_name)

    # Check tensorflow explicitly
    if not check_tensorflow():
        missing["requested"] = "tensorflow-gpu"
                
    return (warning, missing)

class Tests(unittest.TestCase):
    """Run tests for installation of Python."""
        
    def test_python_version(self):
        py_version = get_version()
        expected_py_versions = PY_VERSIONS_DSG if is_linux() else PY_VERSIONS_LOCAL
        self.assertTrue(py_version in expected_py_versions)

    def test_packages(self):
        warning, missing = get_missing_packages()
        fail = False
        for key, packages in warning.items():
            if packages:
                print("\n** The following %s packages can be imported but had pkg_resource issues: **" % key)
                print("\n".join(packages))
                print("** The above %s packages can be imported but had pkg_resource issues: **" % key)
        for key, packages in missing.items():
            if packages:
                print("\n** The following %s packages are missing: **" % key)
                print("\n".join(packages))
                print("** The above %s packages are missing! **\n" % key)
                fail = True
        if fail:
            self.fail("Required and/or optional packages are missing")
    

if '__main__' == __name__:
    import unittest
    unittest.main()
