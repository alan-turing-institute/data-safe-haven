# Administrator documentation

## {{seedling}} Prerequisites

This document assumes that you already have access a {ref}`Safe Haven Management (SHM) environment <deploy_shm>` and one or more {ref}`Secure Research Environments (SREs) <deploy_sre>` that are linked to it.

- You will need VPN access to the SHM as described in the deployment instructions

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

```{include} ../system_deployer/snippets/user_csv_format.partial.md
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

## {{dollar}} Cost management

When and SHM and/or SRE is not being used, it can be cost-efficient to shut it down in order to save on some of the ongoing running costs.

## {{point_down}} Shut down an SHM or SRE

Sometimes you may want to temporarily shut down an SHM or SRE, rather than tearing it down entirely.
You can do that with these scripts:

On your **deployment machine**.

- Ensure you have the same version of the Data Safe Haven repository as was used by your deployment team
- Open a `Powershell` terminal and navigate to the `deployment/administration` directory within the Data Safe Haven repository
- Then do one or both of the following:

````{admonition} Shut down SHM
```powershell
PS> ./SHM_Manage_VMs.ps1 -shmId <shm id> -Action EnsureStopped -Group All
```
````

````{admonition} Shut down SRE
```powershell
./SRE_Manage_VMs.ps1 -shmId <shm id> -sreId <sre id> -Action EnsureStopped
```
````

## {{boot}} Start up an SHM or SRE

If you need to reboot an SHM or SRE that is not running, you can use the same scripts youused to shut them down, but changing the `-Action` flag to `EnsureStopped`, see below.

On your **deployment machine**.

- Ensure you have the same version of the Data Safe Haven repository as was used by your deployment team
- Open a `Powershell` terminal and navigate to the `deployment/administration` directory within the Data Safe Haven repository
- Run `./SHM_Manage_VMs.ps1 -shmId <shm id> -Action EnsureStarted -Group All` to restart the SHM
- For each SRE, run `./SRE_Manage_VMs.ps1 -shmId <shm id> -sreId <sre id> -Action EnsureStarted`

```{warning}
If the Azure subscription that you have deployed into runs out of credit, the SHM and/or SRE will be shutdown automatically.
```

## {{package}} Updating proxy package allowlists

When the Nexus repository is deployed the full allowlists present in
`environment_configs/package_lists/` will be used for configuration. For a
{ref}`policy_tier_2` proxy these will be ignored and all packages on PyPI and
CRAN may be installed on linked SREs. For a {ref}`policy_tier_3` proxy only the
packages named in these lists may be installed.

To update the allowlists and Nexus configuration on an SHM, you may use the
`/deployment/administration/SHM_Update_Nexus_Allowlists.ps1` script.

```powershell
PS> /deployment/administration/SHM_Update_Nexus_Allowlists.ps1 -shmId <SHM ID>
```

By default, this script will use the allowlists present in
`environment_configs/package_lists/` but you may use the `-allowlistDirectory`
option to specify another directory containing the allowlists. It is assumed
that the allowlists will have the same names as those in in
`environment_configs/package_lists/`.

## {{anger}} Tear down SHM package mirrors

During normal usage of the SHM, you should not need to tear down the package mirrors.
However, if you no longer have any SREs at a particular tier and you want to save on the costs of running the mirrors, you might decide to do so.

On your **deployment machine**.

- Ensure you have the same version of the Data Safe Haven repository as was used by your deployment team
- Open a `Powershell` terminal and navigate to the `deployment/safe_haven_management_environment/setup` directory within the Data Safe Haven repository
- Ensure you are logged into `Azure` within `Powershell` using the command: `Connect-AzAccount`. This command will give you a URL and a short alphanumeric code. You will need to visit that URL in a web browser and enter the code
  - NB. If your account is a guest in additional Azure tenants, you may need to add the `-Tenant <Tenant ID>` flag, where `<Tenant ID>` is the ID of the Azure tenant you want to deploy into.
- Tear down the package mirrors by running `./Teardown_SHM_Package_Mirrors.ps1 -shmId <SHM ID> -tier <desired tier>`, where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` specified in the configuration file
- This will take **a few minutes** to run

## Ingress and Egress

(roles_system_manager_data_ingress)=

### Data Ingress

It is the data provider's responsibility to upload the data required by the safe haven.

```{important}
Any data ingress must be signed off by the {ref}`role_data_provider_representative`, {ref}`role_investigator` and {ref}`role_referee` (if applicable).
```

The following steps show how to generate a temporary write-only upload token that can be securely sent to the data provider, enabling them to upload the data:

- In the Azure portal select `Subscriptions` then navigate to the subscription containing the relevant SHM
- Search for the resource group: `RG_SHM_<SHM ID>_PERSISTENT_DATA`, then click through to the storage account called: `<SHM ID><SRE ID>data<storage suffix>` (where `<storage suffix>` is a random string)
- Click `Networking` under `Settings` and paste the data providers IP address as one of those allowed under the `Firewall` header, then hit the save icon in the top left
- From the `Overview` tab, click the link to `Containers` (in the middle of the page)
- Click `ingress`
- Click `Shared access signature` under `Settings` and do the following:
  - Under `Permissions`, check these boxes:
    - `Write`
    - `List`
  - Set a 24 hour time window in the `Start and expiry date/time` (or an appropriate length of time)
  - Leave everything else as default click `Generate SAS token and URL`
  - Copy the `Blob SAS URL`
- Send the `Blob SAS URL` to the data provider via secure email (for example, you could use the [Egress secure email](https://www.egress.com/) service)
- The data provider should now be able to upload data by following {ref}`these instructions <role_data_provider_representative_ingress_upload>`
- You can validate successful data ingress by logging into the SRD for the SRE and checking the `/data` volume, where you should be able to view the data that the data provider has uploaded

(roles_system_manager_software_ingress)=

### Software Ingress

Software ingress is performed in a similar manner to data.

```{important}
Software ingress must go through the same {ref}`approval policy <policy_security_package_approval>` as is the case for data ingress, including sign-off from the {ref}`role_data_provider_representative`, {ref}`role_investigator` and {ref}`role_referee` (if applicable).
```

- Follow the same steps as for {ref}`data ingress <roles_system_manager_data_ingress>` above to provide temporary write access, but set the time window for the SAS token to a shorter period (e.g. several hours)
- Share the token with the {ref}`role_investigator`, so they can install software within the time window
- The {ref}`role_investigator` can perform software ingress via `Azure Storage Explorer` (for instance as a zip file), by following the same instructions as {ref}`the data provider <role_data_provider_representative_ingress>`

(roles_system_manager_data_egress)=

### Data egress

- In the Azure portal select `Subscriptions` then navigate to the subscription containing the relevant SHM
- Search for the resource group: `RG_SHM_<SHM ID>_PERSISTENT_DATA`, then click through to the storage account called: `<SHM ID><SRE ID>data<storage suffix>` (where `<storage suffix>` is a random string)
- Click `Networking` under `Settings` to check the list of pre-approved IP addresses allowed under the `Firewall` header and check your own IP address to ensure you are connecting from one of these
- Click `Containers` under `Data storage`
- Click `egress`
- Click `Shared access signature` under `Settings` and do the following:
  - Under `Permissions`, check these boxes:
    - `Read`
    - `List`
  - Set a time window in the `Start and expiry date/time` that gives you enough time to extract the data
  - Leave everything else as default click `Generate SAS token and URL`

    ```{image} administrator_guide/read_only_sas_token.png
    :alt: Read-only SAS token
    :align: center
    ```

  - Leave this portal window open and move to the next step
- Open `Azure Storage Explorer` ([download](https://azure.microsoft.com/en-us/features/storage-explorer/) it if you don't have it)
- Click the socket image on the left hand side

  ```{image} ../data_provider_representative/azure_storage_explorer_connect.png
  :alt: Azure Storage Explorer connection
  :align: center
  ```

- On `Select Resource`, choose `Blob container`
- On `Select Connection Method`, choose `Shared access signature URL (SAS)` and hit `Next`

  ```{image} administrator_guide/connect_azure_storage.png
  :alt: Connect with SAS token
  :align: center
  ```

- On `Enter Connection Info`:
  - Set the `Display name` to "egress" (or choose an informative name)
  - Copy the `Blob SAS URL` from your Azure portal session into the `Blob container SAS URL` box and hit `Next`
- On the `Summary` page, hit `Connect`
- On the left hand side, the connection should show up under `Local & Attached > Storage Accounts > (Attached Containers) > Blob Containers > ingress (SAS)`
- You should now be able to securely download the data from the Safe Haven's output volume by highlighting the relevant file(s) and hitting the `Download` button

#### The output volume

Once you have set up the egress connection in `Azure Storage Explorer`, you should be able to view data from the **output volume**, a read-write area intended for the extraction of results, such as figures for publication.
On the SRD, this volume is `/output` and is shared between all SRDs in an SRE.
For more info on shared SRE storage volumes, consult the {ref}`Safe Haven User Guide <role_researcher_user_guide_shared_storage>`.

## {{file_cabinet}} Backup

### {{card_file_box}} Restoring Blobs

Blob containers in backed up storage accounts are protected by [operational backup](https://docs.microsoft.com/en-us/azure/backup/blob-backup-overview#how-operational-backup-works).
It is possible to restore the state of the blobs to an earlier point in time, up to twelve weeks in the past.

The blob containers covered by the protection for each SRE are the

- ingress container (mounted at `/data`)
- egress container (mounted at `/output`)
- backup container (mounted at `/backup`)

To restore these containers to a previous point in time:

```{important}
Blobs are restored 'in place'.
The current state will be overwritten by the point which you restore to.
```

- In the Azure portal select `Subscriptions` then navigate to the subscription containing the relevant SRE
- Search for the resource group: `RG_SHM_<SHM ID>_SRE_<SRE ID>_BACKUP`, then click on the storage account called: `bv-<shm id>-sre-<sre id>`
- Click `Backup instances` under `Manage` in the left-hand menu
- Ensure that the `Datasource type` filter is set to `Azure Blobs (Azure Storage)`

  ```{image} administrator_guide/backup_instances_blobs.png
  :alt: Selecting blob backup instances
  :align: center
  ```

- Click on the storage-account backup instance
- Select a point in the past to restore to and click `Restore`

  ```{image} administrator_guide/backup_select_restore_time_blobs.png
  :alt: Selecting blob backup restore point
  :align: center
  ```

- Click on `Next: Restore Parameters`
- You can now choose whether to restore all, or a subset of the containers. In the example below the 'egress' and 'backup' containers are selected
- Click on `Validate`

  ```{image} administrator_guide/backup_select_containers_validate_blobs.png
  :alt: Selecting blob containers to restore and validating
  :align: center
  ```

- Click on `Next: Review + restore`
- Click on `Restore`

### {{optical_disk}} Restoring Disks

Backed up disks have incremental snapshots taken daily.
These snapshots are stored in the backup resource group,`RG_SHM_<SHM ID>_SRE_<SRE ID>_BACKUP`.

The disks covered by the protection for each SRE are the

- GitLab data disk
- CodiMD data disk
- CoCalc data disk
- PostgreSQL data disk
- MSSQL data disk

To restore a disk:

```{important}
Restoring a disk creates a new disk object from the incremental snapshots.
You will need to specify where to create the disk and its name.
You will also need to attach the disk to any virtual machines which should use
it and enroll the new disk into the backup system.
```

- In the Azure portal select `Subscriptions` then navigate to the subscription containing the relevant SRE
- Search for the resource group: `RG_SHM_<SHM ID>_SRE_<SRE ID>_BACKUP`, then click on the storage account called: `bv-<shm id>-sre-<sre id>
- Click `Backup instances` under `Manage` in the left-hand menu
- Ensure that the `Datasource type` filter is set to `Azure Disks`

  ```{image} administrator_guide/backup_instances_disks.png
  :alt: Selecting disk backup instances
  :align: center
  ```

- Click on the disk to restore
- Click `Restore`
- Click `Select restore point` to choose which snapshot to revert to and click `Select`. By default only snapshots from the last 30 days are displayed but this can be adjusted
- Click `Next: Restore Parameters`
- Enter the subscription and resource group in which to create the new disk; these should match the original disk
- Enter a name for the new disk and click `Validate`

  ```{image} administrator_guide/backup_select_snapshot_validate_disks.png
  :alt: Configuring and validating disk backup
  :align: center
  ```

- Click on `Next: Review + restore`
- Click on `Restore`
- Wait for the restoration to finish. You can monitor the progress on the backup instance page on the Azure portal

  ```{image} administrator_guide/backup_progress_disk_1.png
  :align: center
  ```

  ```{image} administrator_guide/backup_progress_disk_2.png
  :align: center
  ```

  ```{image} administrator_guide/backup_progress_disk_3.png
  :align: center
  ```

- Navigate to the resource group where the new disk has been created
- Select the virtual machine the old disk is attached to and click `Disks` in the left-hand menu
- Take note of the old disks 'LUN'
- Remove the old disk be clicking the 'X' at the righ-hand side of the disk table
- Click `Save`
- Click `Attach existing disks` and selected the disk you restored
- Ensure the restored disk has the same 'LUN' as the old disk
- Click `Save`

  ```{image} administrator_guide/backup_swap_disk_before.png
  :alt: The state before swapping in the restored disk
  :align: center
  ```

  ```{image} administrator_guide/backup_swap_disk_after.png
  :alt: The state after swapping in the restored disk
  :align: center
  ```

- Restart the virtual machine

## {{end}} Remove a deployed Safe Haven

### {{fire}} Tear down an SRE

In order to tear down an SRE, use the following procedure:

On your **deployment machine**.

- Ensure you have the same version of the Data Safe Haven repository as was used by your deployment team
- Open a `Powershell` terminal and navigate to the `deployment/administration` directory within the Data Safe Haven repository
- Ensure you are logged into `Azure` within `Powershell` using the command: `Connect-AzAccount`. This command will give you a URL and a short alphanumeric code. You will need to visit that URL in a web browser and enter the code
  - NB. If your account is a guest in additional Azure tenants, you may need to add the `-Tenant <Tenant ID>` flag, where `<Tenant ID>` is the ID of the Azure tenant you want to deploy into.
  - Run the following script:

    ```powershell
    ./SRE_Teardown.ps1 -shmId <SHM ID> -sreId <SRE ID>
    ```

  - If you provide the optional `-dryRun` parameter then the names of all affected resources will be printed, but nothing will be deleted

### {{bomb}} Tear down the SHM

In order to tear down the SHM, use the following procedure (you may skip the tearing down of package mirrors, unless this is the specific thing you wanted to do):

#### {{unlock}} Disconnect from the Azure Active Directory

Connect to the **SHM Domain Controller (DC1)** via Remote Desktop Client over the SHM VPN connection

- Log in as a **domain** user (ie. `<admin username>@<SHM domain>`) using the username and password obtained from the Azure portal
- If you see a warning dialog that the certificate cannot be verified as root, accept this and continue
- Open Powershell as an administrator
  - Navigate to `C:\Installation`
  - Run `.\Disconnect_AD.ps1`
  - You will need to provide login credentials (including MFA if set up) for `<admin username>@<SHM domain>`

```{attention}
Full disconnection of the Azure Active Directory can take up to 72 hours but is typically less.
If you are planning to install a new SHM connected to the same Azure Active Directory you may find the `AzureADConnect` installation step requires you to wait for the previous disconnection to complete.
```

#### {{collision}} Tear down any attached SREs then the SHM

On your **deployment machine**.

- Ensure you have the same version of the Data Safe Haven repository as was used by your deployment team
- Open a `Powershell` terminal and navigate to the `deployment/administration` directory within the Data Safe Haven repository
- Ensure you are logged into `Azure` within `Powershell` using the command: `Connect-AzAccount`. This command will give you a URL and a short alphanumeric code. You will need to visit that URL in a web browser and enter the code

  ```{attention}
  If your account is a guest in additional Azure tenants, you may need to add the `-Tenant <Tenant ID>` flag, where `<Tenant ID>` is the ID of the Azure tenant you want to deploy into.
  ```

- For each SRE attached to the SHM, do the following:
  - Tear down the SRE by running:

    ```powershell
    ./SRE_Teardown.ps1 -sreId <SRE ID>
    ```

    where the SRE ID is the one specified in the relevant config file

    ```{note}
    If you provide the optional `-dryRun` parameter then the names of all affected resources will be printed, but nothing will be deleted
    ```

- Tear down the SHM by running:

  ```powershell
  ./SHM_Teardown.ps1 -shmId <SHM ID>
  ```

  where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` specified in the configuration file.
