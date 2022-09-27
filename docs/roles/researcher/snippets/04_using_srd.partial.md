## {{computer}} Analysing sensitive data

The SRD has several pre-installed applications and programming languages to help with your data analysis.

### {{package}} Pre-installed applications

#### Programming languages / compilers

```{include} snippets/software_languages.partial.md
:relative-images:
```

#### Editors / IDEs

```{include} snippets/software_editors.partial.md
:relative-images:
```

#### Writing / presentation tools

```{include} snippets/software_presentation.partial.md
:relative-images:
```

#### Database access tools

```{include} snippets/software_database.partial.md
:relative-images:
```

#### Other useful software

```{include} snippets/software_other.partial.md
:relative-images:
```

If you need anything that is not already installed, please discuss this with the designated contact for your SRE.

```{attention}
This secure research desktop SRD is your interface to a single computer running in the cloud.
You may have access to [additional SRDs](#access-additional-srds) so be careful to check which machine you are working in as files and installed packages may not be the same across the machines.
```

### {{musical_keyboard}} Keyboard mapping

When you access the SRD you are actually connecting through the cloud to another computer - via a few intermediate computers/servers that monitor and maintain the security of the SRE.

```{caution}
You may find that the keyboard mapping on your computer is not the same as the one set for the SRD.
```

Click on `Desktop` and `Applications > Settings > Keyboard` to change the layout.

```{tip}
We recommend opening a text editor (such as `Atom` , see [Access applications](#access-applications) below) to check what keys the remote desktop thinks you're typing – especially if you need to use special characters.
```

### {{unlock}} Access applications

You can access applications from the desktop in two ways: the terminal or via a drop down menu.

Applications can be accessed from the dropdown menu.
For example:

- `Applications > Development > Atom`
- `Applications > Development > Jupyter Notebook`
- `Applications > Development > PyCharm`
- `Applications > Development > RStudio`
- `Applications > Education > QGIS Desktop`

Applications can be accessed from a terminal.
For example:

- Open `Terminal` and run `jupyter notebook &` if you want to use `Python` within a jupyter notebook.

```{image} user_guide/access_desktop_applications.png
:alt: How to access applications from the desktop
:align: center
```

### {{snake}} Available Python and R versions

Typing `R` at the command line will give you the system version of `R` with many custom packages pre-installed.

There are several versions of `Python` installed, which are managed through [pyenv](https://github.com/pyenv/pyenv).
You can see the default version (indicated by a '\*') and all other installed versions using the following command:

```none
> pyenv versions
```

This will give output like:

```none
  system
  3.8.12
* 3.9.10 (set by /home/ada.lovelace/.pyenv_version)
  3.10.2
```

You can change your preferred Python version globally or on a folder-by-folder basis using

- `pyenv global <version number>` (to change the version globally)
- `pyenv local <version number>` (to change the version for the folder you are currently in)

#### Creating virtual environments

We recommend that you use a dedicated [virtual environment](https://docs.python.org/3/tutorial/venv.html) for developing your code in `Python`.
You can easily create a new virtual environment based on any of the available `Python` versions

```none
> pyenv virtualenv 3.8.12 myvirtualenv
```

You can then activate it with:

```none
> pyenv shell myvirtualenv
```

or if you want to automatically switch to it whenever you are in the current directory

```none
> pyenv local myvirtualenv
```

### {{gift}} Install R and python packages

There are local copies of the `PyPI` and `CRAN` package repositories available within the SRE.
You can install packages you need from these copies in the usual way, for example `pip install` and `install.packages` for Python and R respectively.

```{caution}
You **will not** have access to install packages system-wide and will therefore need to install packages in a user directory.
```

- For `CRAN` you will be prompted to make a user package directory when you [install your first package](#r-packages).
- For `PyPI` you will need to [install using the `--user` argument to `pip`](#python-packages).

#### R packages

You can install `R` packages from inside `R` (or `RStudio`):

```R
> install.packages(<package-name>)
```

You will see something like the following:

```R
Installing package into '/usr/local/lib/R/site-library'
(as 'lib' is unspecified)
Warning in install.packages("cluster") :
  'lib = "/usr/local/lib/R/site-library"' is not writable
Would you like to use a personal library instead? (yes/No/cancel)
```

Enter `yes`, which prompts you to confirm the name of the library:

```R
Would you like to create a personal library
'~/R/x86_64-pc-linux-gnu-library/3.5'
to install packages into? (yes/No/cancel)
```

Enter `yes`, to install the packages.

#### Python packages

You can install `python` packages from a terminal.

```bash
pip install --user <package-name>
```

```{tip}
If you are using a virtual environment as recommended above, you will not need the `--user` flag.
```

#### Package availability

Depending on the type of data you are accessing, different `R` and `python` packages will be available to you (in addition to the ones that are pre-installed):

- {ref}`Tier 2 <policy_tier_2>` (medium security) environments have full mirrors of `PyPI` and `CRAN` available.
- {ref}`Tier 3 <policy_tier_3>` (high security) environments only have pre-authorised packages available.

If you need to use a package that is not on the allowlist see the section on how to [bring software or data into the environment](#bring-in-new-files-to-the-sre) below.
