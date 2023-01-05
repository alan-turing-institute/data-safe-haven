These steps ensure that you have created a non-privileged user account that you can use for testing.
You must ensure that you have assigned a licence to this user in the Azure Active Directory so that MFA will work correctly.

You should have already set up a non-privileged user account upon setting up the SHM, when {ref}`validating the active directory synchronisation <deploy_shm>`, but you may wish to set up another or verify that you have set one up already:

<details>
<summary><strong>Set up a non-privileged user account</strong></summary>

![Remote: five minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=five%20minutes)

- Log into the **SHM primary domain controller** (`DC1-SHM-<SHM ID>`) VM using the connection details that you previously used to {ref}`log into this VM <roles_system_deployer_shm_remote_desktop>`.
- Follow the user creation instructions from the {ref}`SHM deployment guide <deploy_shm>` (everything under the `Validate Active Directory synchronisation` header). In brief these involve:
  - adding your details (ie. your first name, last name, phone number etc.) to a user details CSV file.
  - running `C:\Installation\CreateUsers.ps1 <path_to_user_details_file>` in a Powershell command window with elevated privileges.
- This will create a user in the local Active Directory on the SHM domain controller and start the process of synchronisation to the Azure Active Directory, which will take around 5 minutes.

</details>

<details>
<summary><strong>Ensure that your non-privileged user account is in the correct Security Group</strong></summary>

![Remote: five minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=five%20minutes)

- Log into the **SHM primary domain controller** (`DC1-SHM-<SHM ID>`) VM using the connection details that you previously used to {ref}`log into this VM <roles_system_deployer_shm_remote_desktop>`.
- In Server Manager click `Tools > Active Directory Users and Computers`
- In `Active Directory Users and Computers`, expand the domain in the left hand panel click `Safe Haven Security Groups`
- Right click the `SG <SRE ID> Research Users` security group and select `Properties`
- Click on the `Members` tab.
- If your user is not already listed here you must add them to the group
  - Click the `Add` button
  - Enter the start of your username and click `Check names`
  - Select your username and click `Ok`
  - Click `Ok` again to exit the `Add users` dialogue
- Synchronise with Azure Active Directory by running following the `Powershell` command on the SHM primary domain controller

```powershell
PS> C:\Installation\Run_ADSync.ps1
```

### {{closed_lock_with_key}} Ensure that your non-privileged user account has MFA enabled

Switch to your custom Azure Active Directory in the Azure portal and make the following checks:

![Azure AD: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=one%20minute)

- From the Azure portal, navigate to the AAD you have created.
- The `Usage Location` must be set in Azure Active Directory (should be automatically synchronised from the local Active Directory if it was correctly set there)
  - Navigate to `Azure Active Directory > Manage / Users > (user account)`, and ensure that `Settings > Usage Location` is set.
- A licence must be assigned to the user.
  - Navigate to `Azure Active Directory > Manage / Users > (user account) > Licenses` and verify that a license is assigned and the appropriate MFA service enabled.
