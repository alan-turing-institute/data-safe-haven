# Documentation

The documentation is built from Markdown files using [Sphinx](https://www.sphinx-doc.org/) and [MyST parser](https://myst-parser.readthedocs.io/).

## Requirements

Install the following requirements before starting

- [Hatch](https://hatch.pypa.io/1.9/install/)

## Building the Documentation

Build the documentation with `hatch`.

```console
> hatch run docs:build
```

The generated documents will be placed under `build/html/`.
To view the documents open `build/html/index.html` in your browser.
For example

```console
> firefox build/html/index.html
```

## Reproducible Builds

We use [`pip-compile`](https://pip-tools.readthedocs.io/en/latest/) behind the scenes to ensure that each commit uses the same set of packages to build the documentation.
This means that each build is fully reproducible.
