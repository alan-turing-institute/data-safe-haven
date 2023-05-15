(administrator_manage_costs)=

# Managing costs

```{important}
This document assumes that you already have access to a {ref}`Safe Haven Management (SHM) environment <deploy_shm>` and one or more {ref}`Secure Research Environments (SREs) <deploy_sre>` that are linked to it.
```

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

If you need to reboot an SHM or SRE that is not running, you can use the same scripts you used to shut them down, but changing the `-Action` flag to `EnsureStopped`, see below.

On your **deployment machine**.

- Ensure you have the same version of the Data Safe Haven repository as was used by your deployment team
- Open a `Powershell` terminal and navigate to the `deployment/administration` directory within the Data Safe Haven repository
- Run `./SHM_Manage_VMs.ps1 -shmId <shm id> -Action EnsureStarted -Group All` to restart the SHM
- For each SRE, run `./SRE_Manage_VMs.ps1 -shmId <shm id> -sreId <sre id> -Action EnsureStarted`

```{warning}
If the Azure subscription that you have deployed into runs out of credit, the SHM and/or SRE will be shutdown automatically.
```

## {{anger}} Tear down SHM package mirrors

During normal usage of the SHM, you should not need to tear down the package mirrors.
However, if you no longer have any SREs at a particular tier and you want to save on the costs of running the mirrors, you might decide to do so.

On your **deployment machine**.

- Ensure you have the same version of the Data Safe Haven repository as was used by your deployment team.
- Open a `Powershell` terminal and navigate to the `deployment/administration` directory within the Data Safe Haven repository.
- Ensure you are logged into `Azure` within `Powershell` using the command: `Connect-AzAccount`. This command will give you a URL and a short alphanumeric code. You will need to visit that URL in a web browser and enter the code
  - NB. If your account is a guest in additional Azure tenants, you may need to add the `-Tenant <Tenant ID>` flag, where `<Tenant ID>` is the ID of the Azure tenant you want to deploy into.
- Tear down the package mirrors by running `./SHM_Package_Repository_Teardown.ps1 -shmId <SHM ID> -tier <desired tier>`, where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` specified in the configuration file.
- This will take **a few minutes** to run.