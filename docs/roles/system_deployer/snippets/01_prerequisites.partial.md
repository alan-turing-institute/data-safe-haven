## 1. {{seedling}} Prerequisites

- An `SHM environment` that has already been deployed in Azure
  - Follow the {ref}`Safe Haven Management (SHM) deployment guide <deploy_shm>` if you have not done so already.
- All {ref}`prerequisites needed for deploying the SHM <deploy_shm_prerequisites>`.
- An [Azure subscription](https://portal.azure.com) with sufficient credits to build the environment in: we recommend around $1,000 as a reasonable starting point.
  - This can be the same or different from the one where the SHM is deployed
  ```{tip}
  - Ensure that the **Owner** of the subscription is an `Azure Security group` that contains all administrators and no-one else.
  - We recommend using separate `Azure Active Directories` for users and administrators
  ```
- Access to a **global administrator** account on the SHM Azure Active Directory

### {{beginner}} Software

- `PowerShell` with support for Azure
  - Install [PowerShell v7.0 or above](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell)
  - Install the [Azure PowerShell Module](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps) using `Install-Module -Name Az -RequiredVersion 5.0.0 -Repository PSGallery`
- `Microsoft Remote Desktop`
  - On macOS this can be installed from the [Apple store](https://apps.apple.com)
- `OpenSSL`
  - Install using your package manager of choice

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
