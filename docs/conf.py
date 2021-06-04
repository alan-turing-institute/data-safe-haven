# Configuration file for the Sphinx documentation builder.
#
# This file only contains a selection of the most common options. For a full
# list see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Customisation  -----------------------------------------------------------
from git import Repo

repo = Repo(search_parent_directories=True)

# Find the version name which is a tag or branch name
tags = [t for t in repo.tags if t.commit == repo.head.commit]
# version = tags[0].name if tags else repo.head.reference.name.replace("master", "latest")
version = tags[0].name if tags else "latest"

# Set sidebar variables
try:
    html_context
except NameError:
    html_context = dict()
html_context["display_lower_left"] = True
html_context["version"] = version
html_context["current_version"] = version
html_context["versions"] = [(t.name, f"../{t.name}/index.html") for t in repo.tags]
# html_context['downloads'] = [("PDF", "/latest.pdf")]

print("html_context", html_context)

# -- Path setup --------------------------------------------------------------

# If extensions (or modules to document with autodoc) are in another directory,
# add these directories to sys.path here. If the directory is relative to the
# documentation root, use os.path.abspath to make it absolute, like shown here.
#
# import os
# import sys
# sys.path.insert(0, os.path.abspath('.'))

# -- Project information -----------------------------------------------------

project = "Data Safe Haven"
copyright = "2021, The Alan Turing Institute"
author = "The Alan Turing Institute"

# The full version, including alpha/beta/rc tags
release = version


# -- General configuration ---------------------------------------------------

# Add any Sphinx extension module names here, as strings. They can be
# extensions coming with Sphinx (named 'sphinx.ext.*') or your custom
# ones.
extensions = ["myst_parser"]

# Add any paths that contain templates here, relative to this directory.
templates_path = ["_templates"]

# List of patterns, relative to source directory, that match files and
# directories to ignore when looking for source files.
# This pattern also affects html_static_path and html_extra_path.
exclude_patterns = ["_build", "Thumbs.db", ".DS_Store"]


# -- Options for HTML output -------------------------------------------------

# The theme to use for HTML and HTML Help pages.  See the documentation for
# a list of builtin themes.
#
# html_theme = 'karma_sphinx_theme'
html_theme = "sphinx_rtd_theme"

# # Add any paths that contain custom static files (such as style sheets) here,
# # relative to this directory. They are copied after the builtin static files,
# # so a file named "default.css" will overwrite the builtin "default.css".
# html_static_path = ['_static']

# -- Options for MyST  --------------------------------------------------------

# MyST extensions to enable
myst_enable_extensions = [
    "colon_fence",
    "html_admonition",
]
