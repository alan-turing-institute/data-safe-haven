(administrator_manage_users)=

# Managing Data Safe Haven users

```{important}
This document assumes that you already have access to a {ref}`Safe Haven Management (SHM) environment <deploy_shm>` and one or more {ref}`Secure Research Environments (SREs) <deploy_sre>` that are linked to it.
```

## {{beginner}} Create new users

Users should be created on the main domain controller (DC1) in the SHM and synchronised to Azure Active Directory.
A helper script for doing this is already uploaded to the domain controller - you will need to prepare a `CSV` file in the appropriate format for it.

## {{scroll}} Generate user details CSV file

### {{car}} Using data classification app

- Follow the [instructions in the classification app documentation](https://github.com/alan-turing-institute/data-classification-app) to create users
  - Users can be created in bulk by selecting `Create User > Import user list` and uploading a spreadsheet of user details
  - Users can also be created individually by selecting `Create User > Create Single User`
- After creating users, export the `UserCreate.csv` file
  - To export all users, select `Users > Export UserCreate.csv`
  - To export only users for a particular project, select `Projects > (Project Name) > Export UserCreate.csv`
- Upload the user details CSV file to a sensible location on the SHM domain controller

  ```{note}
  We suggest using `C:\Installation\YYYYDDMM-HHMM_user_details.csv` but this is up to you
  ```

### {{hand}} Manually edit CSV

On the **SHM domain controller (DC1)**.

```{include} ../../deployment/snippets/user_csv_format.partial.md
:relative-images:
```

## {{arrows_counterclockwise}} Create and synchronise users

Upload the user details `CSV` file to a sensible location on the SHM domain controller (recommended: `C:\Installation`).
This can be done by copying and pasting the file from your deployment device to the SHM DC.

- Log into the **SHM primary domain controller** (`DC1-SHM-<SHM ID>`) VM using the login credentials {ref}`stored in Azure Key Vault <roles_system_deployer_shm_remote_desktop>`
- Open a `Powershell` command window with elevated privileges
- Run `C:\Installation\CreateUsers.ps1 <path_to_user_details_file>`
- This script will add the users and trigger synchronisation with Azure Active Directory
- It will still take around 5 minutes for the changes to propagate

```{error}
If you get the message `New-ADUser : The specified account already exists` you should first check to see whether that user actually does already exist!
Once you're certain that you're adding a new user, make sure that the following fields are unique across all users in the Active Directory.

- `SamAccountName`
  - Specified explicitly in the `CSV` file.
  - If this is already in use, consider something like `firstname.middle.initials.lastname`
- `DistinguishedName`
  - Formed of `CN=<DisplayName>,<OUPath>` by `Active Directory` on user creation.
  - If this is in use, consider changing `DisplayName` from `<GivenName> <Surname>` to `<GivenName> <middle initials> <Surname>` .
```

```{danger}
- These domain administrator credentials have complete control over creating and deleting users as well as assigning them to groups
- Do not use them except where specified and never write them down!
- Be particularly careful never to use them to log in to any user-accessible VMs (such as the SRDs)
```

## {{calling}} Assign MFA licences

### {{hand}} Manually add licence to each user

- Login into the Azure Portal and connect to the correct AAD
- Open `Azure Active Directory`
- Select `Manage > Licenses > All Products`
- Click `Azure Active Directory Premium P1`
- Click `Assign`
- Click `Users and groups`
- Select the users you have recently created and click `Select`
- Click `Assign` to complete the process

### {{car}} Automatically assign licences to users

To automatically assign licences to all local `Active Directory` users that do not currently have a licence in `Azure Active Directory`.

- Ensure you have the same version of the Data Safe Haven repository as was used by your deployment team
- Open a `Powershell` terminal and navigate to the `deployment/administration` directory within the Data Safe Haven repository
- Run the `./SHM_Add_AAD_Licences.ps1 -tenantId <Tenant ID>` script, where `<Tenant ID>` is the ID of the Azure tenant belonging to the SHM you want to add the licences to

## {{running}} User activation

We recommend using email to send connection details to new users.

```{note}
This is not a security risk since:
- we are not sending passwords in this email
- the user needs access to their previously-provided phone number in order to set their account password and MFA
```

A sample email might look like the following

> Dear \<participant name\>,
>
> Welcome to \<event name\>! You've been given access to a Data Safe Haven managed by \<organisation name\>.
> Please find a PDF version of our user guide attached.
> You should start by following the instructions about setting up your account and enabling multi-factor authentication (MFA).
>
> Your username is: \<username@domain\>
> Your Safe Haven is hosted at: \<URL\>
>
> The Safe Haven is only accessible from certain networks and may also involve physical location restrictions.
>
> --details about network and location/VPN restrictions here--

## {{construction_worker}} Common user problems

One of the most common user issues is that they are unable to log in to the environment.
Here we go through the login procedure and discuss possible problems at each step

### {{waning_crescent_moon}} Expired webclient certificate

If the certificate for the SRE domain has expired, users will not be able to login.

```{image} administrator_guide/login_certificate_expiry.png
:alt: Login failure - expired certificate
:align: center
```

```{tip}
**Solution**: Replace the SSL certificate with a new one

- Ensure you have the same version of the Data Safe Haven repository as was used by your deployment team
- Open a `Powershell` terminal and navigate to the `deployment/secure_research_environment/setup` directory within the Data Safe Haven repository
- Ensure you are logged into the `Azure` within `Powershell` using the command: `Connect-AzAccount`
- Run `./Update_SRE_RDS_Ssl_Certificate.ps1 -sreId <SRE ID>`, where the SRE ID is the one specified in the config
```

### {{red_circle}} Unable to log into remote desktop gateway

If users give the wrong username or password they will not be able to progress past the login screen.

```{image} administrator_guide/login_password_login.png
:alt: Login failure - wrong password
:align: center
```

```{tip}
**Solution**: Check user credentials, password may need to be reset.
```

### {{train}} Unable to open any remote apps

Users are stuck at the `Opening remote port` message and never receive the MFA prompt.

```{image} administrator_guide/srd_login_opening_port.png
:alt: Login failure - no MFA prompt
:align: center
```

```{tip}
**Solution**: Check MFA setup

- Ensure that the user has been assigned a license in Azure Active Directory
- Check that the user has set up MFA (at [https://aka.ms/mfasetup](https://aka.ms/mfasetup) ) and is using the phone-call or app authentication method
```

### {{interrobang}} xrdp login failure on the SRD

If users can get to the login screen:

```{image} administrator_guide/srd_login_prompt.png
:alt: SRD login screen
:align: center
```

but then see this error message:

```{image} administrator_guide/srd_login_failure.png
:alt: SRD login failure
:align: center
```

there are a couple of possible causes.

```{error}
**Problem**: the username or password was incorrectly entered

**Solution**: check username and password

- Confirm that the username and password have been correctly typed
- Confirm that there are no unsupported special characters in the password
- Reset the account if there is no other solution
```

```{error}
**Problem**: the computer is unable to communicate with the login server

**Solution**: run diagnostics

- This can happen for a variety of reasons (DNS problems, broken services on the SRD etc.)
- Run the script under `deployment/administration/SRE_SRD_Remote_Diagnostics.ps1`, providing the group and last IP octet of the problematic SRD
- This will run a series of diagnostics intended to fix some common problems including
  - LDAP configuration
  - DNS configuration
  - SSS configuration
  - File mounting configuration
```

### {{cloud}} Unable to install from package mirrors

If it is not possible to install packages from the package mirrors then this may be for one of the following reasons:

```{error}
**Problem**: Mirror VNet is not correctly peered

**Solution**: Re-run the network configuration script.

On your **deployment machine**.

- Ensure you have the same version of the Data Safe Haven repository as was used by your deployment team
- Open a `Powershell` terminal and navigate to the `deployment/secure_research_environment/setup` directory within the Data Safe Haven repository
- Ensure you are logged into `Azure` within `Powershell` using the command: `Connect-AzAccount`
  - NB. If your account is a guest in additional Azure tenants, you may need to add the `-Tenant <Tenant ID>` flag, where `<Tenant ID>` is the ID of the Azure tenant you want to deploy into.
- Run the `./Apply_Network_Configuration.ps1 -sreId <SRE ID>` script, where the SRE ID is the one specified in the config
```

````{error}
**Problem**: Internal mirror does not have the required package

**Solution**: Check package availability

To diagnose this, log into the `Internal` mirror using the Serial Console through the `Azure` portal.
Check the packages directory (i.e. `/datadrive/mirrordaemon/pypi/web/packages` for PyPI or `/datadrive/mirrordaemon/www/cran` for CRAN)

```{image} administrator_guide/internal_mirror_packages.png
:alt: Internal mirror package list
:align: center
````

If the requested package **should** be available (i.e. it is on the appropriate allowlist), then you can force a mirror update by rebooting the `EXTERNAL` mirrors.
This will trigger the following actions:

1. Synchronisation of the external mirror with the remote, internet repository (a `pull` update)
2. Synchronisation of the internal mirror with the external mirror (a `push` update)

This may take an hour or two but should solve the missing package problem.
