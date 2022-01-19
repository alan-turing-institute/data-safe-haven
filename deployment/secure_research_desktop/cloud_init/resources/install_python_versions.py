#! /usr/bin/env python3
import contextlib
import datetime
import glob
import json
import os
import shutil
import subprocess
import sys
import yaml
# Third party libraries
import humanize
from packaging.version import InvalidVersion, Version

def read_yaml(yaml_file):
    with open(yaml_file, "r") as f_yaml:
        requirements = yaml.safe_load(f_yaml)

    for version in requirements["versions"]:
        package_list = []
        for package_name, details in requirements["packages"].items():
            suffix = None
            if details:
                constraints = sum([details.get(v, []) for v in ("all", version)], [])
                if "uninstallable" in constraints:
                    continue
                suffix = ",".join(constraints)
            package_list.append((package_name, suffix))
        yield (version, package_list)

def remove_all(patterns):
    for pattern in patterns:
        for fsobject in glob.glob(pattern):
            with contextlib.suppress(FileNotFoundError):
                try:
                    os.remove(fsobject)
                except IsADirectoryError:
                    shutil.rmtree(fsobject)

def install_python_version(python_version, package_list):
    start_time = datetime.datetime.now()
    print(f">=== {int(start_time.timestamp())} Installing Python {python_version} with {len(package_list)} packages ===<")
    env = os.environ.copy()
    env["PYTHON_CONFIGURE_OPTS"] = "--enable-shared"

    # Write list of package names for later checks
    requested_packages = [pkg[0] for pkg in package_list]
    with open(f"/opt/build/packages/packages-python-{python_version}.list", "w") as f_list:
        f_list.writelines(f"{pkg}\n" for pkg in requested_packages)

    # Install the appropriate Python version
    section_start_time = datetime.datetime.now()
    subprocess.run(["pyenv", "install", "--skip-existing", str(python_version)], env=env)
    pyenv_root = subprocess.run(["pyenv", "root"], env=env, stdout=subprocess.PIPE).stdout.decode().strip()
    exe_path = f"{pyenv_root}/versions/{python_version}/bin"

    # Ensure that we're using the correct version
    env["PYENV_VERSION"] = str(python_version)
    current_version = subprocess.run([f"{exe_path}/python3", "--version"], env=env, stdout=subprocess.PIPE).stdout.decode().split()[-1].strip()
    if current_version != str(python_version):
        raise ValueError(f"Failed to initialise Python version {python_version}")

    # Install and upgrade installation prerequisites
    print(f"Installing and upgrading installation prerequisites for Python {python_version}...")
    subprocess.run([f"{exe_path}/pip3", "install", "--upgrade", "pip", "poetry"], env=env, stderr=subprocess.DEVNULL)
    print(f"Preparing installation took {humanize.naturaldelta(datetime.datetime.now() - section_start_time)}")

    # Get range of available versions for each package using pip
    section_start_time = datetime.datetime.now()
    print(f"Generating package requirements for Python {python_version}...")
    requirements = []
    for (package_name, package_suffix) in package_list:
        if not package_suffix:
            try:
                versions = subprocess.run([f"{exe_path}/pip3", "index", "versions", package_name], env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.decode().split(":")[1].split(",")
                versions = sorted([v for v in map(to_version, versions) if v])
                package_suffix = f">={versions[0]},<={versions[-1]}"
            except IndexError:
                package_suffix = f">=0.0"
        requirements.append(f"{package_name}{package_suffix}")
    print(f"Generating requirements took {humanize.naturaldelta(datetime.datetime.now() - section_start_time)}")

    # Solve dependencies and install using poetry
    section_start_time = datetime.datetime.now()
    print("Installing packages with poetry...")
    remove_all(["poetry.lock", "pyproject.toml"])
    # Generate a TOML file
    with open("/opt/build/python-pyproject-template.toml", "r") as f_template:
        pyproject_toml = [l.replace("PYTHON_ENV_NAME", f"Python {python_version}").replace("PYTHON_VERSION", str(python_version)) for l in f_template.readlines()]
    with open("pyproject.toml", "w") as f_toml:
        f_toml.writelines(pyproject_toml)
    # Add packages to poetry
    subprocess.run([f"{exe_path}/poetry", "config", "virtualenvs.create", "false"], env=env)
    subprocess.run([f"{exe_path}/poetry", "config", "virtualenvs.in-project", "true"], env=env)
    subprocess.run([f"{exe_path}/poetry", "add"] + requirements, env=env)
    # Rehash any CLI programs (eg. safety)
    subprocess.run(["pyenv", "rehash"], env=env)
    # Write package versions to monitoring log
    with open(f"/opt/monitoring/python-{python_version}-package-versions.log", "w") as f_log:
        subprocess.run([f"{exe_path}/poetry", "show"], env=env, stdout=f_log)
        subprocess.run([f"{exe_path}/poetry", "show", "--tree"], env=env, stdout=f_log)
    print(f"Installation took {humanize.naturaldelta(datetime.datetime.now() - section_start_time)}")

    # Install any post-install package requirements
    section_start_time = datetime.datetime.now()
    print("Running post-install commands...")
    installed_package_details = json.loads(subprocess.run([f"{exe_path}/pip3", "list", "--format=json"], env=env, stdout=subprocess.PIPE).stdout.decode())
    installed_packages = [p["name"] for p in installed_package_details]
    if "spacy" in installed_packages:
        for dataset in ["en-core-web-sm", "en-core-web-md", "en-core-web-lg"]:
            if dataset not in installed_packages:
                subprocess.run([f"{exe_path}/python3", "-m", "spacy", "download", dataset.replace("-", "_")], env=env)
    if "nltk" in installed_packages:
        subprocess.run([f"{exe_path}/python3", "-m", "nltk.downloader", "all", "-d", "/usr/share/nltk_data"], env=env)
    if "gensim" in installed_packages:
        env["GENSIM_DATA_DIR"] = "/usr/share/gensim_data"
        for dataset in ["text8", "fake-news"]:
            subprocess.run([f"{exe_path}/python3", "-m", "gensim.downloader", "--download", dataset], env=env)
    # Set the Jupyter kernel name to the full Python version name
    # This ensures that different python3 versions show up separately
    kernel_base = f"{pyenv_root}/versions/{python_version}/share/jupyter/kernels/python3"
    with open(f"{kernel_base}/kernel.json", "r") as f_kernel:
        kernel = json.load(f_kernel)
    kernel["argv"][0] = f"{pyenv_root}/versions/${python_version}/bin/python"
    kernel["display_name"] = f"Python {python_version}"
    with open(f"{kernel_base}/kernel.json", "w") as f_kernel:
        json.dump(kernel, f_kernel, indent=1)
    shutil.move(kernel_base, kernel_base.replace("python3", f"python{python_version.major}{python_version.minor}"))
    print(f"\nPost-install setup took {humanize.naturaldelta(datetime.datetime.now() - section_start_time)}")

    # Check that all requested packages are installed without issues
    section_start_time = datetime.datetime.now()
    print("Sanity checking installed packages...")
    missing_packages = sorted(set(requested_packages).difference(installed_packages))
    if missing_packages:
        print("FATAL: The following requested packages are missing:")
        for missing_package in missing_packages:
            print(f"... {missing_package}")
        raise FileNotFoundError
    print(f"All {len(requested_packages)} requested Python {python_version} packages are installed")
    print(f"Running safety check on Python {python_version} installation...")
    safety_output = f"/opt/monitoring/python-{python_version}-safety-check.json"
    subprocess.run([f"{exe_path}/safety", "check", "--json", "--output", safety_output], env=env)
    subprocess.run([f"{exe_path}/safety", "review", "--full-report", "-f", safety_output], env=env)
    print(f"Checking installed packages took {humanize.naturaldelta(datetime.datetime.now() - section_start_time)}")

    # Clean up
    remove_all(["/root/.pyenv"])
    print(f"Finished installing Python {python_version} after {humanize.naturaldelta(datetime.datetime.now() - start_time)}")


def to_version(input_str):
    try:
        return Version(input_str)
    except InvalidVersion:
        return None

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Path to a YAML file is a required input")
        sys.exit(1)

    # Get list of available Python versions
    available_versions = subprocess.run(["pyenv", "install", "--list"], stdout=subprocess.PIPE).stdout.decode().split("\n")
    available_versions = [v for v in map(to_version, available_versions) if v and not v.is_prerelease]

    with contextlib.suppress(FileExistsError):
        os.mkdir("/opt/build")
        os.mkdir("/opt/monitoring")

    # Install a single Python version
    for version, package_list in read_yaml(sys.argv[1]):
        python_version = sorted([v for v in available_versions if f"{v.major}.{v.minor}" == version])[-1]
        try:
            install_python_version(python_version, package_list)
        except:
            print(f"Python {python_version} could not be installed!")
            sys.exit(1)
