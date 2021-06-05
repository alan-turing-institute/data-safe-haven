# Configuration file for the Sphinx documentation builder.
#
# This file only contains a selection of the most common options. For a full
# list see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html
from git import Repo


def tag2version(tag):
    return tag.name.replace("v", "")


# -- Customisation  -----------------------------------------------------------

# Find name of current version plus names of all tags
repo = Repo(search_parent_directories=True)
repo_name = repo.remotes.origin.url.split(".git")[0].split("/")[-1]
tags = [t for t in repo.tags if t.commit == repo.head.commit]
version = tag2version(tags[0]) if tags else "latest"
versions = ["latest"] + [tag2version(t) for t in repo.tags]

# Set sidebar variables
try:
    html_context
except NameError:
    html_context = dict()
html_context["display_lower_left"] = True
html_context["version"] = version
html_context["current_version"] = version
html_context["versions"] = [(v, f"/{repo_name}/{v}/index.html") for v in versions]
html_context["downloads"] = [
    ("User guide PDF", f"/{repo_name}/{version}/pdf/safe_haven_user_guide.pdf"),
    (
        "Software request form",
        f"/{repo_name}/{version}/pdf/safe_haven_software_request_form.pdf",
    ),
    (
        "Data classification full PDF",
        f"/{repo_name}/{version}/pdf/data_classification_flow_full.pdf",
    ),
    (
        "Data classification simplified PDF",
        f"/{repo_name}/{version}/pdf/data_classification_flow_simple.pdf",
    ),
]
# Add 'Edit on GitHub' link
html_context["display_github"] = True
html_context["github_user"] = "alan-turing-institute"
html_context["github_repo"] = "data-safe-haven"
html_context["github_version"] = "master/docs/"

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
html_theme = "sphinx_rtd_theme"

# Add any paths that contain custom static files (such as style sheets) here,
# relative to this directory. They are copied after the builtin static files,
# so a file named "default.css" will overwrite the builtin "default.css".
html_static_path = ["_static"]
html_css_files = ["overrides.css"]


# -- Options for MyST  --------------------------------------------------------

# MyST extensions to enable
myst_enable_extensions = [
    "colon_fence",
    "html_admonition",
]
