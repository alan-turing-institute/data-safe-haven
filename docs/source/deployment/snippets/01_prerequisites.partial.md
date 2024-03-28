- An `SHM environment` that has already been deployed in Azure
    - Follow the {ref}`Safe Haven Management (SHM) deployment guide <deploy_shm>` if you have not done so already.
- All {ref}`prerequisites needed for deploying the SHM <deploy_shm_prerequisites>`.
- An [Azure subscription](https://portal.azure.com) with sufficient credits to build the environment in: we recommend around $1,000 as a reasonable starting point.
    - This can be the same or different from the one where the SHM is deployed

    ```{tip}
    - Ensure that the **Owner** of the subscription is an `Azure Security group` that contains all administrators and no-one else.
    - We recommend using separate `Microsoft Entra IDs` for users and administrators
    ```

- Access to a **global administrator** account on the SHM Microsoft Entra ID

### {{beginner}} Software

- `PowerShell` with support for Azure
    - We recommend [installing](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell) the [latest stable release](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.4) of Powershell. We have most recently tested deployment using version `7.4.1`.
    - Install the [Azure PowerShell Module](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps) using `Install-Module -Name Az -RequiredVersion 5.0.0 -Repository PSGallery`
- `Microsoft Remote Desktop`
    - On macOS this can be installed from the [Apple store](https://www.apple.com/app-store/)
- `OpenSSL`
    - Install using your package manager of choice

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

### {{key}} VPN connection to the SHM VNet

For some operations, you will need to log on to some of the VMs that you deploy and make manual changes.
This is done using the VPN which should have been deployed {ref}`when setting up the SHM environment <deploy_shm_vpn>`.

### {{name_badge}} SRE domain name

You will need access to a public routable domain name for the SRE and its name servers.
This can be a subdomain of the Safe Haven Management domain, e.g, `sandbox.project.turingsafehaven.ac.uk`, or a top-level domain (eg. `mydatasafehaven.co.uk` ).

### {{arrow_double_up}} Deploying multiple SREs in parallel

```{important}
You can only deploy to **one SRE at a time** from a given computer as the `Az` Powershell module can only work within one Azure subscription at a time.
```

If you need to deploy multiple SREs in parallel you will need to use multiple computers.
These can be different physical computers or you can provision dedicated deployment VMs - this is beyond the scope of this guide.
