# Configuration file for the Sphinx documentation builder.
#
# This file only contains a selection of the most common options. For a full
# list see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html
import datetime
import emoji


# -- Project information -----------------------------------------------------

project = "Data Safe Haven"
copyright = f"CC-BY-4.0 {datetime.date.today().year}, The Alan Turing Institute"
author = "The Alan Turing Institute"
development_branch = "develop"


# -- Customisation  -----------------------------------------------------------

# Construct list of emoji substitutions
# This code reproduces the library functions
# - get_emoji_unicode_dict()
# - get_aliases_unicode_dict()
emoji_codes = set()
for emj, data in emoji.unicode_codes.EMOJI_DATA.items():
    # Only accept fully qualified or component emoji
    # See https://www.unicode.org/reports/tr51/#def_emoji_sequence
    if data["status"] <= emoji.unicode_codes.STATUS["fully_qualified"]:
        # Add the English language name (if any)
        if "en" in data:
            emoji_codes.add(data["en"])
        # Add each of the list of aliases (if any)
        if "alias" in data:
            for alias in data["alias"]:
                emoji_codes.add(alias)
# Strip leading and trailing colons and sort
emoji_codes = sorted(map(lambda s: s.strip(":"), emoji_codes))

# Set sidebar variables
if "html_context" not in globals():
    html_context = dict()

# Add 'Edit on GitHub' link
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
    "sphinx_togglebutton",
    "sphinxcontrib.typer",
]

# Add any paths that contain templates here, relative to this directory.
templates_path = ["_templates"]


# List of patterns, relative to source directory, that match files and
# directories to ignore when looking for source files.
# This pattern also affects html_static_path and html_extra_path.
exclude_patterns = ["**/*.partial.md"]
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
        "image_light": "_static/logo_turing_light.png",
        "image_dark": "_static/logo_turing_dark.png",
    },
    "secondary_sidebar_items": ["page-toc", "edit-this-page", "sourcelink"],
    "use_edit_page_button": True,
    "header_links_before_dropdown": 6
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

# Allow MyST to generate anchors for section titles
myst_heading_anchors = 4
