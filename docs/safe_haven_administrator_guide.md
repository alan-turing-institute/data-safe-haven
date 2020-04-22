# Safe Haven Administrator Documentation

## :mailbox_with_mail: Table of contents

- [:seedling: Prerequisites](#seedling-prerequisites)
- [:beginner: Creating new users](#beginner-creating-new-users)
  - [:scroll: Generating CSV file using data classification app](#scroll-generating-csv-file-using-data-classification-app)
  - [:scroll: Generating CSV file manually](#scroll-generating-csv-file-manually)
  - [:fast_forward: Optional: Add group name](#fast_forward-optional-add-group-name)
  - [:arrows_counterclockwise: Create and synchronise users](#arrows_counterclockwise-create-and-synchronise-users)
  - [:microscope: Troubleshooting: Account already exists](#microscope-troubleshooting-account-already-exists)
  - [:calling: Assign an MFA licence](#calling-assign-an-mfa-licence)
  - [:running: User activation](#running-user-activation)

## :seedling: Prerequisites
This document assumes that you have already deployed a [Safe Haven Management (SHM) environment](deploy_shm_instructions.md) and one or more [Secure Research Environments (SRE)](deploy_sre_instructions.md) that are linked to it.

- You will need VPN access to the SHM as described in the deployment instructions


# :beginner: Creating new users

Users should be created on the main domain controller (DC1) in the SHM and synchronised to Azure Active Directory.
A helper script for doing this is already uploaded to the domain controller - you will need to prepare a CSV file in the appropriate format for it.

## :scroll: Generating CSV file using data classification app
- Follow the [instructions in the webapp repository](https://github.com/alan-turing-institute/data-safe-haven-webapp/blob/master/runbooks/create-users/create-users.md) to create users.
  - Users can be created in bulk by selecting `Create User > Import user list` and uploading a spreadsheet of user details
  - Users can also be created individually by selecting `Create User > Create Single User`
- After creating users, export the `UserCreate.csv` file
  - To export all users, select `Users > Export UserCreate.csv`
  - To export only users for a particular project, select `Projects > (Project Name) > Export UserCreate.csv`

## :scroll: Generating CSV file manually
- Make a new copy of the user details template file from `deployment/safe_haven_management_environment/user_details.csv`
  - :pencil: we suggest naming this `YYYYDDMM-HHMM_user_details.csv` but this is up to you
- Add the required details for each user
  - `SamAccountName`: Log in username **without** the @domain bit. Use `firstname.lastname` format. Maximum length is 20 characters.
  - `GivenName`: User's first / given name
  - `Surname`: User's last name / surname
  - `Mobile`: Phone number to use for initial password reset.
    This must include country code in the format `+<country-code> <local number>`.
    Include a space between the country code and local number parts but no other spaces.
    Remove the leading `0` from local number if present.
    This can be a landline or or mobile but must be accessible to the user when resetting their password and setting up MFA.
    They can add the authenticator app and / or another phone number during MFA setup and at least one MFA method must work when at the Turing.
  - `SecondaryEmail`: An existing organisational email address for the user.
    Not uploaded to their Safe Haven user account but needs to be added here so we reliably send the account activation

## :fast_forward: Optional: Add group name
If you know which groups each user will be added to, you can also include the following column:
  - `GroupName`: The name of the Azure security group that the users should be added (eg. `SG SANDBOX Research Users`)

## :arrows_counterclockwise: Create and synchronise users
Upload the user details CSV file to a sensible location on the SHM domain controller (eg. `C:\Installation`).
On the **SHM domain controller (DC1)**.
- Open a PowerShell command window with elevated privileges.
- Run `C:\Installation\CreateUsers.ps1 <path_to_user_details_file>`
- This script will add the users and trigger a sync with Azure Active Directory, but it will still take around 5 minutes for the changes to propagate.

### :microscope: Troubleshooting: Account already exists
If you get the message `New-ADUser :  The specified account already exists` you should first check to see whether that user actually does already exist!
Once you're certain that you're adding a new user, make sure that the following fields are unique across all users in the Active Directory.
- `SamAccountName`: Specified explicitly in the CSV file. If this is already in use, consider something like `firstname.middle.initials.lastname`
- `DistinguishedName`: Formed of `CN=<DisplayName>,<OUPath>` by Active directory on user creation. If this is in use, consider changing `DisplayName` from `<GivenName> <Surname>` to `<GivenName> <Middle> <Initials> <Surname>`.

## :calling: Assign an MFA licence
- Login into the Azure Portal and connect to the correct AAD subscription
- Open `Azure Active Directory`
- Location `Licenses` under `Manage` section
- Open `All Products` under `Manage`
- Click `Azure Active Directory Premium P1`
- Click `Assign`
- Click `Users and groups`
- Select the users you have recently created and click `Select`
- Click `Assign` to complete the process
- Return to `Azure Active Directory` pane
- Click `Users` from `Manage` section
- Click `Multi-Factor Authentication` button
- Check the box for the users you want to apply MFA to
- Click the `Enable` link in the `Quick steps` block on the right and confirm in the pop-up
- Close MFA console
- Users are now ready to reset password and set up MFA

## :running: User activation
We need to contact the users to tell them their user ID and.
We can securely email users their user ID as they do not know their account password and they need access to the phone number they provided in order to reset this.
We should also send them a copy of the [Safe Haven User Guide](safe_haven_user_guide.md) at this point.

A sample email might look like the following

> Dear \<participant name\>,
>
> Welcome to \<event name\>! You've been given access to a data Safe Haven running on Turing infrastructure.
> Please find a PDF version of our user guide attached.
> You should start by following the instructions about setting up your account and enabling multi-factor authentication (MFA).
>
> Your username is: \<username@domain\>
> Your Safe Haven is hosted at: \<URL\>
>
> The Safe Haven is only accessible from certain networks and may also involve physical location restrictions.
> <details about network and location/VPN restrictions here>
