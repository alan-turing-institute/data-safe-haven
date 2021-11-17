## {{computer}} Develop analyses via the Linux Data Science desktop

You can use the Linux Data Science desktop to carry out data science research on the data that has been made available to you.
You can work with any of the pre-installed applications and programming languages.

### Programming languages / compilers

```{include} software_languages.partial.md
:relative-images:
```

### Editors / IDEs

```{include} software_editors.partial.md
:relative-images:
```

### Writing / presentation tools

```{include} software_presentation.partial.md
:relative-images:
```

### Database access

```{include} software_database.partial.md
:relative-images:
```

### Other useful software

```{include} software_other.partial.md
:relative-images:
```

If you need anything that is not already installed, please discuss this with the designated contact for your SRE.

```{attention}
This desktop is your interface to a "virtual machine".
You may have access to [additional virtual machines](#access-additional-virtual-machines) so be careful to check which machine you are working in as files and installed packages may not be the same across the machines.
```

### {{musical_keyboard}} Keyboard mapping

When you access the Data Science desktop you are actually connecting through "the cloud" to another computer - via a few intermediate computers/servers that monitor and maintain the security of the SRE.

```{caution}
You may find that the keyboard mapping on your computer is not the same as the one in the SRE.
```

Click on `Desktop` and `Applications > Settings > Keyboard` to change the layout.

```{tip}
We recommend opening a text editor (such as `Atom` , see [Access applications](#access-applications) below) to check what keys the remote desktop thinks you're typing – especially if you need to use special characters.
```

### {{unlock}} Access applications

You can access applications from the desktop in two ways: the terminal or via a drop down menu.

Applications can be accessed from the dropdown menu.
For example:

- `Applications > Development > RStudio`
- `Applications > Development > Atom`

Applications can be accessed from a terminal.
For example:

- Open `Terminal` and run `jupyter notebook &` if you want to use python within a jupyter notebook.
- Open `Terminal` and run `spyder &` if you want to use python within the Spyder IDE (integrated development environment) which is quite similar to RStudio.

```{image} user_guide/access_desktop_applications.png
:alt: How to access applications from the desktop
:align: center
```

### {{snake}} Initiate the correct version of R or python

Typing `R` at the command line will give you the system version of `R` with many custom packages pre-installed.

There are several versions of `Python` installed, which are managed through [pyenv](https://github.com/pyenv/pyenv).
You can see the default version (indicated by a '\*') and all other installed versions using the following command:

```bash
> pyenv versions
```

This will give output like:

```
  system
  3.6.11
  3.7.8
* 3.8.3 (set by /home/ada.lovelace/.pyenv_version)
```

You can change your preferred Python version globally or on a folder-by-folder basis using

- `pyenv global <version number>` (to change the version globally)
- `pyenv local <version number>` (to change the version for the folder you are currently in)

### {{gift}} Install R and python packages

There are local copies of the `PyPI` and `CRAN` package repositories available within the SRE.
You can install packages you need from these copies in the usual way, for example `pip install` and `packages.install` for Python and R respectively.

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
Don't forget the `--user` flag as you do not have permission to install packages for all users.
```

#### Package availability

Depending on the type of data you are accessing, different `R` and `python` packages will be available to you (in addition to the ones that are pre-installed):

- {ref}`policy_tier_2` (medium security) environments have full mirrors of `PyPI` and `CRAN` available.
- {ref}`policy_tier_3` (high security) environments only have pre-authorised packages available.

If you need to use a package that is not on the allowlist see the section on how to [bring software or data into the environment](#bring-in-software-or-data-to-the-environment) below.
