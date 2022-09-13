# Configuration file for the Sphinx documentation builder.
#
# This file only contains a selection of the most common options. For a full
# list see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html
import emoji
import git


# -- Project information -----------------------------------------------------

project = "Data Safe Haven"
copyright = "CC-BY-4.0 2022, The Alan Turing Institute."
author = "The Alan Turing Institute"
development_branch = "develop"
earliest_supported_release = "v3.4.0"


# -- Git repository details
repo = git.Repo(search_parent_directories=True)
repo_name = repo.remotes.origin.url.split(".git")[0].split("/")[-1]
releases = sorted((t.name for t in repo.tags), reverse=True)
supported_versions = (
    releases[: releases.index(earliest_supported_release) + 1]
    + [development_branch]
)
default_version = supported_versions[0]  # Latest stable release
current_version = (
    [tag.name for tag in repo.tags if tag.commit == repo.head.commit]
    + [branch.name for branch in repo.branches if branch.commit == repo.head.commit]
    + [repo.head.commit]
)[0]  # Tag or branch name or commit ID if no name is available


# -- Customisation  -----------------------------------------------------------

print(f"Supported versions: {supported_versions}")
print(f"Default version: {default_version}")
print(f"Current version: {current_version}")

# Construct list of emoji substitutions
emoji_codes = set(
    [
        emoji_code.replace(":", "")
        for emoji_list in (
            emoji.unicode_codes.get_emoji_unicode_dict("en").keys(),
            emoji.unicode_codes.get_aliases_unicode_dict().keys(),
        )
        for emoji_code in emoji_list
    ]
)

# Set sidebar variables
if "html_context" not in globals():
    html_context = dict()
html_context["display_lower_left"] = True
html_context["default_version"] = default_version
html_context["current_version"] = current_version
html_context["versions"] = [
    (v, f"/{repo_name}/{v}/index.html") for v in supported_versions
]
# Downloadable PDFs
pdf_commit_hash = repo.git.log("-1", "--format=format:%h", current_version)
pdf_commit_date = repo.git.log(
    "-1", "--format=format:%cd", "--date=format:%d %b %Y", current_version
)
pdf_version_string = f"Version: {current_version} ({pdf_commit_hash})"
print(f"PDF version string: {pdf_version_string}")

html_context["downloads"] = [
    (
        "User guide (Apache Guacamole)",
        f"/{repo_name}/{current_version}/pdf/data_safe_haven_user_guide_guacamole.pdf",
    ),
    (
        "User guide (Microsoft RDS)",
        f"/{repo_name}/{current_version}/pdf/data_safe_haven_user_guide_msrds.pdf",
    ),
    (
        "Classification flowchart",
        f"/{repo_name}/{current_version}/pdf/data_classification_flow_full.pdf",
    ),
    (
        "Simplified classification  flowchart",
        f"/{repo_name}/{current_version}/pdf/data_classification_flow_simple.pdf",
    ),
]
# Add 'Edit on GitHub' link
# html_context["display_github"] = True
html_context["github_user"] = "alan-turing-institute"
html_context["github_repo"] = "data-safe-haven"
html_context["github_version"] = development_branch
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
    "icon_links": [
        {
            "name": "GitHub",
            "url": f"https://github.com/{html_context['github_user']}/{html_context['github_repo']}",
            "icon": "fab fa-github-square",
            "type": "fontawesome",
        }
    ],
    "logo": {
        "image_light": "logo_turing_light.png",
        "image_dark": "logo_turing_dark.png",
    },
    "page_sidebar_items": ["edit-this-page", "sourcelink"],
    "use_edit_page_button": True,
}

# Set the left-hand sidebars
html_sidebars = {
    "**": [
        "search-field.html",
        "sidebar-section-navigation.html",
        "sidebar-versions.html",
    ]
}

# Location of favicon
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
    emoji_code: emoji.emojize(f":{emoji_code}:", language="alias")
    for emoji_code in emoji_codes
}

# -- Options for Rinoh  -------------------------------------------------------

# List of documents to convert to PDF
rinoh_documents = [
    dict(
        doc="roles/researcher/user_guide_guacamole",
        target="pdf/data_safe_haven_user_guide_guacamole",
        title="Data Safe Haven User Guide\nApache Guacamole",
        subtitle=pdf_version_string,
        date=pdf_commit_date,
        author=author,
        template="emoji_support.rtt",
    ),
    dict(
        doc="roles/researcher/user_guide_msrds",
        target="pdf/data_safe_haven_user_guide_msrds",
        title="Data Safe Haven User Guide\nMicrosoft Remote Desktop",
        subtitle=pdf_version_string,
        date=pdf_commit_date,
        author=author,
        template="emoji_support.rtt",
    ),
]
