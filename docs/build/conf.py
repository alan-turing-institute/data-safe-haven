# Configuration file for the Sphinx documentation builder.
#
# This file only contains a selection of the most common options. For a full
# list see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html
import emoji
from git import Repo


# -- Project information -----------------------------------------------------

project = "Data Safe Haven"
copyright = "2021, The Alan Turing Institute"
author = "The Alan Turing Institute"
development_branch = "develop"

# -- Customisation  -----------------------------------------------------------

def tag2version(tag):
    return tag.name

# Find name of current version plus names of all tags
repo = Repo(search_parent_directories=True)
repo_name = repo.remotes.origin.url.split(".git")[0].split("/")[-1]
tags = [t for t in repo.tags if t.commit == repo.head.commit]
versions = [development_branch] + [tag2version(t) for t in repo.tags]

# The most recently released version, including alpha/beta/rc tags
release = tag2version(tags[0]) if tags else development_branch

# Construct list of emoji substitutions
emoji_codes = set(
    [
        emoji_code.replace(":", "")
        for emoji_list in (
            emoji.EMOJI_UNICODE_ENGLISH.keys(),
            emoji.EMOJI_ALIAS_UNICODE_ENGLISH.keys(),
        )
        for emoji_code in emoji_list
    ]
)

# Set sidebar variables
if not "html_context" in globals():
    html_context = dict()
html_context["display_lower_left"] = True
html_context["version"] = release
html_context["current_version"] = release
html_context["versions"] = [(v, f"/{repo_name}/{v}/index.html") for v in versions]
# Downloadable PDFs
html_context["downloads"] = [
    (
        "User guide (Apache Guacamole)",
        f"/{repo_name}/{development_branch}/pdf/data_safe_haven_user_guide_guacamole.pdf",
    ),
    (
        "User guide (Microsoft RDS)",
        f"/{repo_name}/{development_branch}/pdf/data_safe_haven_user_guide_msrds.pdf",
    ),
    (
        "Classification flowchart",
        f"/{repo_name}/{development_branch}/pdf/data_classification_flow_full.pdf",
    ),
    (
        "Simplified classification  flowchart",
        f"/{repo_name}/{development_branch}/pdf/data_classification_flow_simple.pdf",
    ),
]
# Add 'Edit on GitHub' link
html_context["display_github"] = True
html_context["github_user"] = "alan-turing-institute"
html_context["github_repo"] = "data-safe-haven"
html_context["github_version"] = f"{development_branch}/docs/"

# -- Project information -----------------------------------------------------

project = "Data Safe Haven"
copyright = "2021, The Alan Turing Institute"
author = "The Alan Turing Institute"



# -- General configuration ---------------------------------------------------

# Add any Sphinx extension module names here, as strings. They can be
# extensions coming with Sphinx (named 'sphinx.ext.*') or your custom
# ones.
extensions = [
    "myst_parser",
    "rinoh.frontend.sphinx",
]

# Add any paths that contain templates here, relative to this directory.
templates_path = ["_templates"]

# List of patterns, relative to source directory, that match files and
# directories to ignore when looking for source files.
# This pattern also affects html_static_path and html_extra_path.
exclude_patterns = [
    "build",
    "_output",
    "Thumbs.db",
    ".DS_Store",
    "**/*.partial.md",
]

# -- Options for HTML output -------------------------------------------------

# The theme to use for HTML and HTML Help pages.  See the documentation for
# a list of builtin themes.
html_theme = "pydata_sphinx_theme"

# Options for the chosen theme
html_theme_options = {
    "logo_link": "index",
    "github_url": f"https://github.com/{html_context['github_user']}/{html_context['github_repo']}",
}

# Location of logo
html_logo = "_static/logo_turing.jpg"

# Add any paths that contain custom static files (such as style sheets) here,
# relative to this directory. They are copied after the builtin static files,
# so a file named "default.css" will overwrite the builtin "default.css".
html_static_path = ["_static"]
html_css_files = ["overrides.css"]
html_js_files = ["toggle.js"]


# -- Options for MyST  --------------------------------------------------------

# MyST extensions to enable
myst_enable_extensions = [
    "colon_fence",
    "deflist",
    "html_admonition",
    "substitution",
]

# Emoji substitutions: replace {{emoji_name}} => unicode
myst_substitutions = {
    emoji_code: emoji.emojize(f":{emoji_code}:", use_aliases=True)
    for emoji_code in emoji_codes
}

# -- Options for Rinoh  -------------------------------------------------------

# List of documents to convert to PDF
rinoh_documents = [
    dict(
        doc="roles/researcher/user_guide_guacamole",
        target="pdf/data_safe_haven_user_guide_guacamole",
        title="Data Safe Haven User Guide",
        subtitle="Apache Guacamole",
        author=author,
        template="emoji_support.rtt",
    ),
    dict(
        doc="roles/researcher/user_guide_msrds",
        target="pdf/data_safe_haven_user_guide_msrds",
        title="Data Safe Haven User Guide",
        subtitle="Microsoft RDS",
        author=author,
        template="emoji_support.rtt",
    ),
]
