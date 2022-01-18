#! /usr/bin/env python3
import contextlib
import datetime
import glob
import json
import os
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
            package_list.append([package_name, suffix])
        yield (version, package_list)

def install_python_version(python_version, package_list):
    start_time = datetime.datetime.now()
    print(f">=== {int(start_time.timestamp())} Installing Python {python_version} with {len(package_list)} packages ===<")
    env = os.environ.copy()
    env["PYTHON_CONFIGURE_OPTS"] = "--enable-shared"

    # Install the appropriate Python version
    section_start_time = datetime.datetime.now()
    subprocess.run(["pyenv", "install", str(python_version)], env=env)
    pyenv_root = subprocess.run(['pyenv', 'root'], env=env, stdout=subprocess.PIPE).stdout.decode().strip()
    shims = f"{pyenv_root}/shims"

    # Ensure that we're using the correct version
    env["PYENV_VERSION"] = str(python_version)
    current_version = subprocess.run([f"{shims}/python3", "--version"], env=env, stdout=subprocess.PIPE).stdout.decode().split()[-1].strip()
    if current_version != str(python_version):
        raise ValueError(f"Failed to initialise Python version {python_version}")

    # Install and upgrade installation prerequisites
    print(f"Installing and upgrading installation prerequisites for Python {python_version}...")
    subprocess.run([f"{shims}/pip3", "install", "--upgrade", "pip", "poetry", "safety"], env=env, stderr=subprocess.DEVNULL)
    subprocess.run(["pyenv", "rehash"], env=env)
    print(f"Preparing installation took {humanize.naturaldelta(datetime.datetime.now() - section_start_time)}")

    # Get range of available versions for each package using pip
    section_start_time = datetime.datetime.now()
    print(f"Generating package requirements for Python {python_version}...")
    requirements = []
    with open(f"/opt/build/packages/packages-python-{python_version}.list", "w") as f_list:
        for (package_name, package_suffix) in package_list:
            if package_suffix:
                requirements.append(f"{package_name}{package_suffix}")
            else:
                try:
                    versions = subprocess.run([f"{shims}/pip3", "index", "versions", package_name], env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.decode().split(":")[1].split(",")
                    versions = sorted([v for v in map(to_version, versions) if v])
                    requirements.append(f"{package_name}>={versions[0]},<={versions[-1]}")
                except IndexError:
                    requirements.append(f"{package_name}>=0.0")
            f_list.write(f"{package_name}\n")
    print(f"Generating requirements took {humanize.naturaldelta(datetime.datetime.now() - section_start_time)}")

    # Solve dependencies and install using poetry
    section_start_time = datetime.datetime.now()
    print("Installing packages with poetry...")
    # Remove config files
    with contextlib.suppress(FileNotFoundError):
        os.remove("poetry.lock")
        os.remove("pyproject.toml")
    # Generate a TOML file
    with open("/opt/build/python-pyproject-template.toml", "r") as f_template:
        pyproject_toml = [l.replace("PYTHON_ENV_NAME", f"Python {python_version}").replace("PYTHON_VERSION", str(python_version)) for l in f_template.readlines()]
    with open("pyproject.toml", "w") as f_toml:
        f_toml.writelines(pyproject_toml)
    # Add packages to poetry
    subprocess.run([f"{shims}/poetry", "config", "virtualenvs.create", "false"], env=env)
    subprocess.run([f"{shims}/poetry", "config", "virtualenvs.in-project", "true"], env=env)
    subprocess.run([f"{shims}/poetry", "add"] + requirements, env=env)
    # Write package versions to monitoring log
    with open(f"/opt/monitoring/python-{python_version}-package-versions.log", "w") as f_log:
        for line in subprocess.run([f"{shims}/poetry", "show"], env=env, stdout=subprocess.PIPE).stdout.decode().split("\n")[1:]:
            print(line)
            f_log.write(f"{line}\n")
        for line in subprocess.run([f"{shims}/poetry", "show", "--tree"], env=env, stdout=subprocess.PIPE).stdout.decode().split("\n")[1:]:
            f_log.write(f"{line}\n")
    print(f"Installation took {humanize.naturaldelta(datetime.datetime.now() - section_start_time)}")

    # Install any post-install package requirements
    section_start_time = datetime.datetime.now()
    print("Installing post-install package requirements")
    installed_packages = json.loads(subprocess.run([f"{shims}/pip3", "list", "--format=json"], env=env, stdout=subprocess.PIPE).stdout.decode())
    package_names = [p["name"] for p in installed_packages]
    if "spacy" in package_names:
        for dataset in ["en_core_web_sm", "en_core_web_md", "en_core_web_lg"]:
            if dataset not in installed_packages:
                subprocess.run([f"{shims}/python3", "-m", "spacy", "download", dataset], env=env)
    if "nltk" in package_names:
        subprocess.run([f"{shims}/python3", "-m", "nltk.downloader", "all", "-d", "/usr/share/nltk_data"], env=env)
    if "gensim" in package_names:
        env["GENSIM_DATA_DIR"] = "/usr/share/gensim_data"
        for dataset in ["text8", "fake-news"]:
            subprocess.run([f"{shims}/python3", "-m", "gensim.downloader", "--download", dataset], env=env)
    print(f"\nPost-install setup took {humanize.naturaldelta(datetime.datetime.now() - section_start_time)}")

    # Check that all requested packages are installed
    section_start_time = datetime.datetime.now()
    print("Sanity checking installed packages...")
    missing_packages = []
    for requested_package in [p[0] for p in package_list]:
        if requested_package not in installed_packages:
            missing_packages.append(requested_package)
    if missing_packages:
        print("FATAL: The following requested packages are missing:")
        for missing_package in missing_packages:
            print(missing_package)
        sys.exit(1)
    print(f"All requested Python {python_version} packages are installed")

    # Run safety check and log any problems
    print(f"Running safety check on Python {python_version} installation...")
    safety_output = f"/opt/monitoring/python-{python_version}-safety-check.json"
    subprocess.run([f"{shims}/safety", "check", "--json", "--output", safety_output], env=env)
    subprocess.run([f"{shims}/safety", "review", "--full-report", "-f", safety_output], env=env)
    print(f"Checking installed packages took {humanize.naturaldelta(datetime.datetime.now() - section_start_time)}")

    # Set the Jupyter kernel name to the full Python version name
    # This ensures that different python3 versions show up separately
    print("Set Jupyter kernel name")
    kernel_path = f"{pyenv_root}/versions/{python_version}/share/jupyter/kernels/python3/kernel.json"
    with open(kernel_path, "r") as f_kernel:
        kernel = json.load(f_kernel)
    kernel["argv"][0] = f"{pyenv_root}/versions/${python_version}/bin/python"
    kernel["display_name"] = f"Python {python_version}"
    with open(kernel_path, "w") as f_kernel:
        json.dump(kernel, f_kernel, indent=1)

    # Clean up
    for tmpobject in glob.glob("/root/*") + glob.glob("/root/.[a-zA-Z_]") + glob.glob("/tmp/*") + glob.glob("/tmp/.[a-zA-Z_]*"):
        with contextlib.suppress(FileNotFoundError):
            try:
                os.remove(tmpobject)
            except IsADirectoryError:
                os.removedirs(tmpobject)
    print(f"Finished installing {python_version} after {humanize.naturaldelta(datetime.datetime.now() - section_start_time)}")


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
        install_python_version(python_version, package_list)
