(administrator_manage_deployments)=

# Managing Data Safe Haven deployments

```{important}
This document assumes that you already have access to a {ref}`Safe Haven Management (SHM) environment <deploy_shm>` and one or more {ref}`Secure Research Environments (SREs) <deploy_sre>` that are linked to it.
```

(resize_vm)=

## {{arrow_upper_right}} Resize the Virtual Machine (VM) of a Secure Research Desktop (SRD)

Sometimes during a project that uses a deployed SRE, researchers may find the available compute inadequate for their purposes and wish to increase the size of the SRD's VM. The **simplest way to resize a VM is via the Azure Portal**, but it can also be done via script.

To resize via the Azure Portal:

- Log into the Azure portal and locate the VM inside the Resource Group called `RG_SHM_<shm id>_SRE_<sre id>_COMPUTE`
- [Follow these instructions](https://learn.microsoft.com/en-us/azure/virtual-machines/resize-vm?tabs=portal) in the Azure portal

<details>
<summary>
To resize via script:
</summary>

- Log into the Azure portal and locate the VM inside the Resource Group called `RG_SHM_<shm id>_SRE_<sre id>_COMPUTE`
- Make a note of the last octet of the IP address

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Add_Single_SRD.ps1 -shmId <SHM ID> -sreId <SRE ID> -ipLastOctet <IP last octet> [-vmSize <VM size>] -Upgrade -Force
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE
- where `<IP last octet>` is last octet of the IP address (check what this is in the Azure Portal)
- where `<VM size>` is the new [Azure VM size](https://docs.microsoft.com/en-us/azure/virtual-machines/sizes)
- where `<Upgrade>` is required to ensure the old VM is replaced
- where `<Force>` ensures that `<Upgrade>` works even when the VM is built with the same image

</details>

```{tip}
If the new `VM size` you want isn't shown as available in the Azure Portal, there are several steps that can be taken.

Firstly, try **stopping the VM** and checking again whether the size you want is available, as this can reveal additional options that aren't shown whilst the VM is running. For example, when resizing to an N-series VM in Azure, (see {ref}`using_gpus`) we've found that NVIDIA options such as the  NVv3-series are not always shown as available.

Next, you can try to **request an increase** in the vCPU quota for the VM family of the desired VM:
- Navigate to the Azure Portal and on the subscription page, click `Usage + quotas` under `Settings`
- Choose the family appropriate to the VM that you want to resize to, and select a region appropriate for the SRE
- Click the pen icon and set the `New Limit` to at least the number of vCPUs required by the VM that you want, the click submit
- After the request is accepted, resize the VM as above
- In some cases, the quota increase may require a request to be submitted to Microsoft
```

(add_new_srd)=

## {{heavy_plus_sign}} Add a new SRD

The `-VmSizes` parameter provided when deploying the SRE (with the `Deploy_SRE.ps1` script) determines how many SRDs are created and how large each one will be.

To deploy a new SRD into the SRE environment, follow the below instructions:

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Add_Single_SRD.ps1 -shmId <SHM ID> -sreId <SRE ID> -ipLastOctet <IP last octet> [-vmSize <VM size>]
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE
- where `<IP last octet>` is last octet of the IP address (this must be different to any other SRD VMs)

(using_gpus)=

## {{minidisc}} Using GPUs in SRDs

When you {ref}`resize_vm` or {ref}`add_new_srd` featuring a GPU (N-series in Azure), you'll need to ensure it has an Nvidia GPU (as opposed to AMD or other).
See the [Azure docs](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes-gpu) for more information.
This is because only Nvidia GPUs support the drivers and CUDA libraries installed on the SRD image.

To test that a GPU enabled VM is working as expected, log into the SRE and type `nvidia-smi` into the terminal.

## {{crown}} Performing operations that require superuser privileges

If you need to perform any operations in the SRE that require root access, you will need to log into the `compute` VM via the Serial Console in the Azure Portal.

```{include} snippets/01_console.partial.md
:relative-images:
```

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
