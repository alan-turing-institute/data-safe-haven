#! /usr/bin/env python3
import os
import subprocess
import sys
import yaml
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
    available_versions = (
        subprocess.run(
            ["pyenv", "install", "--list"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=os.environ.copy(),
            encoding="utf8",
        )
        .stdout.strip()
        .split("\n")
    )
    available_versions = [
        v for v in map(to_version, available_versions) if v and not v.is_prerelease
    ]

    # Find the most up-to-date Python version and write out a list of packages
    python_versions = []
    for base_version, package_list in read_yaml(sys.argv[1]):
        python_version = sorted(
            [v for v in available_versions if f"{v.major}.{v.minor}" == base_version]
        )[-1]
        python_versions.append(python_version)

        # Write list of package names
        file_path = f"/opt/build/packages/packages-python-{python_version}.list"
        with open(file_path, "w") as f_list:
            f_list.writelines(f"{pkg[0]}\n" for pkg in package_list)

        # Write requirements file
        file_path = f"/opt/build/python-{python_version}-requirements.txt"
        with open(file_path, "w") as f_requirements:
            for (name, constraint) in package_list:
                if constraint:
                    f_requirements.write(f"{name}{constraint}\n")
                else:
                    f_requirements.write(f"{name}\n")
