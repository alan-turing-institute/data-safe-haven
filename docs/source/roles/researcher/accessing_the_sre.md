(roles_researcher_access_sre)=

# Accessing the Secure Research Environment

## {{seedling}} Prerequisites

After going through the account setup procedure, you should have access to:

- Your **username**
- Your **password**
- The {ref}`SRE URL <roles_researcher_sre_url>`
- {ref}`Multifactor authentication <roles_researcher_password_and_mfa>`

:::{tip}
If you aren't sure about any of these then please return to the **{ref}`Set up your account <roles_researcher_setup_your_account>`** section.
:::

## {{unlock}} Log into the research environment

::::{admonition} 1. Browse to the SRE URL
:class: dropdown note

- Open a **private/incognito** browser session, so that you don't pick up any existing Microsoft logins

- Go to the {ref}`SRE URL <roles_researcher_sre_url>` given by your {ref}`System Manager <role_system_manager>`.

    :::{note}
    Our example user, Ada Lovelace, participating in the **sandbox** project, would navigate to **https://sandbox.projects.example.org**.
    :::

::::

::::{admonition} 2. Enter your username and password at the prompt
:class: dropdown note

- At the login prompt enter your **{ref}`long-form username <roles_researcher_username>`** and click on the **{guilabel}`Next`** button

    :::{image} images/guacamole_oauth_login.png
    :alt: Research environment log in
    :align: center
    :width: 90%
    ::::

    ::::{tip}
    Our example user, Ada Lovelace, would use **ada.lovelace@projects.example.org** here.
    :::

- Enter your password at the prompt and click on the **{guilabel}`Next`** button

::::

::::{admonition} 3. Login with MFA
:class: dropdown note

- You will now **receive a call or mobile app notification** to authenticate using multifactor authentication (MFA).

    :::{image} images/guacamole_mfa.png
    :alt: MFA trigger
    :align: center
    :width: 90%
    :::

  {{telephone_receiver}} For the call, you may have to move to an area with good reception and/or press the hash (**#**) key multiple times in-call.

  {{iphone}} For the app you will see a notification saying **"You have received a sign in verification request"**. Go to the app to approve the request.

    :::{caution}
    If you don't respond to the MFA request quickly enough, or if it fails, you may get an error. If this happens, please retry
    :::

::::

You should now be able to see the SRE dashboard screen which will look like the following

:::{image} images/guacamole_dashboard.png
:alt: Research environment dashboard
:align: center
:width: 90%
:::

## {{house}} Log into a workspace

On the SRE dashboard, you should see multiple different workspaces that you can access either via an interactive desktop environment (**Desktop**) or a terminal environment (**SSH**).

:::{important}
If you do not see any available workspaces please contact your {ref}`System Manager <role_system_manager>`.
:::

Each of these is a computer[^footnote-vm] with a wide variety of data analysis applications and programming languages pre-installed.
You can use them to analyse the sensitive data belonging to your project while remaining isolated from the wider internet.

[^footnote-vm]: Actually a virtual machine

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

- Enter your **{ref}`short-form username <roles_researcher_username>`** and **password** at the prompt.

  :::{image} images/workspace_login_screen.png
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

  :::{image} images/workspace_login_failure.png
  :alt: Workspace login failure
  :align: center
  :width: 90%
  :::

  If you want to reset your password, follow the steps defined in the {ref}`Password and MFA <roles_researcher_password_and_mfa>` section.
  ::::
:::::

You should now be able to see the SRE dashboard screen which will look like the following

:::{image} images/workspace_xfce_initial.png
:alt: Research environment dashboard
:align: center
:width: 90%
:::

Welcome to the Data Safe Haven SRE! {{wave}}

## {{unlock}} Access additional workspaces

Your project might make use of further workspaces in addition to the main shared desktop.
Usually this is because of a requirement for a different type of computing resource, such as access to one or more GPUs (graphics processing units).

You will access this machine in a similar way to the main shared desktop, by selecting a different **Desktop** connection.

::::{admonition} Selecting a different workspace
:class: dropdown note

- Our example user, Ada Lovelace, participating in the **sandbox** project, might select **Workspace 2** instead of **Workspace 1** since it has additional CPUs and RAM.

    :::{image} images/guacamole_dashboard_multiple_workspaces.png
    :alt: Research environment dashboard
    :align: center
    :width: 90%
    :::

- This will bring her to the normal login screen, where she will use the short-form username **ada.lovelace** and her password as before.

::::

:::{tip}
When you are connected to a workspace, you may switch to another by bringing up the [Guacamole menu](https://guacamole.apache.org/doc/gug/using-guacamole.html#the-guacamole-menu) with **{kbd}`Ctrl+Alt+Shift`** and navigating to the [home screen](https://guacamole.apache.org/doc/gug/using-guacamole.html#client-user-menu).
:::

:::{tip}
Any files in the **/mnt/output/**, **/home/** or **/mnt/shared** folders on other workspaces will be available in this workspace too.
:::
