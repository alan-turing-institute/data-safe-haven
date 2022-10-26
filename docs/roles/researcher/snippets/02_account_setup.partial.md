## {{rocket}} Set up your account

This section of the user guide will help you set up your new account on the SRE you'll be using.

### {{seedling}} Prerequisites

Make sure you have all of the following in front of you when connecting to the SRE.

- {{email}} The email from your {ref}`System Manager <role_system_manager>` with your account details.
- {{wrench}} Your [username](#username), given in an email from your {ref}`System Manager <role_system_manager>`.
- {{european_castle}} The [domain name and URL](#domain-names) for the SRE, given in an email from your {ref}`System Manager <role_system_manager>`.
- {{computer}} Your computer.
- {{satellite}} [Access](#network-access) to the specific wired or wireless network detailed in the email from your {ref}`System Manager <role_system_manager>`.
- {{lock}} [Data security training](#data-security-training-requirements) for those working on health datasets.
- {{iphone}} Your [phone](#your-phone-for-multi-factor-authentication), with good signal connectivity.

You should also know who the **designated contact** for your SRE is.
This might be an administrator or one of the people working on the project with you.
They will be your primary point of contact if you have any issues in connecting to or using the SRE.

```{note}
For example, during the Turing Data Study Groups, the **facilitator** of each SRE is the designated contact
```

#### Username

Your username will usually be in the format `firstname.lastname`.
In some places, you will need to enter it in the form `username@<username domain>`

```{tip}
You can find your username in the email you received from your {ref}`System Manager <role_system_manager>`.
```

```{caution}
If you have a hyphenated last name, or multiple surnames, or a long family name, your assigned username may not follow the same pattern of `firstname.lastname`.
Please check with the designated contact for your SRE if you are unsure about your username.
```

```{note}
In this document we will use **Ada Lovelace** as our example user.
Her username is:
- short-form: `ada.lovelace`
- long-form: `ada.lovelace@projects.turingsafehaven.ac.uk`
```

#### Network access

The SRE that you're using may be configured to allow access only from a specific set of IP addresses.
This may involve being connected to a specific wired or wireless network or using a VPN.
You also may be required to connect from a specific, secure location.
You will be told what these requirements are for your particular environment.

```{tip}
Make sure you know the networks from which you must connect to your SRE.
This information will be available in the email you received with your connection information.
```

#### Data security training requirements

Depending on your project, you may be required to undertake {ref}`data security awareness training <process_data_security_training>`.

```{tip}
Check with your designated contact to see whether this is the case for you.
```

#### Your phone for multi-factor authentication

Multi-factor authentication (MFA) is one of the most powerful ways of verifying user identity online.
We therefore use MFA to protect the project data - specifically, we will use your phone number.

```{important}
Make sure to have your phone with you and that you have good signal connectivity when you are connecting to the SRE.
```

```{caution}
You may encounter some connectivity challenges if your phone network has poor connectivity.
The SRE is not set up to allow you to authenticate through other methods.
```

#### Domain names

You should be given the {ref}`username domain <user_guide_username_domain>` in the initial email from your {ref}`System Manager <role_system_manager>`.
You might receive the {ref}`SRE URL <user_guide_sre_url>` at this time, or you might be assigned to a particular SRE at a later point.

```{note}
In this document Ada Lovelace - our example user - will be participating in the `sandbox` project at a Turing Data Study Group.
- Her **{ref}`username domain <user_guide_username_domain>`** is `projects.turingsafehaven.ac.uk` .
- Her **{ref}`SRE URL <user_guide_sre_url>`** is `https://sandbox.projects.turingsafehaven.ac.uk`
```

### {{closed_lock_with_key}} Set a password

```{include} 15_MFA.partial.md
:relative-images:
```
