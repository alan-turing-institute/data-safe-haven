import glob
import os
import shutil
import subprocess
import sys
import warnings
import pkg_resources

versions = {
    pkg.split(" ")[0]: pkg.split(" ")[-1]                               # get package name and version
    for pkg in subprocess.run(["pip", "list"], stdout=subprocess.PIPE)  # ... from pip list
        .stdout.decode().split("\n")[1:]                                # after splitting on each line and discarding the header
}

# Some packages cannot be imported so we skip them.
KNOWN_RESOURCE_ISSUES = [
    "backports",  # does not define a package
    "xgboost",    # has dependencies on an external library
]

# For these packages we check for an executable as they are not importable
NON_IMPORTABLE_PACKAGES = {"repro-catalogue": "catalogue"}

# Some packages are imported using a different name than they `pip install` with
IMPORTABLE_NAMES = {
    "PyYAML": "yaml",
    "beautifulsoup4": "bs4",
    "DataShape": "datashape",
    "Fiona": "fiona",
    "Flask": "flask",
    "Jinja2": "jinja2",
    "Markdown": "markdown",
    "pandas-profiling": "pandas_profiling",
    "Pillow": "PIL",
    "protobuf": "google.protobuf",
    "pyshp": "shapefile",
    "pystan": ("stan" if int(versions["pystan"][0]) >= 3 else "pystan"),
    "python-dateutil": "dateutil",
    "PyWavelets": "pywt",
    "scikit-image": "skimage",
    "scikit-learn": "sklearn",
    "spacy-langdetect": "spacy_langdetect",
    "Sphinx": "sphinx",
    "SQLAlchemy": "sqlalchemy",
    "tensorflow-estimator": "tensorflow.estimator",
    "Theano": "theano",
    "torchvision": "torchvision",
    "XlsxWriter": "xlsxwriter",
}


def get_python_version():
    """
    Get the current Python version as a string.
    """
    v_info = sys.version_info
    return {
        "full": "{}.{}.{}".format(v_info.major, v_info.minor, v_info.micro),
        "short": "{}{}".format(v_info.major, v_info.minor),
    }


def import_tensorflow():
    try:
        warnings.simplefilter("ignore")
        os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"
        module_ = __import__("tensorflow.python.client", fromlist=["device_list"])
        device_names = [d.name for d in module_.device_lib.list_local_devices()]
        print("Tensorflow can see the following devices %s" % device_names)
        return True
    except ImportError:
        return False


def get_missing_packages(packages):
    """
    Check that all requested packages are importable and that resources exist
    """
    warnings.filterwarnings("ignore", category=DeprecationWarning)
    warning, missing = [], []
    for package in packages:
        # Some packages are not importable so we test for the executable instead
        if package in NON_IMPORTABLE_PACKAGES.keys():
            if not shutil.which(NON_IMPORTABLE_PACKAGES[package]):
                missing.append(package)
                continue
        # Test whether we can import
        else:
            importable_name = (
                IMPORTABLE_NAMES[package] if package in IMPORTABLE_NAMES else package
            )
            try:
                _ = __import__(importable_name)
            except ImportError:
                missing.append(package)
                continue
        # If we can, then test whether package resources exist
        if package not in KNOWN_RESOURCE_ISSUES:
            try:
                pkg_resources.get_distribution(package)
            except pkg_resources.DistributionNotFound:
                warning.append(package)

    # Check tensorflow explicitly
    if not import_tensorflow():
        missing.append("tensorflow")

    return (warning, missing)


def test_packages():
    version = get_python_version()
    print("Python version %s found" % version["full"])
    pypi_package_lists = glob.glob(
        os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "..",
            "package_lists",
            "packages-python-pypi*",
        )
    )
    matching_package_lists = [
        _list for _list in pypi_package_lists if version["short"] in _list
    ]
    if matching_package_lists:
        with open(matching_package_lists[0], "r") as f_packages:
            packages = [
                p.strip() for p in f_packages.readlines() if not p.startswith("#")
            ]
        print("Testing {} Python packages".format(len(packages)))
        warning, missing = get_missing_packages(packages)
        if warning:
            print(f"The following {len(warning)} packages may be missing resources:")
            print("\n".join(warning))
        if missing:
            print(f"The following {len(missing)} packages are missing or broken:")
            print("\n".join(missing))
        if (not warning) and (not missing):
            print(f"All {len(packages)} packages are installed")


if __name__ == "__main__":
    test_packages()
