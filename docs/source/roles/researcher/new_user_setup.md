(roles_researcher_new_user_setup)=

# New user setup

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

(roles_researcher_username_domain)=
Username domain
: the domain (for example **projects.example.org**) which your user account will belong to. Multiple projects can share the same domain.

(roles_researcher_sre_id)=
SRE ID
: each SRE has a unique short ID, for example **sandbox** which your {ref}`System Manager <role_system_manager>` will use to distinguish different SREs in the same Data Safe Haven.

(roles_researcher_sre_url)=
SRE URL
: each SRE has a unique URL (for example **sandbox.projects.example.org**) which is used to access the data.

(roles_researcher_setup_your_account)=

## {{rocket}} Set up your account

This section of the user guide will help you set up your new account on the SRE you'll be using.

### {{seedling}} Prerequisites

Make sure you have all of the following when connecting to the SRE.

- {{computer}} Your computer.
- {{wrench}} Your [username](#username) and the {ref}`username domain <roles_researcher_username_domain>` for your SRE.
- {{european_castle}} The {ref}`URL <roles_researcher_sre_url>` for your SRE.
- {{satellite}} [Access](#network-access) to a specific wired or wireless network (if this is required for your project).
- {{iphone}} Your [phone](#your-phone-for-multi-factor-authentication), with good signal connectivity.

:::{important}
You should have received an email from your {ref}`System Manager <role_system_manager>` with your account details, the URL for your SRE, and any necessary network or [training requirements](#data-security-training-requirements) for your project.
:::

You should also know who the **designated contact** for your SRE is.
This might be an administrator or one of the people working on the project with you.
They will be your primary point of contact if you have any issues in connecting to or using the SRE.

(roles_researcher_username)=

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

You should be given the {ref}`username domain <roles_researcher_username_domain>` in the initial email from your {ref}`System Manager <role_system_manager>`.
You might receive the {ref}`SRE URL <roles_researcher_sre_url>` at this time, or you might be assigned to a particular SRE at a later point.

:::{note}
In this document Ada Lovelace - our example user - will be participating in the **sandbox** project.

- Her **{ref}`username domain <roles_researcher_username_domain>`** is **projects.example.org**.
- Her **{ref}`SRE URL <roles_researcher_sre_url>`** is **https://sandbox.projects.example.org**.

:::

(roles_researcher_password_and_mfa)=

## {{closed_lock_with_key}} Password and MFA

For security reasons, you must reset your password before you log in for the first time.
Please follow these steps carefully.

::::{admonition} 1. Start the password reset process
:class: dropdown note

- Go to `https://aka.ms/mfasetup` in a **private/incognito** browser session on your computer.

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

    :::{image} images/account_setup_forgotten_password.png
    :alt: Forgotten my password
    :align: center
    :width: 90%
    :::
::::

::::{admonition} 3. Fill out the CAPTCHA
:class: dropdown note

- Fill out the requested CAPTCHA (your username should be pre-filled) then click on the **{guilabel}`Next`** button.

    :::{image} images/account_setup_captcha.png
    :alt: Password CAPTCHA
    :align: center
    :width: 90%
    :::
::::

::::{admonition} 4. Confirm your contact details
:class: dropdown note

- Confirm your phone number or email address, which you provided to the {ref}`System Manager <role_system_manager>` when you registered for access to the environment.

    :::{image} images/account_setup_verify_phone.png
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

    :::{image} images/account_setup_new_password.png
    :alt: New password
    :align: center
    :width: 90%
  :::

- Click on the **{guilabel}`Finish`** button and you should get this notice

    :::{image} images/account_setup_new_password_sign_in.png
    :alt: Click to continue
    :align: center
    :width: 90%
    :::

- Click on this link and provide your username and password when prompted.
- At this point you will be asked for additional security verification.

    :::{image} images/account_setup_more_information_required.png
    :alt: Click to continue
    :align: center
    :width: 90%
    :::
::::

### {{door}} Set up multi-factor authentication

The next step in setting up your account is to authenticate your account from your phone.
This additional security verification is to make it harder for people to impersonate you and connect to the environment without permission.
This is known as multi-factor authentication (MFA).
The Data Safe Haven requires that you use a phone app for MFA - this can be **Microsoft Authenticator** or another authenticator app.

#### {{bento_box}} Microsoft Authenticator app

::::{admonition} 1. Download the Microsoft Authenticator app
:class: dropdown note

Search for **Microsoft Authenticator** in your phone's app store or follow the appropriate link for your phone here:

- {{apple}} iOS: `https://bit.ly/iosauthenticator`
- {{robot}} Android: `https://bit.ly/androidauthenticator`
- {{bento_box}} Windows mobile: `https://bit.ly/windowsauthenticator`

    :::{important}
    You must give permission for the authenticator app to send you notifications for the app to work as an MFA method.
    :::

::::

::::{admonition} 2. Add sign-in method
:class: dropdown note

- Click on **{guilabel}`+ Add sign-in method`** and select **Authenticator app**.

    :::{image} images/account_setup_mfa_add_authenticator_app.png
    :alt: Add Authenticator app
    :align: center
    :width: 90%
    :::

- At the **Getting the app** click on **{guilabel}`Next`**.

    :::{image} images/account_setup_mfa_choose_authenticator_app.png
    :alt: Add Authenticator app
    :align: center
    :width: 90%
    :::

- Open the Microsoft Authenticator app

::::

::::{admonition} 3. Register your app
:class: dropdown note

- From the Microsoft Authenticator app
    - Select **Add an account**
    - Select **Work or School account**
- From your browser, at the on-screen prompt click on **{guilabel}`Next`**.
    :::{image} images/account_setup_mfa_allow_notifications.png
    :alt: Allow Authenticator notifications
    :align: center
    :width: 90%
    :::

- The next prompt will give you a QR code to scan, like the one shown below
- Scan the QR code on the screen then click **{guilabel}`Next`**

  :::{image} images/account_setup_mfa_app_qrcode.png
  :alt: Setup Authenticator app
  :align: center
  :width: 90%
  :::

- Once this is completed, Microsoft will send you a test notification to respond to

  :::{image} images/account_setup_mfa_microsoft_authenticator_app_test.png
  :alt: Authenticator app test notification
  :align: center
  :width: 90%
  :::

- When you click **{guilabel}`Approve`** on the phone notification, you will get the following message in your browser

  :::{image} images/account_setup_mfa_microsoft_authenticator_app_approved.png
  :alt: Authenticator app test approved
  :align: center
  :width: 90%
  :::
::::

::::{admonition} 4. Check the Security Information dashboard
:class: dropdown note

- You should now be returned to the Security Information dashboard that shows the **Microsoft Authenticator** method.

  :::{image} images/account_setup_mfa_dashboard_microsoft_authenticator.png
  :alt: Registered MFA methods
  :align: center
  :width: 90%
  :::

- Choose whichever you prefer to be your **Default sign-in method**.

::::

#### {{iphone}} Alternate authenticator app

::::{admonition} 1. Download an authenticator app
:class: dropdown note

- Choose an authenticator app that supports **time-based one-time password (TOTP)**.
- One example is **Google Authenticator**.

    :::{important}
    You must give permission for the authenticator app to send you notifications for the app to work as an MFA method.
    :::

::::

::::{admonition} 2. Add sign-in method
:class: dropdown note

- Click on **{guilabel}`+ Add sign-in method`** and select **Authenticator app**.

    :::{image} images/account_setup_mfa_add_authenticator_app.png
    :alt: Add Authenticator app
    :align: center
    :width: 90%
    :::

- At the **Getting the app** click on **I want to use a different authenticator app**.

    :::{image} images/account_setup_mfa_choose_authenticator_app.png
    :alt: Add Authenticator app
    :align: center
    :width: 90%
    :::

- Open your authenticator app

::::

::::{admonition} 3. Register your app
:class: dropdown note

- Follow the steps in your authenticator app to add a new account
- At the on-screen prompt click on **{guilabel}`Next`**.

    :::{image} images/account_setup_mfa_totp_allow_notifications.png
    :alt: Allow authenticator notifications
    :align: center
    :width: 90%
    :::

- The next prompt will give you a QR code to scan, like the one shown below
- Scan the QR code on the screen then click **{guilabel}`Next`**

    :::{image} images/account_setup_mfa_totp_app_qrcode.png
    :alt: Setup Authenticator app
    :align: center
    :width: 90%
    :::

- Once this is completed, Microsoft will send you a test notification to respond to

    :::{image} images/account_setup_mfa_totp_authenticator_app_test.png
    :alt: Authenticator app test notification
    :align: center
    :width: 90%
    :::

- When you click **{guilabel}`Approve`** on the phone notification, you will get the following message in your browser

    :::{image} images/account_setup_mfa_totp_authenticator_app_approved.png
    :alt: Authenticator app test approved
    :align: center
    :width: 90%
    :::

::::

::::{admonition} 4. Check the Security Information dashboard
:class: dropdown note

- You should now be returned to the Security Information dashboard that shows the **Authenticator app** method.

    :::{image} images/account_setup_mfa_dashboard_totp_authenticator.png
    :alt: Registered MFA methods
    :align: center
    :width: 90%
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
