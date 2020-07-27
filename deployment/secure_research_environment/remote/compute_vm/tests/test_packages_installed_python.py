import glob
import os
import shutil
import sys
import warnings
import pkg_resources


# Some packages cannot be imported so we skip them.
KNOWN_RESOURCE_ISSUES = [
    "backports",  # not a single package
    "xgboost",    # has dependencies on external library
]

# For these packages we check for an executable as they are not importable
NON_IMPORTABLE_PACKAGES = {
    "repro-catalogue": "catalogue"
}

# Some packages are imported using a different name than they `pip install` with
IMPORTABLE_NAMES = {
    "PyYAML": "yaml",
    "beautifulsoup4": "bs4",
    "DataShape": "datashape",
    "Fiona": "fiona",
    "Flask": "flask",
    "Jinja2": "jinja2",
    "Keras": "keras",
    "Markdown": "markdown",
    "pandas-profiling": "pandas_profiling",
    "Pillow": "PIL",
    "pyshp": "shapefile",
    "python-dateutil": "dateutil",
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
        module_ = __import__("tensorflow.python.client", fromlist=["device_list"])
        os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"
        device_names = [d.name for d in module_.device_lib.list_local_devices()]
        print("Tensorflow can see the following devices %s" % device_names)
        return True
    except ImportError:
        return False


def get_missing_packages(packages):
    """Gets the packages required and optional for this version that are
    not installed.
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
        os.path.join("..", "package_lists", "packages-python-pypi*")
    )
    matching_package_lists = [_list for _list in pypi_package_lists if version["short"] in _list]
    if matching_package_lists:
        with open(matching_package_lists[0], "r") as f_packages:
            packages = [
                p.strip() for p in f_packages.readlines() if not p.startswith("#")
            ]
        print("Testing {} python packages".format(len(packages)))
        warning, missing = get_missing_packages(packages)
        if warning:
            print(
                "\nThe following {} packages may be missing resources:".format(
                    len(warning)
                )
            )
            print("\n".join(warning))
        if missing:
            print(
                "\nThe following {} packages are missing or broken:".format(
                    len(missing)
                )
            )
            print("\n".join(missing))
        if (not warning) and (not missing):
            print("All {} packages are installed".format(len(packages)))


if __name__ == "__main__":
    test_packages()
