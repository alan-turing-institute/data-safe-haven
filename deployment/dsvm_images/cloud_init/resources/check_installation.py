#! /usr/bin/env python3
import os
import subprocess
import sys


def run(command):
    return subprocess.run(
        command,
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        encoding="utf8",
    ).stdout.strip()


def run_tests(success, failure, *tests):
    for test in tests:
        if "python" in test[0]:
            python_version = test[0].split(" ")[-1]
            exists = run(f"ls /opt/pyenv/versions/{python_version}*/bin/python")
            version = run(f"/opt/pyenv/versions/{python_version}*/bin/python --version")
        else:
            exists = run(f"which {test[0]}")
            version = run(test[1]) if exists else None
        if version:
            print(f"... {test[0]} [{exists}] {version}")
            success += 1
        else:
            print(f"... ERROR {test[0]} not found!")
            failure += 1
    return (success, failure)


# Run all tests
print("Programming languages:")
(success, failure) = run_tests(
    0,
    0,
    ("dotnet", "dotnet --version"),
    ("g++", "g++ --version | grep g++ | awk '{print $NF}'"),
    ("gcc", "gcc --version | grep gcc | awk '{print $NF}'"),
    ("gfortran", "gfortran --version | grep Fortran | awk '{print $NF}'"),
    ("java", "java -version 2>&1 | grep 'openjdk version' | cut -d '\"' -f 2"),
    ("julia", "julia --version | awk '{print $NF}'"),
    ("python 3.6", None),
    ("python 3.7", None),
    ("python 3.8", None),
    ("R", "R --version | grep 'R version' | awk '{print $3}'"),
    ("scala", "scalac -version 2>&1 | awk '{print $4}'"),
    ("spark-shell", "spark-shell --version 2>&1 | grep version | grep -v Scala | awk '{print $NF}'"),
)

print("Editors/IDEs:")
(success, failure) = run_tests(
    success,
    failure,
    ("atom", "dpkg -s atom | grep '^Version:' | awk '{print $NF}'"),
    ("code", "dpkg -s code | grep '^Version:' | awk '{print $NF}'"),
    ("emacs", "emacs --version | head -n 1 |  awk '{print $NF}'"),
    ("nano", "nano --version | head -n 1 |  awk '{print $NF}'"),
    ("pycharm-community", "snap list pycharm-community | tail -n 1 | awk '{print $2}'"),
    ("rstudio", "dpkg -s rstudio | grep '^Version:' | awk '{print $NF}'"),
    ("vim", "vim --version | tr ' ' '\n' | grep fdebug-prefix-map | rev | cut -d '/' -f1 | cut -d '-' -f1 | cut -d '=' -f2 | rev"),
)

print("Presentation tools:")
(success, failure) = run_tests(
    success,
    failure,
    ("latex", "latex --version | grep 'TeX Live' | awk '{print $2}'"),
    ("libreoffice", "libreoffice --version | head -n 1 | awk '{print $2}'"),
    ("xelatex", "xelatex --version | grep 'TeX Live' | awk '{print $2}'"),
)

print("Development tools:")
(success, failure) = run_tests(
    success,
    failure,
    ("azuredatastudio", "dpkg -s azuredatastudio | grep '^Version:' | awk '{print $NF}'"),
    ("bash", "bash --version | head -n 1 | awk '{print $4}'"),
    ("dbeaver", "dpkg -s dbeaver-ce | grep '^Version:' | awk '{print $NF}'"),
    ("docker", "docker --version | awk '{print $3}'"),
    ("firefox", "firefox --version | awk '{print $NF}'"),
    ("git", "git --version | awk '{print $NF}'"),
    ("htop", "htop --version | head -n 1 | awk '{print $2}'"),
    ("nvidia-smi", "modinfo nvidia | grep '^version:' | awk '{print $NF}'"),
    ("psql", "psql --version | awk '{print $NF}' | sed 's/)//'"),
    ("sqlcmd", "sqlcmd -? | grep Version | awk '{print $2}'"),
    ("weka", "weka -c weka.core.Version 2> /dev/null | head -n 1"),
)

# Return appropriate code
print(f"{success + failure} tests, {failure} failures")
if failure > 0:
    sys.exit(os.EX_SOFTWARE)
sys.exit(os.EX_OK)
