(deploy_sre_apache_guacamole)=

# Deploy an SRE with Apache Guacamole

These instructions will walk you through deploying a Secure Research Environment (SRE) that uses an existing Safe Haven Management (SHM) environment.

```{include} snippets/00_symbols.partial.md
:relative-images:
```

## 1. {{seedling}} Prerequisites

```{include} snippets/01_prerequisites.partial.md
:relative-images:
```

(roles_deployer_sre_id)=

## 2. {{clipboard}} Secure Research Environment configuration

```{include} snippets/02_configuration.partial.md
:relative-images:
```

## 3. {{computer}} Deploy SRE

![Powershell: a few hours](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20hours) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Deploy_SRE.ps1 -shmId <SHM ID> -sreId <SRE ID> -VMs <VM sizes>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE
- where `<VM sizes>` is a list of [Azure VM sizes](https://docs.microsoft.com/en-us/azure/virtual-machines/sizes) that you want to create (for example `'Standard_D2s_v3', 'default', 'Standard_NC6s_v3'`)

You will be prompted for credentials for:

- a user with admin rights over the Azure subscriptions you plan to deploy into
- a user with Global Administrator privileges over the SHM Azure Active Active directory

This will perform the following actions, which can be run individually if desired:

<details>
<summary><strong>Remove data from previous deployments</strong></summary>

```{include} snippets/03_01_remove_data.partial.md
:relative-images:
```

</details>

<details>
<summary><strong>Register SRE with the SHM</strong></summary>

```{include} snippets/03_02_register_sre.partial.md
:relative-images:
```

</details>

<details>
<summary><strong>Create SRE DNS Zone</strong></summary>

```{include} snippets/04_01_sre_dns.partial.md
:relative-images:
```

</details>

```{include} snippets/04_02_manual_dns.partial.md
:relative-images:
```

<details>
<summary><strong>Deploy the virtual network</strong></summary>

```{include} snippets/04_03_deploy_vnet.partial.md
:relative-images:
```

</details>

<details>
<summary><strong>Deploy storage accounts</strong></summary>

```{include} snippets/05_storage_accounts.partial.md
:relative-images:
```

</details>

<details>
<summary><strong>Deploy Apache Guacamole remote desktop</strong></summary>

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Setup_SRE_Guacamole_Servers.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM.
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE.

</details>

<details>
<summary><strong>Deploy web applications (CoCalc, CodiMD and GitLab)</strong></summary>

```{include} snippets/07_deploy_webapps.partial.md
:relative-images:
```

</details>

<details>
<summary><strong>Deploy databases</strong></summary>

```{include} snippets/08_databases.partial.md
:relative-images:
```

</details>

<details>
<summary><strong>Deploy Secure Research Desktops (SRDs)</strong></summary>

The `-VmSizes` parameter that you provided to the `Deploy_SRE.ps1` script determines how many SRDs are created and how large each one will be.

```{note}
The following script will be run once for each `<VM size>` that you specified.
If you specify the same size more than once, you will create multiple SRDs of that size.
```

```{include} snippets/09_single_srd.partial.md
:relative-images:
```

</details>

<details>
<summary><strong>Apply network configuration</strong></summary>

```{include} snippets/10_network_lockdown.partial.md
:relative-images:
```

</details>

<details>
<summary><strong>Configure firewall</strong></summary>

```{include} snippets/11_configure_firewall.partial.md
:relative-images:
```

</details>

<details>
<summary><strong>Configure monitoring</strong></summary>

```{include} snippets/12_configure_monitoring.partial.md
:relative-images:
```

</details>

<details>
<summary><strong>Enable backup</strong></summary>

```{include} snippets/13_enable_backup.partial.md
:relative-images:
```

</details>

## 4. {{microscope}} Test deployed SRE

(deploy_sre_apache_guacamole_create_user_account)=

### {{bicyclist}} Verify non-privileged user account is set up

```{include} snippets/06_01_create_user_account.partial.md
:relative-images:
```

(deploy_sre_apache_guacamole_test_remote_desktop)=

### {{pear}} Test the Apache Guacamole remote desktop

- Launch a local web browser on your **deployment machine** and go to `https://<SRE ID>.<safe haven domain>` and log in with the user name and password you set up for the non-privileged user account.
  - For example for `<safe haven domain> = project.turingsafehaven.ac.uk` and `<SRE ID> = sandbox` this would be `https://sandbox.project.turingsafehaven.ac.uk/`
- You should see a screen like the following. If you do not, follow the **troubleshooting** instructions below.

  ```{image} ../roles/researcher/user_guide/guacamole_dashboard.png
  :alt: Guacamole dashboard
  :align: center
  ```

- At this point you should double click on the {{computer}} `Ubuntu0` link under `All Connections` which should bring you to the secure remote desktop (SRD) login screen
- You will need the short-form of the user name (ie. without the `@<safe haven domain>` part) and the same password as before
- This should bring you to the SRD that will look like the following

  ```{image} deploy_sre/guacamole_desktop.png
  :alt: Guacamole dashboard
  :align: center
  ```

```{important}
Ensure that you are connecting from one of the **permitted IP ranges** specified in the `inboundAccessFrom` section of the SRE config file.
For example, if you have authorised a corporate VPN, check that you have correctly configured you client to connect to it.
```

````{error}
If you see an error like the following when attempting to log in, it is likely that the AzureAD application is not registered as an `ID token` provider.

```{image} deploy_sre/guacamole_aad_idtoken_failure.png
:alt: AAD ID token failure
:align: center
```

<details><summary><b>Register AzureAD application</b></summary>

![Azure AD: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=one%20minute)

- From the Azure portal, navigate to the AAD you have created.
- Navigate to `Azure Active Directory > App registrations`, and select the application called `Guacamole SRE <SRE ID>`.
- Click on `Authentication` on the left-hand sidebar
- Ensure that the `ID tokens` checkbox is ticked and click on the `Save` icon if you had to make any changes
  ```{image} deploy_sre/guacamole_aad_app_registration_idtoken.png
  :alt: AAD app registration
  :align: center
  ```
</details>
````

### {{snowflake}} Test CoCalc, CodiMD and GitLab servers

- Connect to the remote desktop {ref}`using the instructions above <deploy_sre_apache_guacamole_test_remote_desktop>`
- Test `CoCalc` by clicking on the `CoCalc` desktop icon.
  - This should open a web browser inside the remote desktop
  - You will get a warning about a `Potential Security Risk` related to a self-signed certificate. It is safe to trust this by selecting `Advanced > Accept the risk and continue`.
  - Create a new username and password and use this to log in.
- Test `CodiMD` by clicking on the `CodiMD` desktop icon.
  - This should open a web browser inside the remote desktop
  - Log in with the short-form `username` of a user in the `SG <SRE ID> Research Users` security group.
- Test `GitLab` by clicking on the `GitLab` desktop icon.
  - This should open a web browser inside the remote desktop
  - Log in with the short-form `username` of a user in the `SG <SRE ID> Research Users` security group.

### {{fire}} Run smoke tests on SRD

```{include} snippets/14_run_smoke_tests.partial.md
:relative-images:
```
