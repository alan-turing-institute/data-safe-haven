# Configuration file for the Sphinx documentation builder.
#
# This file only contains a selection of the most common options. For a full
# list see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html
import emoji
import importlib.util
import os

# Reliably import local module, no matter how python script is called
spec=importlib.util.spec_from_file_location("repo_info",
    os.path.join(os.path.dirname(os.path.realpath(__file__)),"repo_info.py"))
repo_info = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repo_info)

# -- Project information -----------------------------------------------------

project = "Data Safe Haven"
copyright = "2021, The Alan Turing Institute"
author = "The Alan Turing Institute"

# -- Customisation  -----------------------------------------------------------

print(f"Supported versions: {repo_info.supported_versions}")
print(f"Default version: {repo_info.default_version}")

env_build_git_version = os.getenv("BUILD_GIT_VERSION")


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
if "html_context" not in globals():
    html_context = dict()
html_context["display_lower_left"] = True
html_context["default_version"] = repo_info.default_version
html_context["current_version"] = env_build_git_version
html_context["versions"] = [(v, f"../{v}/index.html") for v in repo_info.supported_versions]
# Downloadable PDFs
html_context["downloads"] = [
    (
        "User guide (Apache Guacamole)",
        f"../{repo_info.development_branch}/pdf/data_safe_haven_user_guide_guacamole.pdf",
    ),
    (
        "User guide (Microsoft RDS)",
        f"../{repo_info.development_branch}/pdf/data_safe_haven_user_guide_msrds.pdf",
    ),
    (
        "Classification flowchart",
        f"../{repo_info.development_branch}/pdf/data_classification_flow_full.pdf",
    ),
    (
        "Simplified classification  flowchart",
        f"../{repo_info.development_branch}/pdf/data_classification_flow_simple.pdf",
    ),
]
# Add 'Edit on GitHub' link
html_context["display_github"] = True
html_context["github_user"] = "alan-turing-institute"
html_context["github_repo"] = "data-safe-haven"
html_context["github_version"] = repo_info.development_branch
html_context["doc_path"] = "docs"


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
    "use_edit_page_button": True,
    "logo_link": "index",
    "github_url": f"https://github.com/{html_context['github_user']}/{html_context['github_repo']}",
}

# Location of logo and favicon
html_logo = "_static/logo_turing.jpg"
html_favicon = "_static/favicon.ico"

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
