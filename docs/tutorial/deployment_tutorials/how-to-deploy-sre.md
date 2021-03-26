# Secure Research Environment Build Instructions

These instructions will walk you through deploying a Secure Research Environment (SRE) that uses an existing Safe Haven Management (SHM) environment.

> :warning: If you are deploying a Tier 1 environment, follow [these instructions](./how-to-deploy-sre-tier1.md) instead.

## Contents

+ [:seedling: 1. Prerequisites](#seedling-1-prerequisites)
  + [:beginner: Software](#beginner-software)
  + [:key: VPN connection to the SHM VNet](#key-vpn-connection-to-the-shm-vnet)
  + [:name_badge: SRE domain name](#name_badge-sre-domain-name)
  + [:arrow_double_up: Deploying multiple SREs in parallel](#arrow_double_up-deploying-multiple-sres-in-parallel)
+ [:clipboard: 2. Secure Research Environment configuration](#clipboard-2-secure-research-environment-configuration)
  + [:apple: SHM configuration properties](#apple-shm-configuration-properties)
  + [:green_apple: SRE configuration properties](#green_apple-sre-configuration-properties)
  + [:bouquet: Verify code version](#bouquet-optional-verify-code-version)
  + [:full_moon: View full SRE configuration](#full_moon-optional-view-full-sre-configuration)
+ [:cop: 3. Prepare SHM environment](#cop-3-prepare-shm-environment)
  + [:fast_forward: Optional: Remove data from previous deployments](#fast_forward-optional-remove-data-from-previous-deployments)
  + [:registered: Register SRE with the SHM](#registered-register-sre-with-the-shm)
+ [:station: 4. Deploy networking components](#station-4-deploy-networking-components)
  + [:clubs: Create SRE DNS Zone](#clubs-create-sre-dns-zone)
  + [:ghost: Deploy the virtual network](#ghost-deploy-the-virtual-network)
+ [:fishing_pole_and_fish: 5. Deploy remote desktop](#fishing_pole_and_fish-5-deploy-remote-desktop)
  + [:tropical_fish: Deploy the remote desktop servers](#tropical_fish-deploy-remote-desktop-servers)
  + [:satellite: Configure RDS webclient](#satellite-configure-rds-webclient)
  + [:closed_lock_with_key: Secure RDS webclient](#closed_lock_with_key-secure-rds-webclient)
  + [:bicyclist: Set up a non-privileged user account](#bicyclist-optional-set-up-a-non-privileged-user-account)
  + [:microscope: Test the RDS using a non-privileged user account](#mountain_bicyclist-test-the-rds-using-a-non-privileged-user-account)
+ [:snowflake: 6. Deploy web applications (GitLab and CodiMD)](#snowflake-6-deploy-web-applications-gitlab-and-CodiMD)
  + [:microscope: Test GitLab Server](#microscope-test-gitlab-server)
  + [:microscope: Test CodiMD Server](#microscope-test-codimd-server)
+ [:floppy_disk: 7. Deploy storage accounts](#floppy_disk-7-deploy-storage-accounts)
+ [:baseball: 8. Deploy databases](#baseball-8-deploy-databases)
+ [:computer: 9. Deploy data science VMs](#computer-9-deploy-data-science-vms)
  + [:fast_forward: Optional: Customise the deployed VM](#fast_forward-optional-customise-the-deployed-vm)
  + [:computer: Deploy a single data science VM (DSVM)](#computer-deploy-a-single-data-science-vm-dsvm)
+ [:lock: 10. Apply network configuration](#lock-10-apply-network-configuration)
+ [:fire_engine: 11. Deploy firewall](#fire_engine-11-deploy-firewall)
+ [:chart_with_upwards_trend: 12. Configure logging](#chart_with_upwards_trend-12-configure-logging)
+ [:fire: 13. Run smoke tests on DSVM](#fire-13-run-smoke-tests-on-dsvm)

## Explanation of symbols used in this guide

![Powershell](https://img.shields.io/badge/local-estimate%20of%20time%20needed-blue?logo=powershell&style=for-the-badge)
+ This indicates a `Powershell` command which you will need to run locally on your machine
+ Ensure you have checked out the appropriate version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
+ Open a `Powershell` terminal and navigate to the indicated directory of your locally checked-out version of the Safe Haven repository
+ Ensure that you are logged into Azure by running the `Connect-AzAccount` command
  + :pencil: If your account is a guest in additional Azure tenants, you may need to add the `-Tenant <Tenant ID>` flag, where `<Tenant ID>` is the ID of the Azure tenant you want to deploy into.
+ This command will give you a URL and a short alphanumeric code.
  + You will need to visit that URL in a web browser, enter the code and log in to your account on Azure
  + :pencil: If you have several Azure accounts, make sure you use one that has permissions to make changes to the subscription you are using

![Remote](https://img.shields.io/badge/remote-estimate%20of%20time%20needed-blue?logo=microsoft-onedrive&style=for-the-badge)
+ This indicates a command which you will need to run remotely on an Azure virtual machine (VM) using `Microsoft Remote Desktop`
+ Open `Microsoft Remote Desktop` and click `Add Desktop` / `Add PC`
+ Enter the private IP address of the VM that you need to connect to in the `PC name` field (this can be found by looking in the Azure portal)
+ Enter the name of the VM (for example `DC1-SHM-TESTA`) in the `Friendly name` field
+ Click `Add`
+ Ensure you are connected to the SHM VPN that you have set up
+ Double click on the desktop that appears under `Saved Desktops` or `PCs`.
+ Use the `username` and `password` specified by the appropriate section of the guide
+ :pencil: If you see a warning dialog that the certificate cannot be verified as root, accept this and continue.

![Azure Portal](https://img.shields.io/badge/portal-estimate%20of%20time%20needed-blue?logo=microsoft-azure&style=for-the-badge)
+ This indicates an operation which needs to be carried out in the [`Azure Portal`](https://portal.azure.com) using a web browser on your local machine.
+ You will need to login to the portal using an account with privileges to make the necessary changes to the resources you are altering

:pencil: **Notes**
+ This indicates some explanatory notes or examples that provide additional context for the current step.

:warning: **Troubleshooting**
+ This indicates a set of troubleshooting instructions to help diagnose and fix common problems with the current step.

![macOS](https://img.shields.io/badge/-555?&logo=apple&logoColor=white)![Windows](https://img.shields.io/badge/-555?&logo=windows&logoColor=white)![Linux](https://img.shields.io/badge/-555?&logo=linux&logoColor=white)
+ These indicate steps that depend on the OS that you are using to deploy the SRE


## :seedling: 1. Prerequisites

+ An `SHM environment` that has already been deployed in Azure
  + Follow the [Safe Haven Management (SHM) deployment guide](how-to-deploy-shm.md) if you have not done so already.
+ All [prerequisites needed for deploying the SHM](how-to-deploy-shm.md#prerequisites)
+ An [Azure subscription](https://portal.azure.com) with sufficient credits to build the environment in.
  + This can be the same or different from the one where the SHM is deployed
  + Ensure that the **Owner** of the subscription is an Azure Security group that all administrators can be added to.
  + :maple_leaf: We recommend around $1,000 as a reasonable starting point.
  + :maple_leaf: We recommend using separate Azure Active Directories for users and administrators
+ Access to a global administrator account on the SHM Azure Active Directory


### :key: VPN connection to the SHM VNet

For some operations, you will need to log on to some of the VMs that you deploy and make manual changes. This is done using the VPN which should have been deployed [when setting up the SHM environment](how-to-deploy-shm.md#download-a-client-vpn-certificate-for-the-safe-haven-management-network).

### :name_badge: SRE domain name

You will need access to a public routable domain name for the SRE and its name servers. This can be a subdomain of the Safe Haven Management domain, e.g, `sandbox.testb.dsgroupdev.co.uk` , or a top-level domain (eg. `dsgroup100.co.uk` ).

### :arrow_double_up: Deploying multiple SREs in parallel

> :warning: You can only deploy to **one SRE at a time** from a given computer as the `Az` Powershell module can only work within one Azure subscription at a time.

If you need to deploy multiple SREs in parallel you will need to use multiple computers. These can be different physical computers or you can provision dedicated deployment VMs - this is beyond the scope of this guide.

## :clipboard: 2. Secure Research Environment configuration

The full configuration details for a new SRE are generated by defining a few "core" properties for the new SRE and the management environment in which it will be deployed.

### Secure research environment ID

Choose a short ID `<SRE ID>` to identify the secure research environment (e.g. `sandbox`). This can have a **maximum of seven alphanumeric characters**.

The core properties for the relevant pre-existing Safe Haven Management (SHM) environment must be defined in a JSON file named `shm_<SHM ID>_core_config.json` in the `environment_configs/core` folder.
The core properties for the secure research environment (SRE) must be defined in a JSON file named `sre_<SHM ID><SRE ID>_core_config.json` in the `environment_configs/core` folder.

The following core SRE properties are required - look at `sre_testasandbox_core_config.json` to see an example.

``` json
{
    "sreId": "The <SRE ID> that you decided on above (eg. 'sandbox').",
    "tier": "The data classification tier for the SRE. This controls the outbound network restrictions on the SRE and which mirror set the SRE is peered with",
    "nexus": "[Optional, Bool] Whether to use a Nexus repository as a proxy to PyPI and CRAN. Defaults to true if tier is 2 and false otherwise.",
    "shmId": "The <SHM ID> that you decided on above (eg. 'testa').",
    "subscriptionName": "Azure subscription that the SRE will be deployed into.",
    "ipPrefix": "The three octet IP address prefix for the Class A range used by the management environment. See below for suggestion on how to set this",
    "inboundAccessFrom": "A comma-separated string of IP ranges (addresses or CIDR ranges) from which access to the RDS webclient is permitted. See below for suggestion on how to set this.",
    "outboundInternetAccess": "Whether to allow outbound internet access from inside the remote desktop environment. Either ('Yes', 'Allow', 'Permit'), ('No', 'Deny', 'Forbid') or 'default' (for Tier 0 and 1 'Allow' otherwise 'Deny')",
    "computeVmImage": {
        "type": "The name of the Compute VM image (most commonly 'Ubuntu')",
        "version": "The version of the Compute VM image (e.g. 0.1.2019082900)",
    },
    "dataAdminIpAddresses": "[Optional] A list of one or more IP addresses which admins will be using to transfer sensitive data to/from the secure Azure storage area (if not specified then Turing IP addresses will be used).",
    "azureAdminGroupName" : "[Optional] Azure Security Group that admins of this SRE will belong to. If not specified then the same one as the SHM will be used.",
    "domain": "[Optional] The fully qualified domain name for the SRE. If not specified then <SRE ID>.<SHM domain> will be used.",
    "databases": "[Optional] A list of one or more database flavours from the following list ('MSSQL', 'PostgreSQL'). For example ['MSSQL', 'PostgreSQL'] would deploy both an MS-SQL and a PostgreSQL database.",
    "overrides": "[Optional, Advanced] Do not use this unless you know what you're doing! If you want to override any of the default settings, you can do so by creating the same JSON structure that would be found in the final config file and nesting it under this entry. For example, to change the name of the Key Vault secret containing the MSSQL admin password, you could use something like: 'sre: { databases: { dbmssql: { adminPasswordSecretName: my-password-name } } }'"
}
```

#### :pencil: Notes
+ When deciding on what to set the `inboundAccessFrom` field to, we recommend the following settings:
  + Tier 0/1 SREs: this can be set to 'Internet', allowing access from anywhere.
  + Tier 2 SREs: this should correspond to the **organisational networks** (including guest networks) for all approved partner organisations (i.e. any network managed by the organsiation, such as `EduRoam`, `Turing Guest`, `Turing Secure` etc)
  + Tier 3 SREs: this should correspond to the **restricted networks** for all approved partner organisations. These should only permit connections from within medium security access controlled physical spaces and from managed devices (e.g. `Turing Secure`).
+ Setting `inboundAccessFrom` to 'default' will use the default Turing network ranges.
+ The `ipPrefix` must be unique for each SRE attached to the same SHM.
+ Each SRE should use a `/21` subspace of the `10.0.0.0/24` private class A range, starting from `10.21.0.0` to cleanly avoid the space already occupied by the SHM `10.0.1.0 - 10.0.7.255` and the mirrors (`10.20.2.0-10.20.3.255`).
  + It is very important that address spaces do not overlap in the environment as this will cause network faults. This means that prefixes must differ by at least 8 in their third octet.
  + This provides ample addresses for a SRE and capacity to add additional subnets should that be required in the future.

### :bouquet: (Optional) Verify code version
In order to confirm which version of the data safe haven you are currently using, you can run the following commands.

![Powershell](https://img.shields.io/badge/local-a%20few%20seconds-blue?logo=powershell&style=for-the-badge)

```pwsh
git fetch; git pull; git status; git log -1 --pretty="At commit %h (%H)"
```

This will verify that you are on the correct branch and up to date with `origin`. You can include this confirmation in any record you keep of your deployment.

### :full_moon: Optional: View full SRE configuration

A full configuration, which will be used in subsequent steps, will be automatically generated from your core configuration. Should you wish to, you can print the full SRE config by running the following Powershell command:

![Powershell](https://img.shields.io/badge/local-a%20few%20seconds-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment`

```pwsh
./ShowConfigFile.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE


## :cop: 3. Prepare SHM environment

### :fast_forward: Optional: Remove data from previous deployments

If you are redeploying an SRE in the same subscription and did not use the `./SRE_Teardown.ps1` script to clean up the previous deployment, then there may be residual SRE data in the SHM. If the subscription is not empty, confirm that it is not being used before deleting any resources in it. Clear any remaining SRE data from the SHM by running

![Powershell](https://img.shields.io/badge/local-a%20few%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Remove_SRE_Data_From_SHM.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE

### :registered: Register SRE with the SHM

![Powershell](https://img.shields.io/badge/local-a%20few%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Setup_SRE_Key_Vault_And_Users.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE

This step will register service accounts with the SHM and also create a Key Vault in the SRE subscription (at `Resource Groups > RG_SHM_<SHM ID>_SRE_<SRE ID>_SECRETS > kv-<SHM ID>-sre-<SRE ID>`).

## :station: 4. Deploy networking components

### :clubs: Create SRE DNS Zone

![Powershell](https://img.shields.io/badge/local-one%20minute-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Setup_SRE_DNS_Zone.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE

#### :warning: Troubleshooting
+ If you see a message `You need to add the following NS records to the parent DNS system for...` you will need to manually add the specified NS records to the parent's DNS system, as follows:

<details><summary><b>Instructions for manually creating SRE DNS records</b></summary>

+ To find the required values for the NS records on the portal, click `All resources` in the far left panel, search for "DNS Zone" and locate the DNS Zone with SRE's domain. The NS record will list 4 Azure name servers.
  <p align="center">
    <img src="../../images/deploy_sre/subdomain_ns_record.png" width="80%" title="subdomain_ns_record"/>
  </p>
+ Duplicate these records to the parent DNS system as follows:
  + If the parent domain has an Azure DNS Zone, create an NS record set in this zone.
    + The name should be set to the subdomain (e.g. `sandbox` ) or `@` if using a custom domain, and the values duplicated from above.
    + For example, for a new subdomain `sandbox.testa.dsgroupdev.co.uk` , duplicate the NS records from the Azure DNS Zone `sandbox.testa.dsgroupdev.co.uk` to the Azure DNS Zone for `testa.dsgroupdev.co.uk` , by creating a record set with name `sandbox` .
  + If the parent domain is outside of Azure, create NS records in the registrar for the new domain with the same value as the NS records in the new Azure DNS Zone for the domain.
</details>

### :ghost: Deploy the virtual network

![Powershell](https://img.shields.io/badge/local-five%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./deployment/secure_research_environment/setup/Setup_SRE_Networking.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE

#### :pencil: Notes
The VNet peerings may take a few minutes to provision after the script completes.

## :fishing_pole_and_fish: 5. Deploy remote desktop

### :tropical_fish: Deploy the remote desktop servers

![Powershell](https://img.shields.io/badge/local-fifty%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Setup_SRE_Remote_Desktop.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE

#### :warning: Troubleshooting
If you encounter errors with the deployment of the remote desktop servers, re-running `Setup_SRE_Remote_Desktop.ps1` should fix them. If this does not work, please try deleting everything that has been deployed into the `RG_SHM_<SHM ID>_SRE_<SRE ID>_RDS` resource group for this SRE and [attempt to rerun this step again](#tropical_fish-deploy-remote-desktop-servers).

### :satellite: Configure RDS webclient

![Remote](https://img.shields.io/badge/remote-twenty%20minutes-blue?logo=microsoft-onedrive&style=for-the-badge)

+ Navigate to the **RDS Gateway** VM in the portal at `Resource Groups > RG_SHM_<SHM ID>_SRE_<SRE ID>_RDS > RDG-SRE-<SRE ID>` and note the `Private IP address` for this VM
+ Log into the **RDS Gateway** (`RDG-SRE-<SRE ID>`) VM using this `private IP address` together with the same `<admin login>` and `<admin password>` that you used to [log into the SHM domain controller](how-to-deploy-shm.md#configure-the-first-domain-controller-via-remote-desktop)

you used for logging into the **SHM domain controller**
+ Run the following command on the RDS VM to configure the remote desktop environment

```pwsh
C:\Installation\Deploy_RDS_Environment.ps1
```

#### :pencil: Notes
This script cannot be run remotely since remote `Powershell` runs as a local admin but this script has to be run as a domain admin.

#### :warning: Troubleshooting
![Windows](https://img.shields.io/badge/-555?&logo=windows&logoColor=white) when deploying on Windows, the SHM VPN needs to be redownloaded/reconfigured each time an SRE is deployed. Otherwise, there may be difficulties connecting to the **RDS Gateway**.

### :closed_lock_with_key: Secure RDS webclient

![Powershell](https://img.shields.io/badge/local-fifteen%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Secure_SRE_Remote_Desktop_Gateway.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE

This will perform the following actions, which can be run individually if desired:

<details>
<summary><strong>Disable insecure TLS connections</strong></summary>

![Powershell](https://img.shields.io/badge/local-five%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Disable_Legacy_TLS.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE

#### :pencil: Notes
If additional TLS protocols become available (or existing ones are found to be insecure) during the lifetime of the SRE, then you can re-run this script to update the list of accepted protocols

</details>

<details>
<summary><strong>Configure RDS CAP and RAP settings</strong></summary>

![Powershell](https://img.shields.io/badge/local-five%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Configure_SRE_RDS_CAP_And_RAP.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE

</details>

<details>
<summary><strong>Update SSL certificate</strong></summary>

![Powershell](https://img.shields.io/badge/local-five%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Update_SRE_RDS_SSL_Certificate.ps1 -shmId <SHM ID> -sreId <SRE ID> -emailAddress <email>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE
- where `<email>` is an email address that you want to be notified when certificates are close to expiry

#### :pencil: Notes
This script should be run again whenever you want to update the certificate for this SRE.

#### :warning: Troubleshooting
Let's Encrypt will only issue **5 certificates per week** for a particular host (e.g. `rdg-sre-sandbox.testa.dsgroupdev.co.uk` ). For production environments this should usually not be an issue. The signed certificates are also stored in the Key Vault for easy redeployment. However, if you find yourself needing to re-run this step without the Key Vault secret available, either to debug an error experienced in production or when redeploying a test environment frequently during development, you should run `./Update_SRE_RDS_SSL_Certificate.ps1 -dryRun $true` to use the Let's Encrypt staging server, which will issue certificates more frequently. However, these certificates will not be trusted by your browser, so you will need to override the security warning in your browser to access the RDS web client for testing.

</details>

### :bicyclist: Optional: Set up a non-privileged user account

These steps ensure that you have created a non-privileged user account that you can use for testing.
You must ensure that you have assigned a licence to this user in the Azure Active Directory so that MFA will work correctly.

You should have already set up a non-privileged user account upon setting up the SHM, when [validating the active directory synchronisation](./how-to-deploy-shm.md#validate-active-directory-synchronisation), but you may wish to set up another or verify that you have set one up already:

<details>
<summary><strong>Set up a non-privileged user account</strong></summary>

![Remote](https://img.shields.io/badge/remote-five%20minutes-blue?logo=microsoft-onedrive&style=for-the-badge)

+ Log into the **SHM primary domain controller** (`DC1-SHM-<SHM ID>`) VM using the connection details that you previously used to [log into this VM](how-to-deploy-shm.md#configure-the-first-domain-controller-via-remote-desktop)
+ Follow the [user creation instructions](./how-to-deploy-shm.md#validate-active-directory-synchronisation) from the [SHM deployment guide](./how-to-deploy-shm.md) (everything under the Validate Active Directory synchronisation header). In brief these involve:
  + adding your details (ie. your first name, last name, phone number etc.) to a user details CSV file.
  + running `C:\Installation\CreateUsers.ps1 <path_to_user_details_file>` in a Powershell command window with elevated privileges.

This will create a user in the local Active Directory on the SHM domain controller and start the process of synchronisation to the Azure Active Directory, which will take around 5 minutes.

#### Ensure that your non-privileged user account is in the correct Security Group

![Remote](https://img.shields.io/badge/remote-five%20minutes-blue?logo=microsoft-onedrive&style=for-the-badge)

+ Log into the **SHM primary domain controller** (`DC1-SHM-<SHM ID>`) VM using the connection details that you previously used to [log into this VM](how-to-deploy-shm.md#configure-the-first-domain-controller-via-remote-desktop)
+ In Server Manager click `Tools > Active Directory Users and Computers`
+ In `Active Directory Users and Computers`, expand the domain in the left hand panel click `Safe Haven Security Groups`
+ Right click the `SG <SRE ID> Research Users` security group and select `Properties`
+ Click on the `Members` tab.
+ If your user is not already listed here you must add them to the group
  + Click the `Add` button
  + Enter the start of your username and click `Check names`
  + Select your username and click `Ok`
  + Click `Ok` again to exit the `Add users` dialogue
+ Synchronise with Azure Active Directory by running following `Powershell` command on the SHM primary domain controller

```pwsh
C:\Installation\Deploy_RDS_Environment.ps1
```

#### Ensure that your user account has MFA enabled

Please ensure that your account is fully set-up (including MFA as [detailed in the user guide](../../how_to_guides/user_guides/user-guide.md#door-set-up-multi-factor-authentication)).
In order to verify this switch to your custom Azure Active Directory in the Azure portal and make the following checks:

<details>
<summary><strong>Verify non-privileged user account is set up</strong></summary>

![Azure Portal](https://img.shields.io/badge/portal-one%20minute-blue?logo=microsoft-azure&style=for-the-badge)

+ From the Azure portal, navigate to the AAD you have created.
+ The `Usage Location` must be set in Azure Active Directory (should be automatically synchronised from the local Active Directory if it was correctly set there)
  + Navigate to `Azure Active Directory > Manage / Users > (user account)`, and ensure that `Settings > Usage Location` is set.
+ A licence must be assigned to the user.
  + Navigate to `Azure Active Directory > Manage / Users > (user account) > Licenses` and verify that a license is assigned and the appropriate MFA service enabled.
+ MFA must be enabled for the user.
  + The user must log into `aka.ms/mfasetup` and set up MFA as [detailed in the user guide](../../how_to_guides/user_guides/user-guide.md#door-set-up-multi-factor-authentication).

</details>

### :microscope: Test the RDS using a non-privileged user account

+ Launch a local web browser on your **deployment machine**  and go to `https://<SRE ID>.<safe haven domain>` and log in with the user name and password you set up for the non-privileged user account.
  + for example for `<safe haven domain> = testa.dsgroupdev.co.uk` and `<SRE ID> = sandbox` this would be `https://sandbox.testa.dsgroupdev.co.uk/`
+ You should see a screen like the following. If you do not, follow the **troubleshooting** instructions below.

  <p align="center">
    <img src="../../images/deploy_sre/rds_desktop.png" width="80%" title="rds_desktop"/>
  </p>

#### :pencil: Notes
+ Ensure that you are connecting from one of the **permitted IP ranges** specified in the `inboundAccessFrom` section of the SRE config file. For example, if you have authorised a corporate VPN, check that you have correctly configured you client to connect to it.
+ Note that clicking on the apps will not work until the other servers have been deployed.

#### :warning: Troubleshooting
If you get a `404 resource not found` error when accessing the webclient URL, it is likely that the RDS webclient failed to install correctly.

+ Go back to the previous section and rerun the `C:\Installation\Deploy_RDS_Environment.ps1` script on the RDS gateway.
+ After doing this, follow the instructions to [configure RDS CAP and RAP settings](#accept-configure-rds-cap-and-rap-settings) and to [update the SSL certificate](#closed_lock_with_key-update-ssl-certificate).

If you get an `unexpected server authentication certificate error` , your browser has probably cached a previous certificate for this domain.

+ Do a [hard reload](https://www.getfilecloud.com/blog/2015/03/tech-tip-how-to-do-hard-refresh-in-browsers/) of the page (permanent fix)
+ OR open a new private / incognito browser window and visit the page.

If you can see an empty screen with `Work resources` but no app icons, your user has not been correctly added to the security group.

+ Ensure that the user you have logged in with is a member of the `SG <SRE ID> Research Users` group on the domain controller

## :snowflake: 6. Deploy web applications (GitLab and CodiMD)

![Powershell](https://img.shields.io/badge/local-thirty%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Setup_SRE_WebApp_Servers.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE

### :microscope: Test GitLab and CodiMD servers

+ Launch a local web browser on your **deployment machine**  and go to `https://<SRE ID>.<safe haven domain>` and log in with the user name and password you set up for the non-privileged user account.
  + for example for `<safe haven domain> = testa.dsgroupdev.co.uk` and `<SRE ID> = sandbox` this would be `https://sandbox.testa.dsgroupdev.co.uk/`
  + Test `GitLab` by clicking on the `GitLab` app icon.
  + You should receive an MFA request to your phone or authentication app.
  + Once you have approved the sign in, you should see a Chrome window with the GitLab login page.
  + Log in with the short-form `username` of a user in the `SG <SRE ID> Research Users` security group.
+ Test `CodiMD` by clicking on the `CodiMD` app icon.
  + You should receive an MFA request to your phone or authentication app.
  + Once you have approved the sign in, you should see a Chrome window with the GitLab login page.
  + Log in with the short-form `username` of a user in the `SG <SRE ID> Research Users` security group.
+ If you do not get an MFA prompt or you cannot connect to the `GitLab` and `CodiMD` servers, follow the **troubleshooting** instructions below.

#### :warning: Troubleshooting

If you can log in to the initial webclient authentication but do not get the MFA request, then the issue is likely that the configuration of the connection between the SHM NPS server and the RDS Gateway server is not correct.

+ Ensure that both the SHM NPS server and the RDS Gateway are running
+ Follow the instructions to [configure RDS CAP and RAP settings](#accept-configure-rds-cap-and-rap-settings) to reset the configuration of the RDS gateway and NPS VMs.
+ Ensure that the default UDP ports `1812` , `1813` , `1645` and `1646` are all open on the SHM NPS network security group ( `NSG_SHM_SUBNET_IDENTITY` ). [This documentation](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/dd316134(v=ws.10)) gives further details.

If this does not resolve the issue, trying checking the Windows event logs

  + Use `Event Viewer` on the SRE RDS Gateway (`Custom views > Server roles > Network Policy and Access Services`) to check whether the NPS server is contactable and whether it is discarding requests
  + Use `Event Viewer` on the SHM NPS server (`Custom views > Server roles > Network Policy and Access Services`) to check whether NPS requests are being received and whether the NPS server has an LDAP connection to the SHM DC.
    + Ensure that the requests are being received from the **private** IP address of the RDS Gateway and **not** its public one.
  + One common error on the NPS server is `A RADIUS message was received from the invalid RADIUS client IP address x.x.x.x` . [This help page](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/dd316135(v=ws.10)) might be useful.
    + This may indicate that the NPS server could not join the SHM domain. Try `ping DC1-SHM-<SHM ID>` from the NPS server and if this does not resolve, try rebooting it.
  + Ensure that the `Windows Firewall` is set to `Domain Network` on both the SHM NPS server and the SRE RDS Gateway

If you get a `We couldn't connect to the gateway because of an error` message, it's likely that the `Remote RADIUS Server` authentication timeouts have not been set correctly.

+ Follow the instructions to [configure RDS CAP and RAP settings](#accept-configure-rds-cap-and-rap-settings) to reset the authentication timeouts on the RDS gateway.
  + If you get multiple MFA requests with no change in the `Opening ports` message, it may be that the shared RADIUS secret does not match on the SHM server and SRE RDS Gateway.
+ Follow the instructions to [configure RDS CAP and RAP settings](#accept-configure-rds-cap-and-rap-settings) to reset the secret on both the RDS gateway and NPS VMs.
+ :warning: This can happen if the NPS secret stored in the Key Vault is too long. We found that a 20 character secret caused problems but the (default) 12 character secret works.


## :floppy_disk: 7. Deploy storage accounts

![Powershell](https://img.shields.io/badge/local-ten%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Setup_SRE_Storage_Accounts.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE

This script will create a storage account in the `RG_SHM_<shmId>_DATA_PERSISTENT` resource group, a corresponding private end point in `RG_SRE_NETWORKING` and will configure the DNS zone of the storage account to the right IP address.

## :baseball: 8. Deploy databases

![Powershell](https://img.shields.io/badge/local-depends%20on%20settings-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Setup_SRE_Databases.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE

This will deploy any databases that you specified in the core config file. The time taken will depend on which (if any) databases you chose.
+ The deployment of an `MS-SQL` database will take **around 60 minutes** to complete.
+ The deployment of a `PostgreSQL` database will take **around 10 minutes** to complete.

## :computer: 9. Deploy data science VMs

### :fast_forward: Optional: Customise the deployed VM

If this SRE needs additional software or settings that are not in your default VM image, you can create a custom cloud init file.
On your **deployment machine**.

+ By default, compute VM deployments will use the `cloud-init-compute-vm.template.yaml` configuration file in the `deployment/secure_research_environment/cloud_init/` folder. This does all the necessary steps to configure the VM to work with LDAP.
+ If you require additional steps to be taken at deploy time while the VM still has access to the internet (e.g. to install some additional project-specific software), copy the default cloud init file to a file named `cloud-init-compute-vm-sre-<SRE ID>.template.yaml` in the same folder and add any additional required steps in the `SRE-SPECIFIC COMMANDS` block marked with comments.

### :computer: Deploy a single data science VM (DSVM)

![Powershell](https://img.shields.io/badge/local-ten%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Add_DSVM.ps1 -shmId <SHM ID> -sreId <SRE ID> -ipLastOctet <IP last octet>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE
- where `<IP last octet>` is last octet of the IP address
- you can also provide a VM size by passing the optional `-vmSize` parameter.

This will deploy a new compute VM into the SRE environment

#### :pencil: Notes
+ The initial shared `DSVM Main` shared VM should be deployed with the last octet `160`
+ ![Turing Institute](https://img.shields.io/badge/Turing%20Institute-555?&logo=canonical&logoColor=white) our convention is that subsequent CPU-based VMs are deployed with the next unused last octet in the range `161` to `179` and GPU-based VMs are deployed with the next unused last octet between `180` and `199` .
+ If you want to deploy several DSVMs, simply repeat the above setps with a different IP address last octet

## :lock: 10. Apply network configuration

![Powershell](https://img.shields.io/badge/local-ten%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Apply_SRE_Network_Configuration.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE

## :fire_engine: 11. Configure firewall

<!-- NB. this could be moved earlier in the deployment process once this has been tested, but the first attempt will just focus on locking down an already-deployed environment -->

![Powershell](https://img.shields.io/badge/local-a%20few%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Setup_SRE_Firewall.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE

## :chart_with_upwards_trend: 12. Configure logging

![Powershell](https://img.shields.io/badge/local-a%20few%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/secure_research_environment/setup`

```pwsh
./Setup_SRE_Logging.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
- where `<SRE ID>` is the [secure research environment ID](#secure-research-environment-id) for this SRE

#### :warning: Troubleshooting

The API call that installs the logging extensions to the VMs will time out after a few minutes, so you may get some extension installation failure messages if installation of the loggin agent takes longer than this to complete.
When this happens, you will see a failure message reporting that installation of the extension was not successful for the VM(s) for which the API timed out.
You may also get this message for other failures in installation.

In any case, re-running `./Setup_SRE_Logging.ps1 -shmId $shmId -sreId $sreId` will attempt to install the extensions again, skipping any VMs that already have the extensions installed.
Where the issue was an API timeout, these VMs will report that the extension is already installed when the logging set up script is run again.

Where there was a genuine failure in the installation of a VM extension, the script will try again to install the extension when the logging set up script is run again.
If you get consistent failure messages after re-running the logging set up script a few times, then further investigation will be required.


## :fire: 13. Run smoke tests on DSVM

These tests should be run **after** the network lock down and peering the SRE and package mirror VNets.
They are automatically uploaded to the compute VM during the deployment step.

![Azure Portal](https://img.shields.io/badge/portal-one%20minute-blue?logo=microsoft-azure&style=for-the-badge)
+ Navigate to the **compute VM** that you have just deployed in the portal at `Resource Groups > RG_SHM_<SHM ID>_SRE_<SRE ID>_COMPUTE > SRE-<SRE ID>-<IP last octet>-<version number>` and note the `Private IP address` for this VM
+ Next, navigate to the `RG_SHM_<SHM ID>_SRE_<SRE ID>_SECRETS` resource group and then the `kv-<SHM ID>-sre-<SRE ID>` Key Vault and then select `secrets` on the left hand panel and retrieve the following:
+ `<admin username>` is in the `sre-<SRE ID>-vm-admin-username` secret.
+ `<admin password>` is in the `sre-<SRE ID>-vm-admin-password-compute` secret.


To run the smoke tests:

![Remote](https://img.shields.io/badge/remote-five%20minutes-blue?logo=microsoft-onedrive&style=for-the-badge)
+ Log into the **DSVM** (`SRE-<SRE ID>-<IP last octet>-<version number>`) VM that you just deployed using the credentials that you just retrieved from the portal.
+ Open a terminal session
+ Enter the test directory using `cd /opt/verification/smoke_tests`
+ Run `bats run_all_tests.bats` .
+ If all test results are expected you are done! Otherwise check the `README.md` in this folder for help diagnosing test failures.
