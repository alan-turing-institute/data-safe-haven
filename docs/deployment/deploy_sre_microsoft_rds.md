(deploy_sre_microsoft_rds)=

# Deploy an SRE with Microsoft RDS

These instructions will walk you through deploying a Secure Research Environment (SRE) that uses an existing Safe Haven Management (SHM) environment.

```{important}
If you are deploying a {ref}`policy_tier_0` or {ref}`policy_tier_1` environment, or a development environment, we would suggest deploying with {ref}`Guacamole <deploy_sre_apache_guacamole>`.
```

```{include} snippets/00_symbols.partial.md
:relative-images:
```

## 1. {{seedling}} Prerequisites

```{include} snippets/01_prerequisites.partial.md
:relative-images:
```

### VPN connection to the SHM VNet

For some operations, you will need to log on to some of the VMs that you deploy and make manual changes.
This is done using the VPN which should have been deployed {ref}`when setting up the SHM environment <deploy_shm_vpn>`.

## 2. {{clipboard}} Secure Research Environment configuration

```{include} snippets/02_configuration.partial.md
:relative-images:
```

## 3. {{cop}} Prepare SHM environment

### (Optional) {{fast_forward}} Remove data from previous deployments

```{include} snippets/03_01_remove_data.partial.md
:relative-images:
```

### {{registered}} Register SRE with the SHM

```{include} snippets/03_02_register_sre.partial.md
:relative-images:
```

## 4. {{station}} Deploy networking components

### {{clubs}} Create SRE DNS Zone

```{include} snippets/04_01_sre_dns.partial.md
:relative-images:
```

```{include} snippets/04_02_manual_dns.partial.md
:relative-images:
```

### {{ghost}} Deploy the virtual network

```{include} snippets/04_03_deploy_vnet.partial.md
:relative-images:
```

## 5. {{floppy_disk}} Deploy storage accounts

```{include} snippets/05_storage_accounts.partial.md
:relative-images:
```

(deploy_sre_microsoft_deploy_remote_desktop)=

## 6. {{satellite}} Deploy remote desktop

### {{tropical_fish}} Deploy the remote desktop servers

![Powershell: fifty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=fifty%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Setup_SRE_Remote_Desktop.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE

```{error}
If you encounter errors with the deployment of the remote desktop servers, re-running `Setup_SRE_Remote_Desktop.ps1` should fix them.
If this does not work, please try deleting everything that has been deployed into the `RG_SHM_<SHM ID>_SRE_<SRE ID>_REMOTE_DESKTOP` resource group for this SRE and {ref}`attempt to run this step again <deploy_sre_microsoft_deploy_remote_desktop>`.
```

### {{satellite}} Configure RDS webclient

![Remote: twenty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=twenty%20minutes)

- Navigate to the **RDS Gateway** VM in the portal at `Resource Groups > RG_SHM_<SHM ID>_SRE_<SRE ID>_REMOTE_DESKTOP > RDG-SRE-<SRE ID>` and note the `Private IP address` for this VM
- Log into the **RDS Gateway** (`RDG-SRE-<SRE ID>`) VM using this `private IP address` together with the same `<admin login>` and `<admin password>` that you used to {ref}`log into the SHM domain controller <roles_system_deployer_shm_remote_desktop>`.
- Run the following command on the RDS VM to configure the remote desktop environment

```powershell
PS> C:\Installation\Deploy_RDS_Environment.ps1
```

```{caution}
This script cannot be run remotely since remote `Powershell` runs as a local admin but this script has to be run as a domain admin.
```

```{error}
![Windows](https://img.shields.io/badge/-555?&logo=windows&logoColor=white) when deploying on Windows, the SHM VPN needs to be redownloaded/reconfigured each time an SRE is deployed.
Otherwise, there may be difficulties connecting to the **RDS Gateway**.
```

### {{closed_lock_with_key}} Secure RDS webclient

![Powershell: fifteen minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=fifteen%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Secure_SRE_Remote_Desktop_Gateway.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE

This will perform the following actions, which can be run individually if desired:

#### Disable insecure TLS connections

<details>
<summary><strong>Details</strong></summary>

![Powershell: five minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=five%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Disable_Legacy_TLS.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE

```{tip}
If additional TLS protocols become available (or existing ones are found to be insecure) during the lifetime of the SRE, then you can re-run `./Disable_Legacy_TLS.ps1` to update the list of accepted protocols
```

</details>

(deploy_sre_microsoft_rds_configure_cap_rap)=

#### Configure RDS CAP and RAP settings

<details>
<summary><strong>Details</strong></summary>

![Powershell: five minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=five%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Configure_SRE_RDS_CAP_And_RAP.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE

</details>

(deploy_sre_microsoft_update_ssl_certificate)=

#### Update SSL certificate

<details>
<summary><strong>Details</strong></summary>

![Powershell: five minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=five%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Update_SRE_RDS_SSL_Certificate.ps1 -shmId <SHM ID> -sreId <SRE ID> -emailAddress <email>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE
- where `<email>` is an email address that you want to be notified when certificates are close to expiry

```{tip}
`./Update_SRE_RDS_SSL_Certificate.ps1` should be run again whenever you want to update the certificate for this SRE.
```

```{caution}
`Let's Encrypt` will only issue **5 certificates per week** for a particular host (e.g. `rdg-sre-sandbox.project.turingsafehaven.ac.uk`).
To reduce the number of calls to `Let's Encrypt`, the signed certificates are stored in the Key Vault for easy redeployment.
For production environments this should usually not be an issue.
```

````{important}
If you find yourself frequently redeploying a test environment and hit the `Let's Encrypt` certificate limit, you can can use:

```powershell
> ./Update_SRE_RDS_SSL_Certificate.ps1 -dryRun $true
```

to use the `Let's Encrypt` staging server, which will issue certificates more frequently.
These certificates will **not** be trusted by your browser, and so should not be used in production.
````

</details>

### {{bicyclist}} Verify non-privileged user account is set up

```{include} snippets/06_01_create_user_account.partial.md
:relative-images:
```

### {{nut_and_bolt}} Test the Microsoft RDS remote desktop

- Launch a local web browser on your **deployment machine** and go to `https://<SRE ID>.<safe haven domain>` and log in with the user name and password you set up for the non-privileged user account.
  - For example for `<safe haven domain> = project.turingsafehaven.ac.uk` and `<SRE ID> = sandbox` this would be `https://sandbox.project.turingsafehaven.ac.uk/`
- You should see a screen like the following. If you do not, follow the **troubleshooting** instructions below.

  ```{image} deploy_sre/msrds_desktop.png
  :alt: Microsoft RDS desktop
  :align: center
  ```

```{important}
Ensure that you are connecting from one of the **permitted IP ranges** specified in the `inboundAccessFrom` section of the SRE config file.
For example, if you have authorised a corporate VPN, check that you have correctly configured you client to connect to it.
```

```{note}
Clicking on the apps will not work until the other servers have been deployed.
```

```{error}
If you get a `404 resource not found` error when accessing the webclient URL, it is likely that the RDS webclient failed to install correctly.
- Go back to the previous section and rerun the `C:\Installation\Deploy_RDS_Environment.ps1` script on the RDS gateway.
- After doing this, follow the instructions to {ref}`configure RDS CAP and RAP settings <deploy_sre_microsoft_rds_configure_cap_rap>` and to {ref}`update the SSL certificate <deploy_sre_microsoft_update_ssl_certificate>`.
```

```{error}
If you get an `unexpected server authentication certificate error` , your browser has probably cached a previous certificate for this domain.
- Do a [hard reload](https://www.getfilecloud.com/blog/2015/03/tech-tip-how-to-do-hard-refresh-in-browsers/) of the page (permanent fix)
- OR open a new private / incognito browser window and visit the page.
```

```{error}
If you can see an empty screen with `Work resources` but no app icons, your user has not been correctly added to the security group.
- Ensure that the user you have logged in with is a member of the `SG <SRE ID> Research Users` group on the domain controller
```

## 7. {{snowflake}} Deploy web applications (CoCalc, CodiMD and GitLab)

```{include} snippets/07_deploy_webapps.partial.md
:relative-images:
```

### {{microscope}} Test CoCalc, CodiMD and GitLab servers

- Launch a local web browser on your **deployment machine** and go to `https://<SRE ID>.<safe haven domain>` and log in with the user name and password you set up for the non-privileged user account.
  - for example for `<safe haven domain> = project.turingsafehaven.ac.uk` and `<SRE ID> = sandbox` this would be `https://sandbox.project.turingsafehaven.ac.uk/`
- Test `CoCalc` by clicking on the `CoCalc` app icon.
  - You should receive an MFA request to your phone or authentication app.
  - Once you have approved the sign in, you should see a Chrome window with the CoCalc login page.
  - You will get a warning about a `Potential Security Risk` related to a self-signed certificate. It is safe to trust this by selecting `Advanced > Accept the risk and continue`.
  - Create a new username and password and use this to log in.
- Test `CodiMD` by clicking on the `CodiMD` app icon.
  - You should receive an MFA request to your phone or authentication app.
  - Once you have approved the sign in, you should see a Chrome window with the GitLab login page.
  - Log in with the short-form `username` of a user in the `SG <SRE ID> Research Users` security group.
- Test `GitLab` by clicking on the `GitLab` app icon.
  - You should receive an MFA request to your phone or authentication app.
  - Once you have approved the sign in, you should see a Chrome window with the GitLab login page.
  - Log in with the short-form `username` of a user in the `SG <SRE ID> Research Users` security group.
- If you do not get an MFA prompt or you cannot connect to one of the servers, follow the **troubleshooting** instructions below.

```{error}
If you can log in to the initial webclient authentication but do not get the MFA request, then the issue is likely that the configuration of the connection between the SHM NPS server and the RDS Gateway server is not correct.

In order to diagnose whether this is an issue with the NPS settings or the MFA connection, run the diagnostic script on the NPS server at `C:\Installation\MFA_NPS_Troubleshooter.ps1` and follow the instructions there.

If the "Checking if Azure MFA SPN exists" test fails, then run `C:\Installation\Ensure_MFA_SP_AAD.ps1` to restore it.
```

```{error}
If running the previous script did not help to diagnose the issue then try the following:

- Ensure that both the SHM NPS server and the RDS Gateway are running
- Follow the instructions to {ref}`configure RDS CAP and RAP settings <deploy_sre_microsoft_rds_configure_cap_rap>` to reset the configuration of the RDS gateway and NPS VMs.
- Ensure that the default UDP ports `1812`, `1813`, `1645` and `1646` are all open on the SHM NPS network security group (`NSG_SHM_SUBNET_IDENTITY`). [This documentation](<https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/dd316134(v=ws.10)>) gives further details.
```

```{error}
If this does not resolve the issue, trying checking the Windows event logs

- Use `Event Viewer` on the SRE RDS Gateway (`Custom views > Server roles > Network Policy and Access Services`) to check whether the NPS server is contactable and whether it is discarding requests
- Use `Event Viewer` on the SHM NPS server (`Custom views > Server roles > Network Policy and Access Services`) to check whether NPS requests are being received and whether the NPS server has an LDAP connection to the SHM DC.
  - Ensure that the requests are being received from the **private** IP address of the RDS Gateway and **not** its public one.
- One common error on the NPS server is `A RADIUS message was received from the invalid RADIUS client IP address x.x.x.x` . [This help page](<https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/dd316135(v=ws.10)>) might be useful.
  - This may indicate that the NPS server could not join the SHM domain. Try `ping DC1-SHM-<SHM ID>` from the NPS server and if this does not resolve, try rebooting it.
- Ensure that the `Windows Firewall` is set to `Domain Network` on both the SHM NPS server and the SRE RDS Gateway
```

```{error}
If you get a `We couldn't connect to the gateway because of an error` message, it's likely that the `Remote RADIUS Server` authentication timeouts have not been set correctly.
- Follow the instructions to {ref}`configure RDS CAP and RAP settings <deploy_sre_microsoft_rds_configure_cap_rap>` to reset the authentication timeouts on the RDS gateway.
```

```{error}
If you get multiple MFA requests with no change in the `Opening ports` message, it may be that the shared RADIUS secret does not match on the SHM server and SRE RDS Gateway.
- Follow the instructions to {ref}`configure RDS CAP and RAP settings <deploy_sre_microsoft_rds_configure_cap_rap>` to reset the secret on both the RDS gateway and NPS VMs.
- Alternatively, this can happen if the NPS secret stored in the Key Vault is too long. We found that a 20 character secret caused problems but the (default) 12 character secret works.
```

## 8. {{baseball}} Deploy databases

```{include} snippets/08_databases.partial.md
:relative-images:
```

## 9. {{computer}} Deploy secure research desktops (SRDs)

```{include} snippets/09_single_srd.partial.md
:relative-images:
```

```{hint}
If desired, you can also provide a VM size by passing the optional `-vmSize` parameter.
```

If you want to deploy several SRDs, simply repeat the above steps with a different IP address last octet.

```{important}
The initial shared `SRD Main` shared VM should be deployed with the last octet `160` as the dashboard is hard-coded to expect this.
```

## 10. {{lock}} Apply network configuration

```{include} snippets/10_network_lockdown.partial.md
:relative-images:
```

## 11. {{fire_engine}} Configure firewall

```{include} snippets/11_configure_firewall.partial.md
:relative-images:
```

## 12. {{chart_with_upwards_trend}} Configure logging

```{include} snippets/12_configure_monitoring.partial.md
:relative-images:
```

## 13. {{left_right_arrow}} Enable backup

```{include} snippets/13_enable_backup.partial.md
:relative-images:
```

## 14. {{fire}} Run smoke tests on SRD

```{include} snippets/14_run_smoke_tests.partial.md
:relative-images:
```
