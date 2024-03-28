(deploy_shm)=

# Deploy a Safe Haven Management Environment (SHM)

These instructions will deploy a new Safe Haven Management Environment (SHM).
This is required to manage your Secure Research Environments (SREs) and **must be** deployed before you create any SREs.
A single SHM can manage all your SREs.
Alternatively, you may run multiple SHMs concurrently, for example you may have a group of projects with the same lifecycle which share a different SHM to your other projects.

```{include} snippets/00_symbols.partial.md
:relative-images:
```

(deploy_shm_prerequisites)=

## 1. {{seedling}} Prerequisites

- An [Azure subscription](https://portal.azure.com) with sufficient credits to build the environment in: we recommend around $3,000 as a reasonable starting point.

  ```{tip}
  - Ensure that the **Owner** of the subscription is an `Azure Security group` that contains all administrators and no-one else.
  - We recommend using separate `Microsoft Entra IDs` for users and administrators
  ```

- `PowerShell`
    - We recommend [installing](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell) the [latest stable release](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.4) of Powershell. We have most recently tested deployment using version `7.4.1`.
- `Powershell` cross-platform modules

  ````{tip}
  Check whether you are missing any required modules by running
  ```powershell
  PS> ./deployment/CheckRequirements.ps1
  ```
  Either manually install each missing module or install them all with
  ```powershell
  PS> ./deployment/CheckRequirements.ps1 -InstallMissing
  ```
  ````

- `Microsoft Remote Desktop`
    - ![macOS](https://img.shields.io/badge/-555?&logo=apple&logoColor=white) this can be installed from the [Apple store](https://www.apple.com/app-store/)
    - ![Windows](https://img.shields.io/badge/-555?&logo=windows&logoColor=white) this can be [downloaded from Microsoft](https://apps.microsoft.com/store/detail/microsoft-remote-desktop/9WZDNCRFJ3PS)
    - ![Linux](https://img.shields.io/badge/-555?&logo=linux&logoColor=white) use your favourite remote desktop client
- `OpenSSL`

    - ![macOS](https://img.shields.io/badge/-555?&logo=apple&logoColor=white) a pre-compiled version can be installed using Homebrew: `brew install openssl`
    - ![Windows](https://img.shields.io/badge/-555?&logo=windows&logoColor=white) binaries are [available here](https://wiki.openssl.org/index.php/Binaries).

      ```{error}
      If `Powershell` cannot detect `OpenSSL` you may need to explicitly add your `OpenSSL` installation to your `Powershell` path by running `$env:path = $env:path + ";<path to OpenSSL bin directory>`
      ```

    - ![Linux](https://img.shields.io/badge/-555?&logo=linux&logoColor=white) use your favourite package manager or install manually following the [instructions on GitHub](https://github.com/openssl/openssl)

````{hint}
If you run:

```powershell
PS> Start-Transcript -Path <a log file>
```

before you start your deployment and

```powershell
PS> Stop-Transcript
```

afterwards, you will automatically get a full log of the Powershell commands you have run.
````

## 2. {{clipboard}} Safe Haven Management configuration

(roles_deployer_shm_id)=

### Management environment ID

```{important}
Choose a short ID `<SHM ID>` to identify the management environment (e.g. `project`).
This can have a maximum of **seven alphanumeric characters**.
```

(roles_system_deployer_shm_configuration_file)=

### Create configuration file

The core properties for the Safe Haven Management (SHM) environment must be defined in a JSON file named `shm_<SHM ID>_core_config.json` in the `environment_configs` folder.
The following core SHM properties are required - look in the `environment_configs` folder to see some examples.

```json
{
  "name": "Name of this Safe Haven (e.g. 'Turing Production Safe Haven').",
  "shmId": "The <SHM ID> that you decided on above (e.g. 'project').",
  "domain": "The fully qualified domain name for the management environment (e.g. 'project.turingsafehaven.ac.uk')",
  "timezone": "[Optional] Timezone in IANA format (e.g. 'Europe/London').",
  "azure": {
    "adminGroupName": "Azure Security Group that admins of this Safe Haven will belong to (see below for details).",
    "activeDirectoryTenantId": "Tenant ID for the Microsoft Entra ID containing users (see below for details on how to obtain this). Note that we preserve the Active Directory name here for compatability with earlier DSH versions.",
    "location": "Azure location to deploy the management environment into (e.g. 'uksouth').",
    "subscriptionName": "Azure subscription to deploy the management environment into."
  },
  "organisation": {
    "name": "Name of your organisation, used when generating SSL certificates (e.g. 'The Alan Turing Institute')",
    "townCity": "Town where your organisation is located, used when generating SSL certificates (e.g. 'London')",
    "stateCountyRegion": "Region where your organisation is located, used when generating SSL certificates (e.g. 'London')",
    "countryCode": "Country where your organisation is located, used when generating SSL certificates (e.g. 'GB')",
    "contactEmail": "Email address at your organisation that will receive notifications when SSL certificates are about to expire."
  },
  "dnsRecords": {
    "subscriptionName": "[Optional] Azure subscription which holds DNS records (if not specified then the value from the 'azure' block will be used).",
    "resourceGroupName": "[Optional] Resource group which holds DNS records (e.g. RG_SHM_DNS_TEST)."
  },
  "repositoryType": {
    "tier2": "[Optional] Whether to use 'mirror' or 'proxy' for tier-2 repositories (default is 'proxy').",
    "tier3": "[Optional] Whether to use 'mirror' or 'proxy' for tier-3 repositories (default is 'proxy')."
  },
  "vmImages": {
    "subscriptionName": "[Optional] Azure subscription where VM images will be built (if not specified then the value from the 'azure' block will be used). Multiple Safe Haven deployments can share a single set of VM images in a common subscription if desired - this is what is done in the Turing deployment. If you are hoping to use images that have already been built for another Safe Haven deployment, make sure you specify this parameter accordingly.",
    "location": "[Optional] Azure location where VM images should be built (if not specified then the value from the 'azure' block will be used). Multiple Safe Haven deployments can share a single set of VM images in a common subscription if desired - this is what is done in the Turing deployment. If you are hoping to use images that have already been built for another Safe Haven deployment, make sure you specify this parameter accordingly.",
    "buildIpAddresses": "[Optional] One or more IP addresses which admins will be running the VM build scripts from (if not specified then Turing IP addresses will be used)."
  },
  "overrides": "[Optional, Advanced] Do not use this unless you know what you're doing! If you want to override any of the default settings, you can do so by creating the same JSON structure that would be found in the final config file and nesting it under this entry. For example, to change the size of the data disk on the domain controller, you could use something like: 'shm: { dc: { disks: { data: { sizeGb: 50 } } } }'"
}
```

```{note}
- This configuration file is also used when deploying an SRE environment.
- We recommend that you set the fully qualified domain name to `<SHM ID>.<some domain that you control>`.
- This may require purchasing a dedicated domain so follow your organisation's guidance.
- You must ensure that the group specifed in `azure.adminGroupName` exists in the Microsoft Entra ID for the tenant that you will be deploying into. Depending on your setup, this may be different from the Microsoft Entra ID where your users are created.
```

```{admonition} Alan Turing Institute default
- **production** uses `<SHM ID>.turingsafehaven.ac.uk`
- **development** uses `<SHM ID>.dsgroupdev.co.uk`
```

### (Optional) Verify code version

If you have cloned/forked the code from our `GitHub` repository, you can confirm which version of the Data Safe Haven you are currently using by running the following commands:

![Powershell: a few seconds](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20seconds)

```powershell
PS> git tag --list | Select-String $(git describe --tags)
```

This will check the tag you are using against the list of known tags and print it out.
You can include this confirmation in any record you keep of your deployment.

### (Optional) View full SHM configuration

A full configuration, which will be used in subsequent steps, will be automatically generated from your core configuration.
Should you wish to, you can print the full SHM config by running the following Powershell command:

![Powershell: a few seconds](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20seconds) at {{file_folder}} `./deployment`

```powershell
PS> ./ShowConfigFile.ps1 -shmId <SHM ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM

(roles_deployer_setup_aad)=

## 3. {{file_folder}} Setup Microsoft Entra ID

```{warning}
If you wish to reuse an existing Microsoft Entra ID please make sure you remove any existing `Conditional Access Policies` by going to `Security > Conditional Access > Policies` and manually removing the `Restrict Microsoft Entra ID access` and `Require MFA` policies.
You can then continue to the next step: {ref}`getting the Microsoft Entra tenant ID <roles_deployer_aad_tenant_id>`.
```

### Create a new Microsoft Entra ID

![Portal: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-azure&label=portal&color=blue&message=one%20minute)

- From the Azure portal, click `Create a Resource` and search for `Microsoft Entra ID`
  <details><summary><b>Screenshots</b></summary>

  ```{image} deploy_shm/AAD.png
  :alt: Microsoft Entra ID
  :align: center
  ```

  </details>

- Click `Create`
- Set the `Organisation Name` to the value of `<name>` in your core configuration file (e.g. `Turing Production Safe Haven`)
    - Note: be careful not to confuse this with the `<name>` under `<organisation>` used in the config file
- Set the `Initial Domain Name` to the `Organisation Name` all lower case with spaces removed (e.g. `turingproductionsafehaven`)
- Set the `Country or Region` to whatever region is appropriate for your deployment (e.g. `United Kingdom`)
  <details><summary><b>Screenshots</b></summary>

  ```{image} deploy_shm/aad_creation.png
  :alt: Microsoft Entra ID creation
  :align: center
  ```

  </details>

- Click `Create`
- Wait for Microsoft Entra ID to be created

(roles_deployer_aad_tenant_id)=

### Get the Microsoft Entra Tenant ID

![Microsoft Entra ID: one minute](https://img.shields.io/badge/Microsoft_Entra_ID-One_minute-blue?logo=microsoft-academic)

- From the Azure portal, navigate to the Microsoft Entra ID you have created.
  You can do this by:
    - Clicking the link displayed at the end of the initial Microsoft Entra ID  deployment.
    - Clicking on your username and profile icon at the top left of the Azure portal, clicking `Switch directory` and selecting the Microsoft Entra ID  you have just created from the `All Directories` section of the `Directory + Subscription` panel that then displays.
- If required, click the "hamburger" menu in the top left corner (three horizontal lines) and select `Microsoft Entra ID`
- Click `Overview` in the left panel and copy the `Tenant ID` displayed under the Microsoft Entra ID name and initial `something.onmicrosoft.com` domain.
  <details><summary><b>Screenshots</b></summary>

  ```{image} deploy_shm/aad_tenant_id.png
  :alt: Microsoft Entra tenant ID
  :align: center
  ```

  </details>

- Ensure that you add this to the {ref}`configuration file <roles_system_deployer_shm_configuration_file>` for this SHM under `azure > activeDirectoryTenantId`.

(roles_deployer_shm_configure_dns)=

## 4. {{door}} Register custom domain with Microsoft Entra ID

### Configure DNS for the custom domain

![Powershell: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

```powershell
PS> ./Setup_SHM_DNS_Zone.ps1 -shmId <SHM ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM

````{error}
If you see a message `You need to add the following NS records to the parent DNS system for...` you will need to add the NS records manually to the parent's DNS system, as follows:

<details><summary><b>Manual DNS configuration instructions</b></summary>

- To find the required values for the NS records on the portal, click `All resources` in the far left panel, search for `DNS Zone` and locate the DNS Zone with the SHM's domain.
- The NS record will list four Azure name servers which must be duplicated to the parent DNS system.
- If the parent domain has an Azure DNS Zone, create an NS record set in this zone.
    - The name should be set to the subdomain (e.g. `project`) or `@` if using a custom domain, and the values duplicated from above
    - For example, for a new subdomain `project.turingsafehaven.ac.uk`, duplicate the NS records from the Azure DNS Zone `project.turingsafehaven.ac.uk` to the Azure DNS Zone for `turingsafehaven.ac.uk`, by creating a record set with name `project`
    ```{image} deploy_shm/shm_subdomain_ns.png
    :alt: Subdomain NS record
    :align: center
    ```
- If the parent domain is outside of Azure, create NS records in the registrar for the new domain with the same value as the NS records in the new Azure DNS Zone for the domain.
</details>
````

### Add the SHM domain to the Microsoft Entra ID

![Powershell: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

```powershell
PS> ./Setup_SHM_AAD_Domain.ps1 -shmId <SHM ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM

```{error}
If you get an error like `Could not load file or assembly 'Microsoft.IdentityModel.Clients.ActiveDirectory, Version=3.19.8.16603, Culture=neutral PublicKeyToken=31bf3856ad364e35'. Could not find or load a specific file. (0x80131621)` then you may need to try again in a fresh `Powershell` terminal.
```

```{error}
Due to delays with DNS propagation, the script may occasionally exhaust the maximum number of retries without managing to verify the domain.
If this occurs, run the script again.
If it exhausts the number of retries a second time, wait an hour and try again.
```

(roles_deploy_add_additional_admins)=

## 5. {{hammer}} Create Microsoft Entra administrator accounts

A default external administrator account was automatically created for the user you were logged in as when you initially created the Microsoft Entra ID.
This user should also **not be used** for administering the Microsoft Entra ID.

Several later steps will require the use of a **native** administrator account with a valid mobile phone and email address.
You must therefore create and activate a **native** administrator account for each person who will be acting as a system administrator.
After doing so, you can delete the default external user - we strongly recommend that you do so.

```{tip}
In order to avoid being a single point of failure, we strongly recommend that you add other administrators in addition to yourself.
```

```{caution}
An emergency access admin account is created later in the deployment process.
This should not be used except when **absolute necessary**.
In particular, it should not be used as a shared admin account for routine administration of the Safe Haven.
```

### Create a new account for each administrator (including yourself)

![Microsoft Entra ID: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Microsoft%20Entra%20ID&color=blue&message=a%20few%20minutes)

- From the Azure portal, navigate to the Microsoft Entra ID you have created.
- Click `Users` in the left hand sidebar and click on the `+New user` icon in the top menu above the list of users.

#### Create an internal admin user:

- User name: `aad.admin.firstname.lastname@<SHM domain>`
- Name: `AAD Admin - Firstname Lastname`
- Leave `Auto-generate password` set. Users will be able to reset their passwords on first login and it is good security practice for admins not to know user passwords.
- Click the `User` link in the `Roles` field and make the user an administrator:
    - Search for `Global Administrator`
    - Check `Global Administrator`
    - Click the `Select` button
- Set their usage location to the country you used when creating the Safe Haven Microsoft Entra ID
- Leave all other fields empty, including First name and Last name
- Click `Create`

```{image} deploy_shm/aad_create_admin.png
:alt: AAD create admin account
:align: center
```

#### Add authentication methods for self-service password reset

- Navigate to `Users` and click on the account you have just created.
- Click on `Properties` and then edit the `Contact info` section.
    - Add the the user's mobile phone number to the `Mobile phone` field.
      Make sure to prefix it with the country code and **do not include** the leading zero (e.g. `+44 7700900000`).
    - They will need to enter their number in **exactly this format** when performing a self-service password reset.
    - Do **not** add anything in the `Email` field here as this will prevent you from using the same email address for a user account.
    - Click the `Save` icon in top panel.
- In the left-hand sidebar click `Authentication methods`.
    - Enter the user's mobile phone number in the `Phone` field, using the same format as above.
        - Note that you do **not** need to fill out the `Alternate Phone` field.
    - Enter the user's institutional email address in the `Email` field.
    - Ensure that you have registered **both** a phone number and an email address.
    - Click the `Save` icon in top panel.

### Register allowed authentication methods

When you have finished creating administrator accounts, you will need to ensure that they are able to set their own passwords

- From the Azure portal, navigate to the Microsoft Entra ID you have created.
- Click `Manage > Password Reset` on the left-hand sidebar
- Click `Manage > Authentication methods` on the left-hand sidebar
- Ensure that both `Email` and `Mobile phone` are enabled

```{image} deploy_shm/aad_authentication_methods.png
:alt: AAD create admin account
:align: center
```

### Activate and configure your new internal admin account

```{warning}
In the next step we will delete the external admin account created for the user account you used to create the Microsoft Entra ID.
Before you do this, you **must** configure and log into the **native** admin account you have just created for yourself.
```

- The `<username>` for this account is `aad.admin.firstname.lastname`
- The `<username domain>` for this account is the same as the `<SHM domain>`

The administrators you have just set up can activate their accounts by following the password and MFA steps in the {ref}`user guide <user_setup_password_mfa>`.

### Remove the default external user that was used to create the Microsoft Entra ID

```{warning}
Make sure you have activated your account and **successfully logged in** with the new **native** administrator account you have just created for yourself (`aad.admin.firstname.lastname@<SHM domain>`) before deleting the default external administrator account.
```

![Microsoft Entra ID: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Microsoft%20Entra%20ID&color=blue&message=a%20few%20minutes)

- Ensure you are logged in with the new **native** administrator account you have just created.
    - Click on your username at the top right corner of the screen, then `Sign in with a different user`.
    - Log in with the password you set for yourself when activating your admin account in the previous step
- From the Azure portal, navigate to the Microsoft Entra ID you have created.
- Click `Users` in the left hand sidebar
- Select the default **external** user that was created when you created the Microsoft Entra ID.
    - The `User principal name` field for this user will contain the **external domain** and will have `#EXT#` before the `@` sign (for example `alovelace_turing.ac.uk#EXT#@turingsafehaven.onmicrosoft.com`)
- Click the `Delete user` icon in the menu bar at the top of the user list panel

(roles_deployer_deploy_shm)=

## 6. {{computer}} Deploy SHM

![Powershell: a few hours](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20hours) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

```powershell
PS> ./Deploy_SHM.ps1 -shmId <SHM ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE

You will be prompted for credentials for:

- a user with admin rights over the Azure subscriptions you plan to deploy into
- a user with Global Administrator privileges over the Microsoft Entra ID you set up earlier

This will perform the following actions, which can be run individually if desired:

(roles_deployer_shm_key_vault)=

<details>
<summary><strong>Deploy Key Vault for SHM secrets and create an emergency admin account</strong></summary>

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

```powershell
PS> ./Setup_SHM_Key_Vault_And_Emergency_Admin.ps1 -shmId <SHM ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM

```{error}
If you get an error like `Could not load file or assembly 'Microsoft.IdentityModel.Clients.ActiveDirectory, Version=3.19.8.16603, Culture=neutral PublicKeyToken=31bf3856ad364e35'. Could not find or load a specific file. (0x80131621)` then you may need to try again in a fresh `Powershell` terminal.
```

Some (rare) operations require you to be logged in as a **native** Global Administrator.
To support these rare cases, and to allow access to the Safe Haven Microsoft Entra ID in the case of loss of access to personal administrator accounts (e.g. lost access to MFA), an **emergency access** administrator account has been created by the above script.

```{warning}
Do not use this account unless absolutely required!
```

</details>

(roles_deployer_shm_vnet_gateway)=

<details>
<summary><strong>Deploy network and VPN gateway</strong></summary>

![Powershell: twenty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=twenty%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

```powershell
PS> ./Setup_SHM_Networking.ps1 -shmId <SHM ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM

<b>Sanity check</b>

![Portal: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-azure&label=portal&color=blue&message=one%20minute)

Once the script exits successfully you should see the following resource groups in the Azure Portal under the SHM subscription, with the appropriate `<SHM ID>` for your deployment e.g. `RG_SHM_<SHM ID>_NETWORKING`:

```{image} deploy_shm/vnet_resource_groups.png
:alt: Resource groups
:align: center
```

```{error}
If you cannot see these resource groups:
- Ensure you are logged into the portal using the account that you are building the environment with.
- Click on your username in the top right corner of the Azure portal screen and ensure that your SHM subscription (see `shm_<SHM ID>_core_config.json`) is one of the selections.
- Click the "hamburger" menu in the top left corner (three horizontal lines) and select `Resource groups`.
```

</details>

(roles_system_deployer_shm_deploy_logging)=

<details>
<summary><strong>Deploy monitoring</strong></summary>

![Powershell: thirty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=thirty%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

```powershell
PS> ./Setup_SHM_Monitoring.ps1 -shmId <SHM ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM

</details>

(roles_system_deployer_shm_deploy_firewall)=

<details>
<summary><strong>Deploy firewall</strong></summary>

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

```powershell
PS> ./Setup_SHM_Firewall.ps1 -shmId <SHM ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM

</details>

(roles_deployer_shm_domain_controllers)=

<details>
<summary><strong>Deploy domain controllers</strong></summary>

![Powershell: one hour](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=one%20hour) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

```powershell
PS> ./Setup_SHM_DC.ps1 -shmId <SHM ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM

<b>Sanity check</b>

Once the script exits successfully you should see the following resource groups in the Azure Portal under the SHM subscription, with the appropriate `<SHM ID>` for your deployment e.g. `RG_SHM_<SHM ID>_NETWORKING`:

```{image} deploy_shm/dc_resource_groups.png
:alt: Resource groups
:align: center
```

```{error}
If you cannot see these resource groups:
- Ensure you are logged into the portal using the account that you are building the environment with.
- Click on your username in the top right corner of the Azure portal screen and ensure that your SHM subscription (see `shm_<SHM ID>_core_config.json`) is one of the selections.
- Click the "hamburger" menu in the top left corner (three horizontal lines) and select `Resource groups`.
```

</details>

(roles_system_deployer_shm_deploy_update_servers)=

<details>
<summary><strong>Deploy update servers</strong></summary>

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

```powershell
PS> ./Setup_SHM_Update_Servers.ps1 -shmId <SHM ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM

</details>

(roles_system_deployer_shm_deploy_mirrors)=

<details>
<summary><strong>Deploy local package repositories</strong></summary>

Two different types of local package repositories are available for {ref}`policy_tier_2` and {ref}`policy_tier_3` SREs:

- **Proxy** (the repository makes on-demand connections to the external repository)
- **Mirror** (the repository full replicates all requested packages from the external repository)

```{hint}
We **recommend** using Nexus proxies at both {ref}`policy_tier_2` and {ref}`policy_tier_3` to avoid the time taken to sync local mirrors.
```

We currently support the **PyPI** (Python) and **CRAN** (R) repositories.

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

```powershell
PS> ./Setup_SHM_Package_Repositories.ps1 -shmId <SHM ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM

```{danger}
You should never attempt to manage the Nexus proxy through the web interface.
Doing so from outside the Nexus subnet could expose the admin credentials.
```

```{warning}
Note that a full set of {ref}`policy_tier_2` local mirrors currently take around **two weeks** to fully synchronise with the external package repositories as PyPI contains >10TB of packages.
```

</details>

(deploy_shm_vpn)=

## 7. {{station}} Configure VPN connection

### Download a client VPN certificate for the Safe Haven Management network

![Portal: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-azure&label=portal&color=blue&message=one%20minute)

- Navigate to the SHM Key Vault via `Resource Groups > RG_SHM_<SHM ID>_SECRETS > kv-shm-<SHM ID>`
- Once there open the `Certificates` page under the `Settings` section in the left hand sidebar.
- Click on the certificate named `shm-<SHM ID>-vpn-client-cert` and select the `CURRENT VERSION`
- Click the `Download in PFX/PEM format` link at the top of the page and save the `*.pfx` certificate file locally
- To install, double click on the downloaded certificate (or on macOS you can manually drag it into the `login` keychain), leaving the password field blank.

**Make sure to securely delete the local "\*.pfx" certificate file that you downloaded after you have installed it.**

### Setup VPN connection to the Safe Haven Management network

![Portal: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-azure&label=portal&color=blue&message=one%20minute)

- Navigate to the Safe Haven Management (SHM) virtual network gateway in the SHM subscription via `Resource Groups > RG_SHM_<SHM ID>_NETWORKING > VNET_SHM_<SHM ID>_GW`
- Once there open the `Point-to-site configuration` page under the `Settings` section in the left hand sidebar
- Click the `Download VPN client` link at the top of the page to download a zip file
  <details><summary><b>Screenshots</b></summary>

  ```{image} deploy_shm/certificate_details.png
  :alt: Certificate details
  :align: center
  ```

  </details>

- Unzip the zip file and identify the root certificate (`Generic\VpnServerRoot.cer`) and VPN configuration file (`Generic\VpnSettings.xml`)
- Follow the [VPN set up instructions](https://docs.microsoft.com/en-us/azure/vpn-gateway/point-to-site-vpn-client-configuration-azure-cert) using the section appropriate to your operating system (**you do not need to install the `Generic\VpnServerRoot.cer` certificate, as we're using our own self-signed root certificate**):

```{admonition} ![Windows](https://img.shields.io/badge/-555?&logo=windows&logoColor=white) instructions
- Use SSTP for the VPN type
- Name the VPN connection `Safe Haven Management Gateway (<SHM ID>)`
- **Do not** rename the VPN client as this will break it
```

````{admonition} ![macOS](https://img.shields.io/badge/-555?&logo=apple&logoColor=white) instructions
- Start from "Configure VPN client profile" step of the `macOS` instructions.
- Use IKEv2 for the VPN type
  <details><summary><b>For users of <i>macOS Catalina</i> or later</b></summary>

  You must select `None` from the drop-down (not `Certificate`) and then select the `Certificate` radio button underneath as shown in the image below.
  ```{image} deploy_shm/catalina_authentication.png
  :alt: Certificate details
  :align: center
  ```
  </details>
- Name the VPN connection `Safe Haven Management Gateway (<SHM ID>)`
- You can view the details of the downloaded certificate by highlighting the certificate file in Finder and pressing the spacebar.
- You can then look for the certificate of the same name in the login KeyChain and view its details by double clicking the list entry.
- If the details match the certificate has been successfully installed.
````

You should now be able to connect to the SHM virtual network via the VPN.

```{important}
Each time you need to access the virtual network ensure you are connected via the VPN.
```

```{error}
![Windows](https://img.shields.io/badge/-555?&logo=windows&logoColor=white) You may get a `Windows protected your PC` pop up.
If so, click `More info -> Run anyway`.
```

```{error}
![Windows](https://img.shields.io/badge/-555?&logo=windows&logoColor=white) You may encounter a further warning along the lines of `Windows cannot access the specified device, path, or file`.
This may mean that your antivirus is blocking the VPN client.
You will need to configure your antivirus software to make an exception.
```

(roles_system_deployer_configure_domain_controllers)=

## 8. {{house_with_garden}} Configure domain controllers

(roles_system_deployer_shm_remote_desktop)=

### Configure the first domain controller via Remote Desktop

![Portal: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-azure&label=portal&color=blue&message=one%20minute)

- Navigate to the **SHM primary domain controller** VM in the portal at `Resource Groups > RG_SHM_<SHM ID>_DC > DC1-SHM-<SHM ID>` and note the `Private IP address` for this VM
- Next, navigate to the `RG_SHM_<SHM ID>_SECRETS` resource group and then the `kv-shm-<SHM ID>` Key Vault and then select `secrets` on the left hand panel and retrieve the following:
  - `<admin username>` is in the `shm-<SHM ID>-domain-admin-username` secret.
  - `<admin login>` is the `<admin username>` followed by the SHM AD domain: `<admin username>@<SHM domain>`.
  - `<admin password>` is in the `shm-<SHM ID>-domain-admin-password` secret.

```{danger}
- These domain administrator credentials have complete control over creating and deleting users as well as assigning them to groups.
- Do not use them except where specified and never write them down!
- Be particularly careful never to use them to log in to any user-accessible VMs (such as the secure research desktops).
```

(roles_deployer_shm_aad_connect)=

#### Install Microsoft Entra Connect

![Remote: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=ten%20minutes)

````{include} ../roles/system_manager/snippets/02_ms_entra_connect.partial.md
:relative-images:
````

- Log into the **SHM primary domain controller** (`DC1-SHM-<SHM ID>`) VM using the `private IP address`, `<admin login>` and `<admin password>` that you {ref}`obtained from the portal above <roles_system_deployer_shm_remote_desktop>`.
- Navigate to `C:\Installation`
- Run the `AzureADConnect` Windows Installer Package
  - On the `Welcome to Azure AD Connect` screen:
    - Tick the `I agree to the license terms` box
    - Click `Continue`
  - On the `Express Settings` screen:
    - Click `Customize`
  - On the `Install required components` screen:
    - Click `Install`
  - On the `User sign-in` screen:
    - Ensure that `Password Hash Synchronization` is selected
    - Click `Next`
  - On the `Connect to Azure AD` screen:
    - Provide credentials for the Azure Active Directory **global administrator** account you set up earlier (`aad.admin.<first name>.<last name>@<SHM domain>`) when prompted
    - If you receive a pop-up prompt, provide the same credentials when prompted
    - Back on the `Connect to Azure AD` screen, click `Next`
    - Approve the login with MFA if required
  - On the `Connect your directories` screen:
    - Ensure that correct forest (your custom domain name; e.g `turingsafehaven.ac.uk`) is selected and click `Add Directory`
    - On the `AD forest account` pop-up:
      - Select `Use existing AD account`
      - Enter the details for the `localadsync` user.
        - **Username**: use the value of the `shm-<SHM ID>-aad-localsync-username` secret in the SHM key vault:
          - EITHER prepended with `<Domain ID>\`, where the `Domain ID` is the capitalised form of the `<SHM ID>`, so if the _SHM ID_ is `project` and the _username_ is `projectlocaladsync` then you would use `PROJECT\projectlocaladsync` here.
          - OR suffixed with `<SHM domain>`, so if the _SHM domain_ is `project.turingsafehaven.ac.uk` and the _username_ is `projectlocaladsync` then you would use `projectlocaladsync@project.turingsafehaven.ac.uk` here.
        - **Password**: use the `shm-<SHM ID>-aad-localsync-password` secret in the SHM key vault.
      - Click `OK`
    - Click `Next`
  - On the `Azure AD sign-in configuration` screen:
    - Verify that the `User Principal Name` is set to `userPrincipalName`
    - Click `Next`
  - On the `Domain and OU filtering` screen:
    - Select `Sync Selected domains and OUs`
    - Expand the domain and deselect all objects
    - Select `Safe Haven Research Users` and `Safe Haven Security Groups`
    - Click `Next`
  - On the `Uniquely identifying your users` screen:
    - Click `Next`
  - On the `Filter users and devices` screen:
    - Select `Synchronize all users and devices`
    - Click `Next`
  - On the `Optional features` screen:
    - Select `Password Writeback`
    - Click `Next`
  - On the `Ready to configure` screen:
    - Ensure that the `Start the synchronisation process when configuration completes` option is ticked.
    - Click `Install`
    - This may take a few minutes to complete
  - On the `Configuration complete` screen:
    - Click `Exit`

```{note}
Take care to consider any differences in the keyboard of your machine and the Windows remote desktop when entering any usernames or passwords.
```

```{error}
If you receive an Internet Explorer pop-up dialog `Content within this application coming from the website below is being blocked by Internet Explorer Advanced Security Configuration` for Microsoft domains such as `https://login.microsoft.com` or `https://aadcdn.msftauth.net` then you can safely add these as exceptions:
- Click `Add`
- Click `Close`
```

```{error}
If you receive an error message on the login webpage pop-ups saying `We can't sign you in.
Javascript is required to sign you in....` followed by the Script Error: `Do you want to continue running scripts on this page` you can safely allow Javascript:
- Click `Yes`
- Close the dialog by clicking `X`
```

```{error}
If you see a Windows Security Warning, related to the MFA login:
- Check `Don't show this message again`
- Click `Yes` to close the dialog.
```

```{error}
If you get an error that the username/password is incorrect or that the domain/directory could not be found when entering the details for the `localadsync` user, try resetting the password for this user in the **Domain Controller** Active Directory so that it matches the value stored in the Key Vault
- In Server Manager click `Tools > Active Directory Users and Computers`
- Expand the domain in the left hand panel
- Expand the `Safe Haven Service Accounts` OU
- Right click on the `<SHM ID> Local AD Sync Administrator` user and select `reset password`
- Set the password to the value from the appropriate Key Vault secret.
- Leave the other settings alone and click `OK`
```

```{error}
If you have recently torn down another SHM linked to the same Microsoft Entra ID you might see the error `Directory synchronization is currently in a pending disabled state for this directory. Please wait until directory synchronization has been fully disabled before trying again`.
You need to wait for the `Microsoft Entra ID` to fully disconnect - this can take up to 72 hours but is typically sooner.
You do not need to close the installer window while waiting.
If you need to, you can disconnect from the DC and VPN and reconnect later before clicking `Retry`.
```

```{error}
If you get an error that the connection to Azure Active Directory could not be made, please check that you do not have any Conditional Access policies enabled on the Azure Active Directory that require MFA for the synchronisation account.
```

(roles_system_deployer_shm_aad_connect_rules)=

#### Update Azure Active Directory Connect rules

This step allows the locale (country code) to be pushed from the local AD to Microsoft Entra ID.

![Remote: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=one%20minute)

- Log into the **SHM primary domain controller** (`DC1-SHM-<SHM ID>`) VM using the `private IP address`, `<admin login>` and `<admin password>` that you {ref}`obtained from the portal above <roles_system_deployer_shm_remote_desktop>`.
- Run the following command on the remote domain controller VM to update the Microsoft Entra rules

```powershell
PS> C:\Installation\UpdateAADSyncRule.ps1
```

(roles_system_deployer_shm_validate_aad_synchronisation)=

### Validate Active Directory synchronisation

This step validates that your local Active Directory users are correctly synchronised to Microsoft Entra ID.
Note that you can use the same script after deploying an SRE to add users in bulk.

![Remote: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=one%20minute)

- Log into the **SHM primary domain controller** (`DC1-SHM-<SHM ID>`) VM using the `private IP address`, `<admin login>` and `<admin password>` that you {ref}`obtained from the portal above <roles_system_deployer_shm_remote_desktop>`.
- Add your details to create researcher accounts for yourself and any other deployers.

```{include} snippets/user_csv_format.partial.md
:relative-images:
```

- Run the following command on the remote domain controller VM to create and synchronise the users

```powershell
PS> C:\Installation\CreateUsers.ps1 <path_to_user_details_file>
```

- This script will add the users and trigger a sync with Microsoft Entra ID
- Wait a few minutes for the changes to propagate

![Microsoft Entra ID: a few seconds](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Microsoft%20Entra%20ID&color=blue&message=a%20few%20seconds)

- Click `Users > All users` and confirm that the new user is shown in the user list.
- The new user account should have the `On-premises sync enabled` field set to `Yes`

```{error}
If you get the message `New-ADUser: The specified account already exists` you should first check to see whether that user actually does already exist!
Once you're certain that you're adding a new user, make sure that the following fields are unique across all users in the Active Directory.

- `SamAccountName`: Specified explicitly in the CSV file.
   - If this is already in use, consider something like `firstname.middle.initials.lastname`
- `DistinguishedName`: Formed of `CN=<DisplayName>,<OUPath>` by Active directory on user creation.
   - If this is in use, consider changing `DisplayName` from `<GivenName> <Surname>` to `<GivenName> <Middle> <Initials> <Surname>`.
```

### Configure AAD side of AD connect

![Microsoft Entra ID: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Microsoft%20Entra%20ID&color=blue&message=one%20minute)

- From the Azure portal, navigate to the Microsoft Entra ID you have created.
- Select `Password reset` from the left hand menu
- Select `On-premises integration` from the left hand side bar

  - Ensure `Enable password writeback for synced users` is ticked.

    ```{image} deploy_shm/enable_password_writeback.png
    :alt: Enable password writeback
    :align: center
    ```

  - If you changed this setting, click the `Save` icon

## 9. {{iphone}} Enable MFA and self-service password reset

To enable self-service password reset (SSPR) and MFA-via-phone-call, you must have sufficient licences for all users.

### Add licences that support self-service password reset

![Microsoft Entra ID: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Microsoft%20Entra%20ID&color=blue&message=a%20few%20minutes)

Click the heading that applies to you to expand the instructions for that scenario.

<details><summary><b>Test deployments</b></summary>

**For testing** you can enable a free trial of the P2 License (NB. it can take a while for these to appear on your Microsoft Entra ID).
You can activate the trial while logged in as your deafult guest administrator account.

- From the Azure portal, navigate to the Microsoft Entra ID you have created.
- Click on `Licences` in the left hand sidebar
- Click on `All products` in the left hand sidebar
- Click on the `+Try/Buy` text above the empty product list and add a suitable licence product.
  - Expand the `Free trial` arrow under `Microsoft Entra ID P2`
  - Click the `Activate` button
  - Wait for the `Microsoft Entra ID P2` licence to appear on the list of `All Products` (this could take several minutes)

</details>

<details><summary><b>Production deployments</b></summary>

**For production** you should buy P1 licences.
This requires you to be logged in with an **native** Global Administrator account.
As activating self-service password reset requires active MFA licences, this is one of the rare occasions you will need to use the emergency access admin account.

- Switch to the the **emergency administrator** account:
  - Click on your username at the top right corner of the screen, then click "Sign in with a different account"
  - Enter `aad.admin.emergency.access@<SHM domain>` as the username
  - Open a new browser tab and go to the [Azure Portal](https://portal.azure.com/)
  - Change to the Microsoft Entra ID associated with the Safe Haven SHM subscription (e.g. an existing corporate Microsoft Entra ID).
    Do this by clicking on your username at the top right corner of the screen, then `Switch directory`, then selecting the directory you wish to switch to.
  - Click the "hamburger" menu in the top left corner (three horizontal lines) and select `Subscriptions`
  - Click on the Safe Haven SHM subscription
  - Click on `Resource Groups` in the left hand sidebar then `RG_SHM_<SHM ID>_SECRETS`
  - Click on the `kv-shm-<shm id>` Key Vault
  - Click on `Secrets` in the left hand sidebar
  - Click on the `shm-<shm id>-aad-emergency-admin-password` secret
  - Click on the entry in the `Current version` section
  - Click on the clipboard icon next to the `Secret value` field
  - The emergency admin account password in now in your clipboard
  - Switch back to the browser tab with the Azure login page
  - Paste the password you copied from the Key Vault
  - Click the `Sign in` button
- Click the `Purchase services` link in the information panel above the trial options.
- In the "Microsoft 365 Admin Centre" portal that opens:
  - Expand the `Billing` section of the left hand side bar
  - Click on `Purchase services`
  - Scroll down the list of products and select `Microsoft Entra ID Premium P1` and click `Buy`
  - Select `Pay monthly`
  - Enter the number of licences required.
  - Leave `automatically assign all of your users with no licences` checked
  - Click `Check out now`
  - Enter the address of the organisation running the Safe Haven on the next screen
  - Click next and enter payment details when requested
- Switch back to your original administrator account
  - Click on your username at the top right corner of the screen, then click "Sign in with a different account"
  - Log in as the user you used to create the Safe Haven Microsoft Entra ID
  </details>

### Enable self-service password reset

![Microsoft Entra ID: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Microsoft%20Entra%20ID&color=blue&message=one%20minute)

- Ensure your Azure Portal session is using the new Safe Haven Management (SHM) Microsoft Entra ID.
  The name of the current directory is under your username in the top right corner of the Azure portal screen.
  To change directories click on your username at the top right corner of the screen, then `Switch directory`, then the name of the new SHM directory.
- Click the "hamburger" menu in the top left corner (three horizontal lines) and select `Microsoft Entra ID`
- Click `Password reset` in the left hand sidebar
- Set the `Self service password reset enabled` toggle to `All`

  ```{image} deploy_shm/aad_sspr.png
  :alt: AAD self-service password reset
  :align: center
  ```

- Click the `Save` icon

```{error}
If you see a message about buying licences, you may need to refresh the page for the password reset option to show.
```

### Configure MFA on Microsoft Entra ID

![Microsoft Entra ID: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Microsoft%20Entra%20ID&color=blue&message=a%20few%20minutes)

- From the Azure portal, navigate to the Microsoft Entra ID you have created.
- Click `Users` in the left hand sidebar
- Click the `Per-user MFA` icon in the top bar of the users list.
- Click on `Service settings` at the top of the panel
- Configure MFA as follows:

  - In the `App passwords` section select `Do not allow users to create app passwords to sign in to non-browser apps`
  - Ensure the `Verification options` are set as follows:
    - **check** `Call to phone` and `Notification through mobile app` (`Call to phone` is not available with a trial P2 licence)
    - **uncheck** `Text message to phone` and `Verification code from mobile app or hardware token`
  - In `Remember multi-factor authentication` section
    - ensure `Allow users to remember multi-factor authentication on devices they trust` is **unchecked**
  - Click "Save" and close window
    <details><summary><b>Screenshots</b></summary>

    ```{image} deploy_shm/aad_mfa_settings.png
    :alt: AAD MFA settings
    :align: center
    ```

    </details>

## 10. {{closed_lock_with_key}} Apply conditional access policies

(roles_system_deployer_shm_require_mfa)=

### Require MFA for all users

```{warning}
Before completing this step, **make sure you have confirmed you are able to successfully log in as the emergency access admin**, as this account will be the only one excluded from the MFA requirement.
```

![Microsoft Entra ID: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Microsoft%20Entra%20ID&color=blue&message=a%20few%20minutes)

- From the Azure portal, navigate to the Microsoft Entra ID you have created.
- Click `Properties` in the left hand sidebar and **disable** security defaults as shown in the screenshot [here](https://docs.microsoft.com/en-us/azure/active-directory/fundamentals/concept-fundamentals-security-defaults)
  - Select `NO` from `Enable Security defaults`
  - Select `My organization is using Conditional Access` and hit the `Save` button
- Click `Security` in the left hand sidebar
- Click `Conditional access` in the left hand sidebar
- Click the `+New Policy` icon in the top bar above the (empty) policy list
- Create a new policy as follows:
  - Set the name to `Require MFA`
  - Under `Users or workload identities` set the `Users and groups` condition to:
    - **Include**: Select `All users`
    - **Exclude**:
      - Check `Users and groups`
      - Select the `Admin - EMERGENCY ACCESS` user
      - Select all `On-Premises Directory Synchronization Service Account` users
      - Click `Select`
  - Under `Cloud apps or actions` select `Cloud apps` in the drop-down menu and set:
    - **Include**: Select `All cloud apps`
    - **Exclude**: Leave unchanged as `None`
  - Leave the `Conditions` condition unchanged (all showing as `Not configured`)
  - Set the `Grant` condition to:
    - Check `Grant access`
    - Check `Require multi-factor authentication`
    - Click `Select`
  - Leave the `Session` condition unchanged
  - Under `Enable policy` select `On`
  - Check `I understand that my account will be impacted by this policy. Proceed anyway.`
  - Click the `Create` button

(roles_system_deployer_shm_block_portal_access)=

### Block portal access for normal users

Most users have no reason to access the Azure portal using the SHM tenant.
Therefore we will block access for all users other than Global Administrators.

![Microsoft Entra ID: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Microsoft%20Entra%20ID&color=blue&message=a%20few%20minutes)

- From the Azure portal, navigate to the Microsoft Entra ID you have created.
- Click `Security` in the left hand sidebar
- Click `Conditional Access` in the left hand sidebar
- Click on `New Policy` at the top of the panel
- Configure the policy as follows
  - In the `Name` field enter `Restrict Microsoft Entra ID access`
  - Under `Users or workload identities` set the `Users and groups` condition to:
    - **Include**: Select `All users`
    - **Exclude**:
      - Check `Directory roles`
      - In the drop-down menu select `Global administrator`.
        This will ensure that only the administrator accounts you created in {ref}`the previous section <roles_deploy_add_additional_admins>` are able to access the portal.
  - Under `Cloud apps or actions` select `Cloud apps` in the drop-down menu and set:
    - **Include**:
      - Select `Select apps`
      - In the pop-up menu on the right, select
        - `Microsoft Azure Management` and
        - `Microsoft Graph PowerShell` then
      - Click `Select`
    - **Exclude**: Leave unchanged as `None`
  - Leave the `Conditions` condition unchanged (all showing as `Not configured`)
  - Under the `Access controls` and `Grant` Headings click `0 controls selected`
    - In the pop-up menu on the right select the `Block Access` radio button and click `Select`
  - Under `Enable policy` select `On`
  - Click the `Create` button

```{error}
Security defaults must be disabled in order to create this policy.
This should have been done when creating a policy to {ref}`require MFA for all users <roles_system_deployer_shm_require_mfa>`.
```

## 11. {{no_pedestrians}} Add MFA licences to any non-admin users

Administrator accounts can use MFA and reset their passwords without a licence needing to be assigned.
However, when you create non-admin users they will need to be assigned an Azure Active Directory licence in order to reset their own password.

### Assigning MFA licences

![Microsoft Entra ID: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Microsoft%20Entra%20ID&color=blue&message=a%20few%20minutes)

- Ensure you are logged in to the Azure Portal in with the **native** administrator account you created.
- Ensure your session is using the new Safe Haven Management (SHM) Microsoft Entra ID.
  The name of the current directory is under your username in the top right corner of the Azure portal screen.
  To change directories click on your username at the top right corner of the screen, then `Switch directory`, then the name of the new SHM directory.
- Click the "hamburger" menu in the top left corner (three horizontal lines) and select `Microsoft Entra ID`
- Click `Licences` in the left hand sidebar
- Click `All products` in the left hand sidebar
- Click the relevant licence product [`Microsoft Entra ID P1` (production) or `Microsoft Entra ID P2` (test)]
- Click `Licensed users` in the left hand sidebar
- Click the `+Assign` icon in the top bar above the list of user licence assignments
- Click `+ Add users and groups` under `Users and groups`
- Click on the users you want to assign licences to
- Click `Select`
- Click `Review + Assign`
- Click `Assign`

</details>

#### Testing password self-reset

- Add a licence to the user you want to test with
- Go to [https://aka.ms/mfasetup](https://aka.ms/mfasetup) in an **incognito / private browsing** tab
- Enter the researcher username
- Click the `Forgotten my password` link
- Enter the captcha text and press next
- Enter your mobile phone number, making sure to prefix it with the country code and to **not include** the leading zero (`+<country-code> <phone-number-without-leading-zero>` e.g. `+44 7700900000`).
- Enter the code that was texted to your phone
- Enter a new password
- Click the `Sign in with new password` link on the following page, or go to [https://aka.ms/mfasetup](https://aka.ms/mfasetup) again
- Enter the username and the new password
- Click `Next` at the `Help us to protect your account` prompt
- Follow the instructions to configure `Microsoft Authenticator`
