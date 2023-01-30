(administrator_manage_deployments)=

# Managing Data Safe Haven deployments

```{important}
This document assumes that you already have access to a {ref}`Safe Haven Management (SHM) environment <deploy_shm>` and one or more {ref}`Secure Research Environments (SREs) <deploy_sre>` that are linked to it.
```

(add_resize_vm)=

## {{heavy_plus_sign}} Add a new Secure Research Desktop (SRD) or resize an existing SRD’s VM

The `-VmSizes` parameter provided when deploying the SRE (with the `Deploy_SRE.ps1` script) determines how many SRDs are created and how large each one will be.

- To **add** another SRD after deployment, follow the below instructions for deploying an SRD with `Add_Single_SRD.ps1`
- The simplest way to **resize** a VM for an existing SRD is to log into the Azure portal and locate the VM inside the Resource Group called `RG_SHM_<shm id>_SRE_<sre id>_COMPUTE`, then resize it by [following these instructions](https://learn.microsoft.com/en-us/azure/virtual-machines/resize-vm?tabs=portal)
- Alternatively, you can **resize** a VM by using the below instructions for deploying an SRD, taking care to set the `<IP last octet>` to that of the existing VM (viewable in Azure), and by setting the `-Upgrade` and `-Force` flags

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

**Deploy an SRD:**

```powershell
PS> ./Add_Single_SRD.ps1 -shmId <SHM ID> -sreId <SRE ID> -ipLastOctet <IP last octet> [-vmSize <VM size>]
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE
- where `<IP last octet>` is last octet of the IP address (if resizing an existing VM, check what this is in Azure)
- [optional] where `<VM size>` is the [Azure VM size](https://docs.microsoft.com/en-us/azure/virtual-machines/sizes) for this SRD
- [optional] where resizing a VM for an existing SRD, also add `-Upgrade` and `-Force`

This will deploy a new SRD into the SRE environment.

## {{fire}} Remove a single SRE

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

## {{end}} Remove a complete Safe Haven

### {{collision}} Tear down any attached SREs

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

### {{unlock}} Disconnect from the Azure Active Directory

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

### {{bomb}} Tear down the SHM

On your **deployment machine**.

- Ensure you have the same version of the Data Safe Haven repository as was used by your deployment team
- Open a `Powershell` terminal and navigate to the `deployment/administration` directory within the Data Safe Haven repository
- Ensure you are logged into `Azure` within `Powershell` using the command: `Connect-AzAccount`. This command will give you a URL and a short alphanumeric code. You will need to visit that URL in a web browser and enter the code

    ```{attention}
    If your account is a guest in additional Azure tenants, you may need to add the `-Tenant <Tenant ID>` flag, where `<Tenant ID>` is the ID of the Azure tenant you want to deploy into.
    ```

- Tear down the SHM by running:

    ```powershell
    ./SHM_Teardown.ps1 -shmId <SHM ID>
    ```

  where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` specified in the configuration file.
