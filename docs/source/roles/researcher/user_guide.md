(role_researcher_user_guide)=

# User Guide

## {{beginner}} Introduction

{{tada}} Welcome to the Turing Data Safe Haven! {{tada}}

Trusted research environments (TREs) for analysis of sensitive datasets are essential to give data providers confidence that their datasets will be kept secure over the course of a project.
The Data Safe Haven is a TRE that is designed to be as user-friendly as possible while still keeping the data safe.

The more sensitive the data you are working with, the higher the level of security within the TRE.
This will affect things like:

- whether you have internet access from inside the TRE
- whether you're allowed to copy and paste between your computer and the TRE
- which software tools and libraries you are able to install

:::{important}
Please read this user guide carefully and remember to refer back to it when you have questions.
In many cases the answer is already here, but if you think this resource could be clearer, please let us know so we can improve the documentation for future users.
:::

### Definitions

The following definitions might be useful during the rest of this guide

Data Safe Haven
: the overall TRE which supports multiple projects

Secure Research Environment (SRE)
: the environment set up for your project that you will use to access the sensitive data.

(user_guide_username_domain)=
Username domain
: the domain (for example **projects.example.org**) which your user account will belong to. Multiple projects can share the same domain.

(user_guide_sre_id)=
SRE ID
: each SRE has a unique short ID, for example **sandbox** which your {ref}`System Manager <role_system_manager>` will use to distinguish different SREs in the same Data Safe Haven.

(user_guide_sre_url)=
SRE URL
: each SRE has a unique URL (for example **sandbox.projects.example.org**) which is used to access the data.

(roles_researcher_user_guide_setup_mfa)=

## {{rocket}} Set up your account

This section of the user guide will help you set up your new account on the SRE you'll be using.

### {{seedling}} Prerequisites

Make sure you have all of the following when connecting to the SRE.

- {{computer}} Your computer.
- {{wrench}} Your [username](#username) and the {ref}`username domain <user_guide_username_domain>` for your SRE.
- {{european_castle}} The {ref}`URL <user_guide_sre_url>` for your SRE.
- {{satellite}} [Access](#network-access) to a specific wired or wireless network (if this is required for your project).
- {{iphone}} Your [phone](#your-phone-for-multi-factor-authentication), with good signal connectivity.

:::{important}
You should have received an email from your {ref}`System Manager <role_system_manager>` with your account details, the URL for your SRE, and any necessary network or [training requirements](#data-security-training-requirements) for your project.
:::

You should also know who the **designated contact** for your SRE is.
This might be an administrator or one of the people working on the project with you.
They will be your primary point of contact if you have any issues in connecting to or using the SRE.

#### Username

Your username comes in both a **short-form** and a **long-form**

- **short-form**: usually be in the format **_GIVEN\_NAME.LAST\_NAME_**
- **long-form**: **_USERNAME@USERNAME\_DOMAIN_**

:::{caution}
If you have a hyphenated last name, or multiple surnames, or a long family name, your short-form username may differ from this pattern.
Please check with the designated contact for your SRE if you are unsure about your username.
:::

:::{note}
In this document we will use **Ada Lovelace** as our example user.
Her username is:

- short-form: **ada.lovelace**
- long-form: **ada.lovelace@projects.example.org**

:::

#### Network access

The SRE that you're using may be configured to allow access only from a specific set of IP addresses.
This may involve being connected to a specific wired or wireless network or using a VPN.
You also may be required to connect from a specific, secure location.
If your SRE has any network requirements, you will be told what these are.

:::{tip}
Make sure you know the networks from which you must connect to your SRE.
This information will be available in the email you received with your connection information.
:::

#### Data security training requirements

Depending on your project, you may be required to undertake data security awareness training.

:::{tip}
Check with your designated contact to see whether this is the case for you.
:::

#### Your phone for multi-factor authentication

Multi-factor authentication (MFA) is one of the most powerful ways of verifying user identity online.
We therefore use MFA to protect the project data - specifically, we will use your phone number.

:::{important}
Make sure to have your phone with you and that you have good signal connectivity when you are connecting to the SRE.
:::

:::{caution}
You may encounter some connectivity challenges if your phone network has poor connectivity.
The SRE is not set up to allow you to authenticate through other methods.
:::

#### Domain names

You should be given the {ref}`username domain <user_guide_username_domain>` in the initial email from your {ref}`System Manager <role_system_manager>`.
You might receive the {ref}`SRE URL <user_guide_sre_url>` at this time, or you might be assigned to a particular SRE at a later point.

:::{note}
In this document Ada Lovelace - our example user - will be participating in the **sandbox** project.
- Her **{ref}`username domain <user_guide_username_domain>`** is **projects.example.org**.
- Her **{ref}`SRE URL <user_guide_sre_url>`** is **https://sandbox.projects.example.org**.
:::

(user_setup_password_mfa)=

## {{closed_lock_with_key}} Password and MFA

For security reasons, you must reset your password before you log in for the first time.
Please follow these steps carefully.

::::{admonition} 1. Start the password reset process
:class: dropdown note

Go to `https://aka.ms/mfasetup` in a **private/incognito** browser session on your computer.

:::{tip}
One of the most common problems that users have in connecting to the SRE is automatic completion of usernames and passwords from other accounts on their computer.
This can be quite confusing, particularly for anyone who logs into Microsoft services for work or personal use.
:::

:::{caution}
Look out for usernames or passwords that are automatically completed, and make sure that you're using the correct details needed to access the SRE.
:::
::::

::::{admonition} 2. Follow the password recovery steps
:class: dropdown note

- At the login prompt enter your **[long-form username](#username)** and click on the **{guilabel}`Next`** button

    :::{note}
    Our example user, Ada Lovelace, participating in the **sandbox** project, would enter **ada.lovelace@projects.example.org**
    :::

- At the password prompt click the **Forgotten my password** link.

    :::{image} user_guide/account_setup_forgotten_password.png
    :alt: Forgotten my password
    :align: center
    :width: 90%
    :::
::::

::::{admonition} 3. Fill out the CAPTCHA
:class: dropdown note

- Fill out the requested CAPTCHA (your username should be pre-filled) then click on the **{guilabel}`Next`** button.

    :::{image} user_guide/account_setup_captcha.png
    :alt: Password CAPTCHA
    :align: center
    :width: 90%
    :::
::::

::::{admonition} 4. Confirm your contact details
:class: dropdown note

- Confirm your phone number or email address, which you provided to the {ref}`System Manager <role_system_manager>` when you registered for access to the environment.

    :::{image} user_guide/account_setup_verify_phone.png
    :alt: Verify phone number
    :align: center
    :width: 90%
    :::
::::

::::{admonition} 5. Set your password
:class: dropdown note

- Select a password that complies with the [Microsoft Entra requirements](https://learn.microsoft.com/en-us/entra/identity/authentication/concept-sspr-policy#microsoft-entra-password-policies):


    :::{tip}
    We suggest the following:

    - minimum 12 characters
    - only alphanumeric characters
    - at least one each of:
      - {{input_latin_uppercase}} uppercase character
      - {{input_latin_lowercase}} lowercase character
      - {{input_numbers}} number
    - not used anywhere else
    - use a [password generator](https://bitwarden.com/password-generator/) to ensure you meet these requirements
    :::

    :::{caution}
    We recommend avoiding special characters or symbols in your password!
    The virtual keyboard inside the SRE may not be the same as your physical keyboard and this can make it difficult to type some symbols.
    :::

- Enter your password into the **Enter new password** and **Confirm new password** fields.

    :::{image} user_guide/account_setup_new_password.png
    :alt: New password
    :align: center
    :width: 90%
  :::

- Click on the **{guilabel}`Finish`** button and you should get this notice

    :::{image} user_guide/account_setup_new_password_sign_in.png
    :alt: Click to continue
    :align: center
    :width: 90%
    :::

- Click on this link and provide your username and password when prompted.
- At this point you will be asked for additional security verification.

    :::{image} user_guide/account_setup_more_information_required.png
    :alt: Click to continue
    :align: center
    :width: 90%
    :::
::::

### {{door}} Set up multi-factor authentication

The next step in setting up your account is to authenticate your account from your phone.
This additional security verification is to make it harder for people to impersonate you and connect to the environment without permission.
This is known as multi-factor authentication (MFA).

#### {{telephone_receiver}} Phone number registration

::::{admonition} 1. Enter your phone number
:class: dropdown note

- In order to set up MFA you will need to enter your phone number

    :::{image} user_guide/account_setup_mfa_additional_security_verification.png
    :alt: Additional security verification
    :align: center
    :width: 90%
    :::
::::

::::{admonition} 2. Answer a phone call
:class: dropdown note

- Once you click **{guilabel}`Next`** you will receive a phone call straight away.

    :::{image} user_guide/account_setup_mfa_verifying_phone.png
    :alt: Verifying phone number
    :align: center
    :width: 90%
    :::

    :::{tip}
    The call might say _press the pound key_ or _press the hash key_. Both mean hit the `#` button.
    :::
::::

::::{admonition} 3. Register phone number
:class: dropdown note

- After following the instructions you will see the following screen

    :::{image} user_guide/account_setup_mfa_verified_phone.png
    :alt: Verified phone number
    :align: center
    :width: 90%
    :::

- Click **{guilabel}`Next`** to register this phone number for MFA

    :::{image} user_guide/account_setup_mfa_registered_phone.png
    :alt: Registered phone number
    :align: center
    :width: 90%
    :::

- Click **{guilabel}`Done`**
::::

::::{admonition} 4. Check the Security Information dashboard
:class: dropdown note

- You should now see the Security Information dashboard that lists all your verified MFA methods

    :::{image} user_guide/account_setup_mfa_dashboard_phone_only.png
    :alt: Registered phone number
    :align: center
    :width: 90%
    :::

- Choose whichever you prefer to be your **Default sign-in method**.

::::

#### {{iphone}} Authenticator app registration

::::{admonition} 1. Download the Microsoft Authenticator app
:class: dropdown note

Search for **Microsoft Authenticator** in your phone's app store or follow the appropriate link for your phone here:

- {{apple}} iOS: `https://bit.ly/iosauthenticator`
- {{robot}} Android: `https://bit.ly/androidauthenticator`
- {{bento_box}} Windows mobile: `https://bit.ly/windowsauthenticator`
::::


::::{admonition} 2. Open authenticator app
:class: dropdown note

- Click on **{guilabel}`+ Add sign-in method`** and select **Authenticator app**.

    :::{image} user_guide/account_setup_mfa_add_authenticator_app.png
    :alt: Add Authenticator app
    :align: center
    :width: 90%
    :::

- At the **Getting the app** click on **{guilabel}`Next`**.

    :::{image} user_guide/account_setup_mfa_download_authenticator_app.png
    :alt: Add Authenticator app
    :align: center
    :::

- Open the app
::::

::::{admonition} 3. Register your app
:class: dropdown note

- From the app
    - Select **Add an account**
    - Select **Work or School account**

    :::{image} user_guide/account_setup_mfa_allow_notifications.png
    :alt: Allow Authenticator notifications
    :align: center
    :::

    :::{important}
    You must give permission for the authenticator app to send you notifications for the app to work as an MFA method.
    :::

- The next prompt will give you a QR code to scan, like the one shown below
- Scan the QR code on the screen then click **{guilabel}`Next`**

  :::{image} user_guide/account_setup_mfa_app_qrcode.png
  :alt: Setup Authenticator app
  :align: center
  :::

- Once this is completed, Microsoft will send you a test notification to respond to

  :::{image} user_guide/account_setup_mfa_authenticator_app_test.png
  :alt: Authenticator app test notification
  :align: center
  :::

- When you click **{guilabel}`Approve`** on the phone notification, you will get the following message in your browser

  :::{image} user_guide/account_setup_mfa_authenticator_app_approved.png
  :alt: Authenticator app test approved
  :align: center
  :::
::::

::::{admonition} 4. Check the Security Information dashboard
:class: dropdown note

- You should now be returned to the Security Information dashboard that lists two verified MFA methods

  :::{image} user_guide/account_setup_mfa_dashboard_two_methods.png
  :alt: Registered MFA methods
  :align: center
  :::

- Choose whichever you prefer to be your **Default sign-in method**.

::::

#### Troubleshooting MFA

Sometimes setting up MFA can be problematic.
You may find the following tips helpful:

- {{inbox_tray}} Make sure you allow notifications on your authenticator app.
- {{sleeping}} Check you don't have **Do not Disturb** mode on.
- {{zap}} You have to be FAST at acknowledging the notification on your app, since the access codes update every 30 seconds.
- {{confused}} Sometimes just going through the steps again solves the problem

## {{unlock}} Access the Secure Research Environment

### {{seedling}} Prerequisites

After going through the account setup procedure, you should have access to:

- Your **username**
- Your **password**
- The {ref}`SRE URL <user_guide_sre_url>`
- [Multifactor authentication](#-set-up-multi-factor-authentication)

:::{tip}
If you aren't sure about any of these then please return to the [**Set up your account**](#-set-up-your-account) section above.
:::

### {{house}} Log into the research environment

::::{admonition} 1. Browse to the SRE URL
:class: dropdown note

- Open a **private/incognito** browser session, so that you don't pick up any existing Microsoft logins

- Go to the {ref}`SRE URL <user_guide_sre_url>` given by your {ref}`System Manager <role_system_manager>`.

    :::{note}
    Our example user, Ada Lovelace, participating in the **sandbox** project, would navigate to **https://sandbox.projects.example.org**.
    :::

::::

::::{admonition} 2. Enter your username and password at the prompt
:class: dropdown note

- At the login prompt enter your **[long-form username](#username)** and click on the **{guilabel}`Next`** button

    :::{image} user_guide/guacamole_oauth_login.png
    :alt: Research environment log in
    :align: center
    ::::

    ::::{tip}
    Our example user, Ada Lovelace, would use **ada.lovelace@projects.example.org** here.
    :::

- Enter your password at the prompt and click on the **{guilabel}`Next`** button
::::

::::{admonition} 3. Login with MFA
:class: dropdown note

- You will now **receive a call or mobile app notification** to authenticate using multifactor authentication (MFA).

    :::{image} user_guide/guacamole_mfa.png
    :alt: MFA trigger
    :align: center
    :::

  {{telephone_receiver}} For the call, you may have to move to an area with good reception and/or press the hash (**#**) key multiple times in-call.

  {{iphone}} For the app you will see a notification saying **"You have received a sign in verification request"**. Go to the app to approve the request.

    :::{caution}
    If you don't respond to the MFA request quickly enough, or if it fails, you may get an error. If this happens, please retry
    :::

::::

You should now be able to see the SRE dashboard screen which will look like the following

:::{image} user_guide/guacamole_dashboard.png
:alt: Research environment dashboard
:align: center
:width: 90%
:::

### {{penguin}} Log into a workspace

On the SRE dashboard, you should see multiple different workspaces that you can access either via an interactive desktop environment (**Desktop**) or a terminal environment (**SSH**).

:::{important}
If you do not see any available workspaces please contact your {ref}`System Manager <role_system_manager>`.
:::

Each of these is a computer[^vm-footnote] with a wide variety of data analysis applications and programming languages pre-installed.
You can use them to analyse the sensitive data belonging to your project while remaining isolated from the wider internet.

[^vm-footnote]: Actually a virtual machine

::::{admonition} 1. Select a workspace
:class: dropdown note

- Click on one of the **Desktop** connections from the list in **All Connections**

:::{note}
Each workspace should have an annotation which indicates its available resources:
- CPUs
- GPUs
- RAM
:::

:::{caution}
These workspaces are shared between everyone on your project. Talk to your collaborators to ensure that you're not all using the same one.
:::

::::

:::::{admonition} 2. Login with your user credentials
:class: dropdown note

- Enter your **[short-form username](#username)** and **password** at the prompt.

  :::{image} user_guide/workspace_login_screen.png
  :alt: Workspace login screen
  :align: center
  :width: 90%
  :::

  :::{note}
  Our example user, Ada Lovelace, would enter **ada.lovelace** and her password.
  :::

  ::::{error}
  If you enter your username and/or password incorrectly you will see a warning like the one below.
  If this happens, please try again, entering your username and password carefully.

  :::{image} user_guide/workspace_login_failure.png
  :alt: Workspace login failure
  :align: center
  :width: 90%
  :::

  If you want to reset your password, follow the steps defined in the [Password and MFA](#-password-and-mfa) section above.
  ::::
:::::

You should now be able to see the SRE dashboard screen which will look like the following

:::{image} user_guide/workspace_xfce_initial.png
:alt: Research environment dashboard
:align: center
:width: 90%
:::

::::{note}
- The Linux desktops within our SRDs use the [Ubuntu operating system](https://ubuntu.com/).
- The desktop environment used by our SRDs is called [Xfce](https://docs.xfce.org/xfce/).
::::

**Welcome to the Data Safe Haven SRE! {{wave}}**

## {{computer}} Analysing sensitive data

The SRD has several pre-installed applications and programming languages to help with your data analysis.

### {{package}} Pre-installed applications

::::{admonition} Programming languages / compilers
:class: dropdown note

:::{include} snippets/software_languages.partial.md
:relative-images:
:::
::::

::::{admonition} Editors / IDEs
:class: dropdown note

:::{include} snippets/software_editors.partial.md
:relative-images:
:::
::::

::::{admonition} Writing / presentation tools
:class: dropdown note

:::{include} snippets/software_presentation.partial.md
:relative-images:
:::
::::

::::{admonition} Database access tools
:class: dropdown note

:::{include} snippets/software_database.partial.md
:relative-images:
:::
::::

::::{admonition} Other useful software
:class: dropdown note

:::{include} snippets/software_other.partial.md
:relative-images:
:::
::::

If you need anything that is not already installed, please discuss this with the designated contact for your SRE.

### {{musical_keyboard}} Keyboard mapping

When you access the SRD you are actually connecting through the cloud to another computer - via a few intermediate computers/servers that monitor and maintain the security of the SRE.

:::{caution}
You may find that the keyboard mapping on your computer is not the same as the one set for the SRD.
:::

::::{admonition} Changing the keyboard layout
:class: dropdown note

From the workspace desktop, click on **{menuselection}`Applications --> Settings --> Keyboard`** to change the layout.

:::{tip}
We recommend opening an application that allows text entry (such as **Libre Office Writer** or a text editor) to check what keys the remote desktop thinks you're typing – especially if you need to use special characters.
:::
::::

### {{unlock}} Access applications

You can access applications from the desktop using either:
- the **Terminal** app accessible frmo the dock at the bottom of the screen
- via a drop-down menu when you right-click on the desktop or click the **{menuselection}`Applications`** button on the top left of the screen

:::{image} user_guide/workspace_desktop_applications.png
:alt: How to access applications from the desktop
:align: center
:width: 90%
:::

### {{snake}} Available Python and R versions

Typing `R` at the command line will give you the system version of `R` with many custom packages pre-installed.

There are several versions of `Python` installed, which are managed through [pyenv](https://github.com/pyenv/pyenv).
You can see the default version (indicated by a '\*') and all other installed versions using the following command:

:::none
> pyenv versions
:::

This will give output like:

:::none
  system
  3.8.12
* 3.9.10 (set by /home/ada.lovelace/.pyenv_version)
  3.10.2
:::

You can change your preferred Python version globally or on a folder-by-folder basis using

- `pyenv global <version number>` (to change the version globally)
- `pyenv local <version number>` (to change the version for the folder you are currently in)

#### Creating virtual environments

We recommend that you use a dedicated [virtual environment](https://docs.python.org/3/tutorial/venv.html) for developing your code in `Python`.
You can easily create a new virtual environment based on any of the available `Python` versions

:::none
> pyenv virtualenv 3.8.12 myvirtualenv
:::

You can then activate it with:

:::none
> pyenv shell myvirtualenv
:::

or if you want to automatically switch to it whenever you are in the current directory

:::none
> pyenv local myvirtualenv
:::

### {{gift}} Install R and python packages

There are local copies of the `PyPI` and `CRAN` package repositories available within the SRE.
You can install packages you need from these copies in the usual way, for example `pip install` and `install.packages` for Python and R respectively.

:::{caution}
You **will not** have access to install packages system-wide and will therefore need to install packages in a user directory.
:::

- For `CRAN` you will be prompted to make a user package directory when you [install your first package](#r-packages).
- For `PyPI` you will need to [install using the `--user` argument to `pip`](#python-packages).

#### R packages

You can install `R` packages from inside `R` (or `RStudio`):

:::R
> install.packages(<package-name>)
:::

You will see something like the following:

:::R
Installing package into '/usr/local/lib/R/site-library'
(as 'lib' is unspecified)
Warning in install.packages("cluster") :
  'lib = "/usr/local/lib/R/site-library"' is not writable
Would you like to use a personal library instead? (yes/No/cancel)
:::

Enter `yes`, which prompts you to confirm the name of the library:

:::R
Would you like to create a personal library
'~/R/x86_64-pc-linux-gnu-library/3.5'
to install packages into? (yes/No/cancel)
:::

Enter `yes`, to install the packages.

#### Python packages

You can install `python` packages from a terminal.

:::bash
pip install --user <package-name>
:::

:::{tip}
If you are using a virtual environment as recommended above, you will not need the `--user` flag.
:::

#### Package availability

Depending on the type of data you are accessing, different `R` and `python` packages will be available to you (in addition to the ones that are pre-installed):

- {ref}`Tier 2 <policy_tier_2>` (medium security) environments have full mirrors of `PyPI` and `CRAN` available.
- {ref}`Tier 3 <policy_tier_3>` (high security) environments only have pre-authorised packages available.

If you need to use a package that is not on the allowlist see the section on how to [bring software or data into the environment](#-bring-in-new-files-to-the-sre) below.

(role_researcher_user_guide_shared_storage)=

## {{link}} Share files with collaborators

### {{open_file_folder}} Shared directories within the SRE

There are several shared areas on the SRD that all collaborators within a research project team can see and access:

- [input data](#input-data-data): `/data/`
- [shared space](#shared-space-shared): `/shared/`
- [scratch space](#scratch-space-scratch): `/scratch/`
- [backup space](#backup-space-backup): `/backup/`
- [output resources](#output-resources-output): `/output/`

#### Input data: `/data/`

Data that has been "ingressed" - approved and brought into the secure research environment - can be found in the `/data/` folder.

Everyone in your group will be able to access it, but it is **read-only**.

:::{important}
You will not be able to change any of the files in `/data/` .
If you want to make derived datasets, for example cleaned and reformatted data, please add those to the `/shared/` or `/output/` directories.
:::

The contents of `/data/` will be **identical** on all SRDs in your SRE.
For example, if your group requests a GPU-enabled machine, this will contain an identical `/data/` folder.

:::{tip}
If you are using the Data Safe Haven as part of an organised event, you might find example slides or document templates in the `/data/` drive.
:::

#### Shared space: `/shared/`

The `/shared/` folder should be used for any work that you want to share with your group.
Everyone in your group will be able to access it, and will have **read-and-write access**.

The contents of `/shared/` will be **identical** on all SRDs in your SRE.

#### Scratch space: `/scratch/`

The `/scratch/` folder should be used for any work-in-progress that isn't ready to share yet.
Although everyone in your group will have **read-and-write access**, you can create your own folders inside `/scratch` and choose your own permissions for them.

:::{caution}
You should not use `/scratch/` for long-term storage as it can be reset at any time without warning (_e.g._ when the VM is restarted).
:::

The contents of `/scratch/` will be **different** on different VMs in your SRE.

#### Backup space: `/backup/`

The `/backup/` folder should be used for any work-in-progress that you want to have backed up.
In the event of any data loss due to accidental data deletion by a TRE user, your system administrator can restore the `/backup/` folder to the state it was in at an earlier point in time (up to 12 weeks in the past).
This **cannot** be used to recover individual files - only the complete contents of the folder.
Everyone in your group will have **read-and-write access** to all folders on `/backup`.

The contents of `/backup/` will be **identical** on all SRDs in your SRE.

#### Output resources: `/output/`

Any outputs that you want to extract from the secure environment should be placed in the `/output/` folder on the SRD.
Everyone in your group will be able to access it, and will have **read-and-write access**.
Anything placed in here will be considered for data egress - removal from the secure research environment - by the project's principal investigator together with the data provider.

:::{tip}
You may want to consider having subfolders of `/output/` to make the review of this directory easier.
:::

### {{newspaper}} Bring in new files to the SRE

Bringing software into a secure research environment may constitute a security risk.
Bringing new data into the SRE may mean that the environment needs to be updated to a more secure tier.

The review of the "ingress" of new code or data will be coordinated by the designated contact for your SRE.
They will have to discuss whether this is an acceptable risk to the data security with the project's principle investigator and data provider and the decision might be "no".

:::{hint}
You can make the process as easy as possible by providing as much information as possible about the code or data you'd like to bring into the environment and about how it is to be used.
:::

## {{pill}} Versioning code using GitLab

`GitLab` is a code hosting platform for version control and collaboration - similar to `GitHub`.
It allows you to use `git` to **version control** your work, coordinate tasks using `GitLab` **issues** and review work using `GitLab` **merge requests**.

:::{note}
`GitLab` is a fully open source project.
This information doesn't matter at all for how you use `GitLab` within the SRE, but we do want to thank the community for maintaining free and open source software for us to use and reuse.
You can read more about `GitLab` at [their code repository](<https://gitlab.com/gitlab-org/gitlab>).
:::

The `GitLab` instance within the SRE can contain code, documentation and results from your team's analyses.
You do not need to worry about the security of the information you upload there as it is fully contained within the SRE and there is no access to the internet and/or external servers.

:::{important}
The `GitLab` instance within the SRE is entirely separate from the `https://gitlab.com` service.
:::

### {{books}} Maintaining an archive of the project

The Data Safe Haven SRE is hosted on the Microsoft Azure cloud platform.
One of the benefits of having cloud based infastructure is that it can be deleted forever when the project is over.
Deleting the infrastructure ensures that neither sensitive data nor insights derived from the data or modelling techniques persist.

While working on the project, make sure that every piece of code you think might be useful is stored in a GitLab repository within the secure environment.
Any other work should be transferred to the `/shared/` drive so that it is accessible to other TRE users.
You can also use the `/backup/` drive to store work that you want to keep safe from accidental deletion.
Anything that you think should be considered for **egress** from the environment (eg. images or processed datasets) should be transferred to the shared `/output/` drive.

:::{caution}
Anything that is not transferred to the `/output/` drive to be considered for egress will be deleted forever when the project is over.
:::

### {{unlock}} Access GitLab

You can access `GitLab` from an internet browser in the SRD using the desktop shortcut.
Login with username `firstname.lastname` (the domain is not needed) and `password` .

::::{note}
Our example user, Ada Lovelace would enter `ada.lovelace` in the `LDAP Username` box, enter her password and then click `Sign in` .

:::{image} user_guide/gitlab_screenshot_login.png
:alt: GitLab login
:align: center
:::
::::

Accessing `GitLab` from the browser on the SRD is an easy way to switch between analysis work and documenting the process or results.

:::{warning}
Do not use your username and password from a pre-existing `GitLab` account!
The `GitLab` instance within the SRE is entirely separate from the `https://gitlab.com` service and is expecting the same username and password that you used to log into the SRE.
:::

### {{open_hands}} Public repositories within the SRE

The `GitLab` instance inside the secure research environment is entirely contained _inside_ the SRE.

When you make a repository inside the SRE "public" it is visible to your collaborators who also have access to the SRE.
A "public" repository within the SRE is only visible to others with the same data access approval, it is not open to the general public via the internet.

:::{tip}
We recommend that you make your repositories public to facilitate collaboration within the secure research environment.
:::

### {{construction_worker}} Support for GitLab use

If you have not used GitLab before:

- There is a small tutorial available as an [Appendix](#-appendix-b-gitlab-tutorial-notes) to this user guide.
- You can find the official documentation on the [GitLab website](https://docs.gitlab.com/ee/user/index.html).
- Ask your team mates for help.
- Ask the designated contact for your SRE.
- There may be a dedicated discussion channel, for example a Slack/Teams/Discord channel or an email list.

## {{book}} Collaborate on documents using CodiMD

`CodiMD` is a locally installed tool that allows you to collaboratively write reports.
It uses `Markdown` which is a simple way to format your text so that it renders nicely in full HTML.

:::{note}
`CodiMD` is a fully open source version of the `HackMD` software.
This information doesn't matter at all for how you use `CodiMD` within the SRE, but we do want to thank the community for maintaining free and open source software for us to use and reuse.
You can read more about `CodiMD` at [their GitHub repository](<https://github.com/hackmdio/codimd#codimd>).
:::

We recommend [this Markdown cheat sheet](https://github.com/adam-p/markdown-here/wiki/Markdown-Cheatsheet).

### {{unlock}} Access CodiMD

You can access `CodiMD` from an internet browser from the SRD using the desktop shortcut.
Login with username `firstname.lastname` (the domain is not needed) and `password` .

::::{note}
Our example user, Ada Lovelace would enter `ada.lovelace` in the `Username` box, enter her password and then click `Sign in` .

:::{image} user_guide/codimd_logon.png
:alt: CodiMD login
:align: center
:::
::::

Accessing CodiMD from the browser on the SRD is an easy way to switch between analysis work and documenting the process or results.

### {{busts_in_silhouette}} Editing other people's documents

The CodiMD instance inside the secure research environment is entirely contained _inside_ the SRE.

When you make a markdown document inside the SRE "editable" your collaborators who also have access to the SRE can access it via the URL at the top of the page.
They will have the right to change the file if they are signed into the CodiMD instance.

The link will only work for people who have the same data access approval, it is not open to the general public via the internet.

:::{image} user_guide/codimd_access_options.png
:alt: CodiMD access options
:align: center
:::

:::{tip}
We recommend that you make your documents **editable** to facilitate collaboration within the secure research environment.
Alternatively, the **locked** option allows others to read but not edit the document.
:::

The default URL is quite long and difficult to share with your collaborators.
We recommend **publishing** the document to get a much shorter URL which is easier to share with others.

Click the `Publish` button to publish the document and generate the short URL.
Click the pen button (shown in the image below) to return to the editable markdown view.

:::{image} user_guide/codimd_publishing.png
:alt: CodiMD publishing
:align: center
:::

:::{important}
Remember that the document is not published to the internet, it is only available to others within the SRE.
:::

### {{microscope}} Troubleshooting CodiMD

We have noticed that a lower case `L` and an upper case `I` look very similar and often trip up users in the SRE.

:::{tip}
Double check the characters in the URL, and if there are ambiguous ones try the one you haven't tried yet!
:::

Rather than proliferate lots of documents, we recommend that one person is tasked with creating the file and sharing the URL with other team members.

:::{tip}
You could use the GitLab wiki or `README` file to share links to collaboratively written documents.
:::

## {{unlock}} Access additional SRDs

Your project might make use of further SRDs in addition to the main shared desktop.
Usually this is because of a requirement for a different type of computing resource, such as access to one or more GPUs (graphics processing units).

You will access this machine in a similar way to the main shared desktop, by selecting a different `Desktop` connection.

::::{note}
Our example user, Ada Lovelace, participating in the **sandbox** project, might select `Ubuntu1_CPU2_8GB (Desktop)` instead of `Ubuntu0_CPU2_8GB (Desktop)`
:::{image} user_guide/guacamole_dashboard.png
:alt: Research environment dashboard
:align: center
:::
::::

- This will bring you to the normal login screen, where you use the same `username` and `password` credentials as before.
- Any local files that you have created in the `/output/` folder on other VMs (e.g. analysis scripts, notes, derived data) will be automatically available in the new VM.

:::{tip}
The naming pattern of the available desktop connections lets you know their compute capabilities.
For example `Ubuntu1_CPU2_8GB` has 2 CPUs and 8GB of RAM.
:::

## {{green_book}} Access databases

Your project might use a database for holding the input data.
You might also/instead be provided with a database for use in analysing the data.
The database server will use either `Microsoft SQL` or `PostgreSQL`.

If you have access to one or more databases, you can access them using the following details, replacing `<SRE ID>` with the {ref}`SRE ID <user_guide_sre_id>` for your project.

For guidance on how to use the databases, many resources are available on the internet.
Official tutorials for [MSSQL](https://learn.microsoft.com/en-us/sql/sql-server/tutorials-for-sql-server-2016?view=sql-server-ver16) and [PostgreSQL](https://www.postgresql.org/docs/current/tutorial.html) may be good starting points.

### {{bento_box}} Microsoft SQL

- Server name: `MSSQL-<SRE ID>` (e.g. `MSSQL-SANDBOX` )
- Database name: \<provided by your {ref}`System Manager <role_system_manager>`>
- Port: 1433

### {{postbox}} PostgreSQL

- Server name: `PSTGRS-<SRE ID>` (e.g. `PSTGRS-SANDBOX` )
- Database name: \<provided by your {ref}`System Manager <role_system_manager>`>
- Port: 5432

Examples are given below for connecting using `Azure Data Studio`, `DBeaver`, `Python` and `R`.
The instructions for using other graphical interfaces or programming languages will be similar.

### {{art}} Connecting using Azure Data Studio

`Azure Data Studio` is currently only able to connect to `Microsoft SQL` databases.

::::{note}
Our example user Ada Lovelace, working in the **sandbox** SRE on the **projects.example.org** Data Safe Haven, would connect using Azure Data Studio as follows:


:::{image} user_guide/db_azure_data_studio.png
:alt: Azure Data Studio connection details
:align: center
:::
::::

:::{important}
Be sure to select `Windows authentication` here so that your username and password will be passed through to the database.
:::

### {{bear}} Connecting using DBeaver

Click on the `New database connection` button (which looks a bit like an electrical plug with a plus sign next to it)

#### Microsoft SQL

- Select `SQL Server` as the database type
- Enter the necessary information in the `Host` and `Port` boxes and set `Authentication` to `Kerberos`
- Tick `Show All Schemas` otherwise you will not be able to see the input data

::::{note}
Our example user Ada Lovelace, working in the **sandbox** SRE on the **projects.example.org** Data Safe Haven, would connect using DBeaver as follows:

:::{image} user_guide/db_dbeaver_mssql.png
:alt: DBeaver connection details for Microsoft SQL
:align: center
:::
::::

:::{important}
Be sure to select `Kerberos authentication` so that your username and password will be passed through to the database
:::

::::{note}
After clicking finish, you may be prompted to download missing driver files.
Drivers have already been provided on the SRD for Microsoft SQL databases.
Clicking `Download` will make DBeaver use these pre-downloaded drivers without requiring internet access.
Thus, even on SRDs with no external internet access (Tier 2 or above), click `Download`.
Note that the prompt may appear multiple times.
:::{image} user_guide/db_dbeaver_mssql_download.png
:alt: DBeaver driver download for Microsoft SQL
:align: center
:::
::::

#### PostgreSQL

- Select `PostgreSQL` as the database type
- Enter the necessary information in the `Host` and `Port` boxes and set `Authentication` to `Database Native`

:::{important}
You do not need to enter any information in the `Username` or `Password` fields
:::

::::{note}
Our example user Ada Lovelace, working in the **sandbox** SRE on the **projects.example.org** Data Safe Haven, would connect using DBeaver as follows:

:::{image} user_guide/db_dbeaver_postgres_connection.png
:alt: DBeaver connection details for PostgreSQL
:align: center
:::
::::

::::{tip}
If you are prompted for `Username` or `Password` when connecting, you can leave these blank and the correct username and password will be automatically passed through to the database
:::{image} user_guide/db_dbeaver_postgres_ignore.png
:alt: DBeaver username/password prompt
:align: center
:::
::::

::::{note}
After clicking finish, you may be prompted to download missing driver files.
Drivers have already been provided on the SRD for PostgreSQL databases.
Clicking `Download` will make DBeaver use these pre-downloaded drivers without requiring internet access.
Thus, even on SRDs with no external internet access (Tier 2 or above), click `Download`.
Note that the prompt may appear multiple times.
:::{image} user_guide/db_dbeaver_pstgrs_download.png
:alt: DBeaver driver download for Microsoft SQL
:align: center
:::
::::

### {{snake}} Connecting using Python

Database connections can be made using `pyodbc` or `psycopg2` depending on which database flavour is being used.
The data can be read into a dataframe for local analysis.

:::{note}
Our example user Ada Lovelace, working in the **sandbox** SRE on the **projects.example.org** Data Safe Haven, would connect using DBeaver as follows:
:::

#### Microsoft SQL

:::python
import pyodbc
import pandas as pd

server = "MSSQL-SANDBOX.projects.example.org"
port = "1433"
db_name = "master"

cnxn = pyodbc.connect("DRIVER={ODBC Driver 17 for SQL Server};SERVER=" + server + "," + port + ";DATABASE=" + db_name + ";Trusted_Connection=yes;")

df = pd.read_sql("SELECT * FROM information_schema.tables;", cnxn)
print(df.head(3))
:::

#### PostgreSQL

:::python
import psycopg2
import pandas as pd

server = "PSTGRS-SANDBOX.projects.example.org"
port = 5432
db_name = "postgres"

cnxn = psycopg2.connect(host=server, port=port, database=db_name)
df = pd.read_sql("SELECT * FROM information_schema.tables;", cnxn)
print(df.head(3))
:::

### {{rose}} Connecting using R

Database connections can be made using `odbc` or `RPostgres` depending on which database flavour is being used.
The data can be read into a dataframe for local analysis.

:::{note}
Our example user Ada Lovelace, working in the **sandbox** SRE on the **projects.example.org** Data Safe Haven, would connect using DBeaver as follows:
:::

#### Microsoft SQL

:::R
library(DBI)
library(odbc)

# Connect to the databases
cnxn <- DBI::dbConnect(
    odbc::odbc(),
    Driver = "ODBC Driver 17 for SQL Server",
    Server = "MSSQL-SANDBOX.projects.example.org,1433",
    Database = "master",
    Trusted_Connection = "yes"
)

# Run a query and save the output into a dataframe
df <- dbGetQuery(cnxn, "SELECT * FROM information_schema.tables;")
head(df, 3)
:::

#### PostgreSQL

:::R
library(DBI)
library(RPostgres)

# Connect to the databases
cnxn <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = "PSTGRS-SANDBOX.projects.example.org",
    port = 5432,
    dbname = "postgres"
)

# Run a query and save the output into a dataframe
df <- dbGetQuery(cnxn, "SELECT * FROM information_schema.tables;")
head(df, 3)
:::

## {{bug}} Report a bug

The Data Safe Haven SRE has been developed in close collaboration with our users: you!

We try to make the user experience as smooth as possible and this document has been greatly improved by feedback from project participants and researchers going through the process for the first time.
We are constantly working to improve the SRE and we really appreciate your input and support as we develop the infrastructure.

:::{important}
If you find problems with the IT infrastructure, please contact the designated contact for your SRE.
:::

### {{wrench}} Help us to help you

To help us fix your issues please do the following:

- Make sure you have **read this document** and checked if it answers your query.
    - Please do not log an issue before you have read all of the sections in this document.
- Log out of the SRE and log back in again at least once
    - Re-attempt the process leading to the bug/error at least twice.
    - We know that "turn it off and turn it back on again" is a frustrating piece of advice to receive, but in our experience it works rather well! (Particularly when there are lots of folks trying these steps at the same time.)
    - The multi-factor authentication step in particular is known to have quite a few gremlins.
    - If you are getting frustrated, log out of everything, turn off your computer, take a 15 minute coffee break, and then start the process from the beginning.

- Write down a comprehensive summary of the issue.
- A really good bug report makes it much easier to pin down what the problem is. Please include:
    - Your computer's operating system and operating system version.
    - Precise condition under which the error occurs.
        - What steps would someone need to take to get the exact same error?
    - A precise description of the problem.
        - What happens? What would you expect to happen if there were no error?
    - Any workarounds/fixes you have found.

- Send the bug report to the designated contact for your SRE.

:::{hint}
We very strongly recommend "rubber ducking" this process before you talk to the designated contact for your SRE.
Either talk through to your imaginary rubber duck, or find a team member to describe the error to, as you write down the steps you have taken.
It is amazing how often working through your problem out loud helps you realise what the answer might be.
:::

## {{pray}} Acknowledgments

This user guide is based on an initial document written in March/April 2018 by Kirstie Whitaker.

Updates:

- December 2018 by Catherine Lawrence, Franz Király, Martin O'Reilly, and Sebastian Vollmer.
- March/April 2019 by Miguel Morin, Catherine Lawrence, Alvaro Cabrejas Egea, Kirstie Whitaker, James Robinson and Martin O'Reilly.
- November 2019 by Ben Walden, James Robinson and Daisy Parry.
- April 2020 by Jules Manser, James Robinson and Kirstie Whitaker.
- November 2021 by James Robinson

## {{passport_control}} Appendix A: Command Line Basics

If you have never used a Linux desktop before, you might find some of the following commands useful if you are using a terminal.

Go into a project directory to work in it

:::bash
cd NAME-OF-PROJECT
:::

Go back one directory

:::bash
cd ..
:::

List what’s in the current directory

:::bash
ls
:::

Create a new directory

:::bash
mkdir NAME-OF-YOUR-DIRECTORY
:::

Remove a file

:::bash
rm NAME-OF-FILE
:::

Remove a directory and all of its contents

:::bash
rm -r NAME-OF-DIRECTORY
:::

View command history

:::bash
history
:::

Show which directory I am in

:::bash
pwd
:::

Clear the shell window

:::bash
clear
:::

For a more detailed introduction, visit the official Ubuntu tutorial, [The Linux command line for beginners](https://ubuntu.com/tutorials/command-line-for-beginners)

## {{notebook}} Appendix B: Gitlab tutorial notes

`GitLab` can be thought of as a local version of `GitHub` - that is a git server along with useful features such as:

- **Project wiki** - exactly what it says
- **Project pastebin** - share bits of code
- **Project issue tracker** - track things TODO and bugs
- **Pull requests** - Way to keep track of changes individuals have made to be included in master

Some teams design their entire workflows around these things.
A comparison in terms of features can be found [here](https://usersnap.com/blog/gitlab-github/).

### Getting started with Git

If you have never used `git` before, you might want to take a look at an introductory guide.
There are multiple `git` cheat sheets such as[this one from the JIRA authors](https://www.atlassian.com/git/tutorials/atlassian-git-cheatsheet).

### Repositories

A repository is usually used to organize a single project.
Repositories can contain folders and files, images, videos, spreadsheets, and data sets – anything your project needs.
We recommend including a README, or a file with information about your project.
Over the course of the work that you do in your SRE, you will often be accessing and adding files to the same project repository.

### Add your Git username and set your email

It is important to configure your `git` username and email address, since every `git` commit will use this information to identify you as the author.
On your shell, type the following command to add your username:

:::bash
git config --global user.name "YOUR_USERNAME"
:::

Then verify that you have the correct username:

:::bash
git config --global user.name
:::

To set your email address, type the following command:

:::bash
git config --global user.email "your_email_address@example.com"
:::

To verify that you entered your email correctly, type:

:::bash
git config --global user.email
:::

You'll need to do this only once, since you are using the `--global` option.
It tells Git to always use this information for anything you do on that system.
If you want to override this with a different username or email address for specific projects, you can run the command without the `--global` option when you’re in that project.

### Cloning projects

In `git`, when you copy a project you say you "clone" it.
To work on a `git` project in the SRD, you will need to clone it.
To do this, sign in to `GitLab`.

When you are on your Dashboard, click on the project that you’d like to clone.
To work in the project, you can copy a link to the `git` repository through a SSH or a HTTPS protocol.
SSH is easier to use after it’s been set up, [you can find the details here](https://docs.gitlab.com/ee/user/ssh.html).
While you are at the Project tab, select HTTPS or SSH from the dropdown menu and copy the link using the Copy URL to clipboard button (you’ll have to paste it on your shell in the next step>).

:::{image} user_guide/gitlab_clone_url.png
:alt: Clone GitLab project
:align: center
:::

Go to your computer’s shell and type the following command with your SSH or HTTPS URL:

:::bash
git clone <PASTE HTTPS OR SSH HERE>
:::

### Branches

Branching is the way to work on different versions of a repository at one time.
By default your repository has one branch usually named `master` or `main` which is considered to be the definitive branch.
We use branches to experiment and make edits before committing them to `main`.

When you create a branch off the `main` branch, you’re making a copy, or snapshot, of `main` as it was at that point in time.
If someone else made changes to the `main` branch while you were working on your branch, you could pull in those updates.

To create a branch:

:::bash
git checkout -b NAME-OF-BRANCH
:::

Work on an existing branch:

:::bash
git checkout NAME-OF-BRANCH
:::

To merge the `main` branch into a created branch you need to be on the created branch.

:::bash
git checkout NAME-OF-BRANCH
git merge main
:::

To merge a created branch into the `main` branch you need to be on the created branch.

:::bash
git checkout main
git merge NAME-OF-BRANCH
:::

### Downloading the latest changes in a project

This is for you to work on an up-to-date copy (it is important to do this every time you start working on a project), while you set up tracking branches.
You pull from remote repositories to get all the changes made by users since the last time you cloned or pulled the project.
Later, you can push your local commits to the remote repositories.

:::bash
git pull REMOTE NAME-OF-BRANCH
:::

When you first clone a repository, REMOTE is typically `origin`.
This is where the repository came from, and it indicates the SSH or HTTPS URL of the repository on the remote server.
NAME-OF-BRANCH is usually `main`, but it may be any existing branch.

### Add and commit local changes

You’ll see your local changes in red when you type `git status`.
These changes may be new, modified, or deleted files/folders.
Use `git add` to stage a local file/folder for committing.
Then use `git commit` to commit the staged files:

:::bash
git add FILE OR FOLDER
git commit -m "COMMENT TO DESCRIBE THE INTENTION OF THE COMMIT"
:::

To add and commit all local changes in one command:

:::bash
git add .
git commit -m "COMMENT TO DESCRIBE THE INTENTION OF THE COMMIT"
:::

To push all local commits to the remote repository:

:::bash
git push REMOTE NAME-OF-BRANCH
:::

For example, to push your local commits to the `main` branch of the origin remote:

:::bash
git push origin main
:::

To delete all local changes in the repository that have not been added to the staging area, and leave unstaged files/folders, type:

:::bash
git checkout .
:::

**Note:** The . character typically means all in Git.

### How to create a Merge Request

Merge requests are useful to integrate separate changes that you’ve made to a project, on different branches.
This is a brief guide on how to create a merge request.
For more information, check the [merge requests documentation](https://docs.gitlab.com/ee/user/project/merge_requests/index.html).

- Before you start, you should have already created a branch and pushed your changes to `GitLab`.
- Go to the project where you’d like to merge your changes and click on the `Merge requests` tab.
- Click on `New merge request` on the right side of the screen.
- From there on, you have the option to select the source branch and the target branch you’d like to compare to.

The default target project is the upstream repository, but you can choose to compare across any of its forks.

:::{image} user_guide/gitlab_new_merge_request.png
:alt: New GitLab merge request
:align: center
:::

- When ready, click on the Compare branches and continue button.
- At a minimum, add a title and a description to your merge request.
- Optionally, select a user to review your merge request and to accept or close it. You may also select a milestone and labels.

:::{image} user_guide/gitlab_merge_request_details.png
:alt: GitLab merge request details
:align: center
:::

- When ready, click on the `Submit merge request` button.

Your merge request will be ready to be approved and merged.
