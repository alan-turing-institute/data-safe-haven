import re
import os
import sys
import unittest
import pkg_resources
import warnings

PY_VERSIONS_DSG = ["27", "36", "37"]  # version numbers in remote
PY_VERSIONS_LOCAL = ["27", "36"]

PACKAGE_DIR = os.path.join(os.path.realpath(".."), "package_lists")
PACKAGE_SUFFIX = "-packages.list"

# Some packages cannot be imported so we skip them.
PACKAGES_TO_SKIP = [
    "backports",                   # not an importable package
    "jupyter",                     # not a python package
    "numpy-base",                  # not an importable package
    "nltk_data",                   # not a python package
    "r-irkernel",                  # not a python package
    "spacy-model-en_core_web_lg",  # not a python package
    "spacy-model-en_core_web_md",  # not a python package
    "spacy-model-en_core_web_sm",  # not a python package
    "tensorflow-gpu",              # add a special test for this
]

# Some packages have different names in conda from the importable name
PACKAGE_REPLACEMENTS = {
    "python-annoy": "annoy",
    "python-blosc": "blosc",
    "pytables": "tables",
    "pytorch": "torch",
    "sqlite": "sqlite3",
    "yaml": "pyyaml",
}

# These packages will fail the pkg_resources check because they're written in C/C++
KNOWN_CPP_PACKAGES = [
    "graph_tool",
    "sqlite3",
    "xgboost",
]


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


def import_package(package_name):
    """Explicitly test imports."""
    warnings.filterwarnings("ignore", category=DeprecationWarning)
    try:
        _ = __import__(package_name)
        return True
    except ImportError:
        pass
    return False


def get_package_lists():
    """Reads the package lists and returns a tuple with required and optional
    packages.
    """
    packages = []
    version = get_version()
    path = os.path.join(PACKAGE_DIR, "python" + version + PACKAGE_SUFFIX)
    with open(path) as f:
        contents = f.read(-1)
        lines = re.split('\r|\n', contents)
        packages = [l for l in lines if "" != l]
    return packages


def check_tensorflow():
    # print("Testing tensorflow...")
    try:
        warnings.simplefilter("ignore")
        from tensorflow.python.client import device_lib
        os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"
        device_names = [d.name for d in device_lib.list_local_devices()]
        # print("Tensorflow can see the following devices:\n{}".format(device_names))
        print("Tensorflow can see the following devices %s" % device_names)
        return True
    except ImportError:
        return False


def get_missing_packages(packages):
    """Gets the packages required and optional for this version that are
    not installed.
    """
    warning, missing = [], []

    for p in packages:
        q = clean_package_name(p)

        if not q:
            continue

        try:
            pkg_resources.get_distribution(q)
        except pkg_resources.DistributionNotFound:
            full_name = p
            if q != p:
                full_name += " (%s)" % q
            # Test whether we can import
            if import_package(q):
                if q not in KNOWN_CPP_PACKAGES:
                    warning.append(full_name)
            else:
                missing.append(full_name)

    # Check tensorflow explicitly
    if not check_tensorflow():
        missing = "tensorflow-gpu"

    return (warning, missing)


# class Tests(unittest.TestCase):
#     """Run tests for installation of Python."""

#     def test_python_version(self):
#         py_version = get_version()
#         expected_py_versions = PY_VERSIONS_DSG if is_linux() else PY_VERSIONS_LOCAL
#         self.assertTrue(py_version in expected_py_versions)

#     def test_packages(self):
#         packages = get_package_lists()
#         print("Testing", len(packages), "python", get_version(), "packages")
#         warning, missing = get_missing_packages(packages)
#         fail = False
#         if warning:
#             print("\n** The following packages can be imported but had pkg_resource issues (possibly because they are C/C++ packages): **")
#             print("\n".join(warning))
#             print("** The above packages can be imported but had pkg_resource issues (possibly because they are C/C++ packages): **")
#         if missing:
#             print("\n** The following packages are missing: **")
#             print("\n".join(missing))
#             print("** The above packages are missing! **\n")
#             fail = True
#         if fail:
#             self.fail("Required and/or optional packages are missing")

def test_python_version():
    py_version = get_version()
    expected_py_versions = PY_VERSIONS_DSG if is_linux() else PY_VERSIONS_LOCAL
    if py_version not in expected_py_versions:
        print("Python version %s could not be interpreted" % py_version)
    else:
        print("Python version %s found" % py_version)

def test_packages():
    packages = get_package_lists()
    print("Testing %i python packages" % len(packages))
    warning, missing = get_missing_packages(packages)
    success = True
    if warning:
        print("\n** The following packages can be imported but had pkg_resource issues (possibly because they are C/C++ packages): **")
        print("\n".join(warning))
        print("** The above packages can be imported but had pkg_resource issues (possibly because they are C/C++ packages): **")
    if missing:
        print("\n** The following packages are missing: **")
        print("\n".join(missing))
        print("** The above packages are missing! **\n")
        success = False

    if success:
        print("All packages were found")
    else:
        print("%i packages are missing" % len(missing))


if __name__ == "__main__":
    #unittest.main()
    test_python_version()
    test_packages()
