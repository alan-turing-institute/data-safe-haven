(deploy_sre_apache_guacamole)=

# Secure Research Environment Build Instructions (Guacamole remote desktop)

These instructions will walk you through deploying a Secure Research Environment (SRE) that uses an existing Safe Haven Management (SHM) environment.

```{include} snippets/00_symbols.partial.md
:relative-images:
```

```{include} snippets/01_prerequisites.partial.md
:relative-images:
```

(roles_deployer_sre_id)=

```{include} snippets/02_configuration.partial.md
:relative-images:
```

## 3. {{computer}} Deploy SRE

![Powershell: a few hours](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20hours) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Deploy_SRE.ps1 -shmId <SHM ID> -sreId <SRE ID> -tenantId <AAD tenant ID> -VMs <VM sizes>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>`for this SRE
- where `<AAD tenant ID>` is the {ref}`tenant ID <roles_deployer_aad_tenant_id>` for the AzureAD that you created during SHM deployment
- where `<VM sizes>` is a list of [Azure VM sizes](https://docs.microsoft.com/en-us/azure/virtual-machines/sizes) that you want to create (for example `'Standard_D2s_v3', 'default', 'Standard_NC6s_v3'`)

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
PS> ./Setup_SRE_Guacamole_Servers.ps1 -shmId <SHM ID> -sreId <SRE ID> -tenantId <tenant ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>`for this SRE
- where `<AAD tenant ID>` is the `Tenant ID` for the AzureAD that you [created during SHM deployment](deploy_shm.md#get-the-azure-active-directory-tenant-id)
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
<summary><strong>Deploy data science VMs</strong></summary>

The following script will be run **once for each VM** that you specified using the `-VmSizes` parameter to the `Deploy_SRE.ps1` script

```{include} snippets/09_single_dsvm.partial.md
:relative-images:
```

```{note}
The `<VM size>` used for each compute VM size will be the one provided in the `-VmSizes` parameter to the `Deploy_SRE.ps1` script
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
<summary><strong>Configure logging</strong></summary>

```{include} snippets/12_configure_logging.partial.md
:relative-images:
```

</details>

## 4. {{microscope}} Test deployed SRE

(deploy_sre_apache_guacamole_create_user_account)=

### {{bicyclist}} Verify non-privileged user account is set up

```{include} snippets/06_01_create_user_account.partial.md
:relative-images:
```

### {{pear}} Test the Apache Guacamole remote desktop

```{include} snippets/06_02_test_rds.partial.md
:relative-images:
```

- Launch a local web browser on your **deployment machine** and go to `https://<SRE ID>.<safe haven domain>` and log in with the user name and password you set up for the non-privileged user account.
  - For example for `<safe haven domain> = project.turingsafehaven.ac.uk` and `<SRE ID> = sandbox` this would be `https://sandbox.project.turingsafehaven.ac.uk/`
- You should see a screen like the following. If you do not, follow the **troubleshooting** instructions below.
  ```{image} ../researcher/user_guide/guacamole_dashboard.png
  :alt: Guacamole dashboard
  :align: center
  ```
- At this point you should double click on the {{computer}} `Ubuntu0` link under `All Connections` which should bring you to an Ubuntu login screen
- You will need the short-form of the user name (ie. without the `@<safe haven domain>` part) and the same password as before
- This should bring you to an Ubuntu desktop that will look like the following
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

- Connect to the remote desktop [using the instructions above](#test-the-apache-guacamole-remote-desktop)
- Test `CoCalc` by clicking on the `CoCalc` desktop icon.
  - This should open a web browser inside the remote desktop
  - Log in with the short-form `username` of a user in the `SG <SRE ID> Research Users` security group.
- Test `CodiMD` by clicking on the `CodiMD` desktop icon.
  - This should open a web browser inside the remote desktop
  - Log in with the short-form `username` of a user in the `SG <SRE ID> Research Users` security group.
- Test `GitLab` by clicking on the `GitLab` desktop icon.
  - This should open a web browser inside the remote desktop
  - Log in with the short-form `username` of a user in the `SG <SRE ID> Research Users` security group.

### {{fire}} Run smoke tests on DSVM

```{include} snippets/13_run_smoke_tests.partial.md
:relative-images:
```
