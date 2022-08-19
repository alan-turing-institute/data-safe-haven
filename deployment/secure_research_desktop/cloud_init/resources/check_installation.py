#! /usr/bin/env python3
import os
import glob
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
        executable = test[0]
        if executable == "python":
            python_version = test[1]
            exists = run(f"ls /opt/pyenv/versions/{python_version}/bin/python")
            version = run(f"/opt/pyenv/versions/{python_version}/bin/python --version | cut -d ' ' -f 2")
            executable = f"Python {'.'.join(python_version.split('.')[:2])}"
        elif executable == "pip":
            python_version = test[1]
            exists = run(f"ls /opt/pyenv/versions/{python_version}/bin/pip")
            version = run(f"/opt/pyenv/versions/{python_version}/bin/pip -V | cut -d ' ' -f 2")
            executable = f"pip (Python {'.'.join(python_version.split('.')[:2])})"
        else:
            exists = run(f"which {executable}")
            version = run(test[1]) if exists else None
        if version:
            print(f"... {executable} [{exists}] {version}")
            success += 1
        else:
            print(f"... ERROR {executable} not found!")
            failure += 1
    return (success, failure)


# Run all tests
success, failure = 0, 0
python_versions = [("python", os.path.split(path)[1]) for path in glob.glob("/opt/pyenv/versions/*")]
pip_versions = [("pip", os.path.split(path)[1]) for path in glob.glob("/opt/pyenv/versions/*")]

print("Programming languages:")
(success, failure) = run_tests(
    success,
    failure,
    ("cmake", "cmake --version 2>&1 | head -n 1 | awk '{print $3}'"),
    ("g++", "g++ --version | grep g++ | awk '{print $NF}'"),
    ("gcc", "gcc --version | grep gcc | awk '{print $NF}'"),
    ("gfortran", "gfortran --version | grep Fortran | awk '{print $NF}'"),
    ("java", "java -version 2>&1 | grep 'openjdk version' | cut -d '\"' -f 2"),
    ("julia", "julia --version | awk '{print $NF}'"),
    *python_versions,
    ("R", "R --version | grep 'R version' | awk '{print $3}'"),
    ("rustc", "rustc --version 2>&1 | awk '{print $2}'"),
    ("scala", "scalac -version 2>&1 | awk '{print $4}'"),
    ("spark-shell", "spark-shell --version 2>&1 | grep version | grep -v Scala | awk '{print $NF}'"),
)

print("Package managers:")
(success, failure) = run_tests(
    success,
    failure,
    ("cargo", "cargo -V"),
    *pip_versions,
)

print("Editors/IDEs:")
(success, failure) = run_tests(
    success,
    failure,
    ("code", "code -v --user-data-dir /tmp 2>/dev/null | head -n 1"),
    ("emacs", "emacs --version | head -n 1 |  awk '{print $NF}'"),
    ("nano", "nano --version | head -n 1 |  awk '{print $NF}'"),
    ("pycharm-community", "snap list pycharm-community | tail -n 1 | awk '{print $2}'"),
    ("rstudio", "dpkg -s rstudio | grep '^Version:' | awk '{print $NF}'"),
    ("vim", "dpkg -s vim | grep '^Version:' | cut  -d ':' -f 3"),
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
    ("dbeaver-ce", "dpkg -s dbeaver-ce | grep '^Version:' | awk '{print $NF}'"),
    ("firefox", "firefox --version | awk '{print $NF}'"),
    ("git", "git --version | awk '{print $NF}'"),
    ("htop", "htop --version | head -n 1 | awk '{print $2}'"),
    ("nvidia-smi", "modinfo nvidia | grep '^version:' | awk '{print $NF}'"),
    ("psql", "psql --version | awk '{print $NF}' | sed 's/)//'"),
    ("sqlcmd", "sqlcmd -? | grep Version | awk '{print $2}'"),
    ("weka", "weka -c weka.core.Version 2> /dev/null | head -n 1"),
)

# Return appropriate code
print(f"{success + failure} test(s), {failure} failure(s)")
if failure > 0:
    sys.exit(os.EX_SOFTWARE)
sys.exit(os.EX_OK)
