# Documentation

The documentation is built from Markdown files using [Sphinx](https://www.sphinx-doc.org/) and [MyST parser](https://myst-parser.readthedocs.io/).

## Building the Documentation

Create a virtual environment

```console
python3 -m venv ./venv
source ./venv/bin/activate
```

Install the python dependencies (specified in [`requirements.txt`](./requirements.txt))

```console
pip install -r requirements.txt
```

Use the [`Makefile`](./Makefile) to build the document site

```console
make html
```

The generated documents will be placed under `build/html/`.
To view the documents open `build/html/index.html` in your browser.
For example

```console
firefox build/html/index.html
```

## Reproducible Builds

To improve the reproducibly of build at each commit, [`requirements.txt`](./requirements.txt) contains a complete list of dependencies and specific versions.

The projects _direct_ dependencies are listed in [`requirements.in`](./requirements.in).
The full list is then generated using [`pip-compile`](https://pip-tools.readthedocs.io/en/latest/#requirements-from-requirements-in)

```console
pip-compile requirements.in
```

### Updating Requirements

All requirements can be updated with

```console
pip-compile --upgrade requirements.in
```

Your virtual environment can be updated with

```console
pip-sync
```
