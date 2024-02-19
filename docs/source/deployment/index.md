# Deployment

```{toctree}
:hidden:

deploy_shm.md
build_srd_image.md
deploy_sre.md
security_checklist.md
```

Deploying an instance of the Data Safe Haven involves the following steps:

- Deploying the Safe Haven management component
- Building a secure research desktop virtual machine image to be used by all projects
- Deploying a Secure Research Environment for each project

Deployment might be carried out by members of an institutional IT team or external contractors.
In either case, the deploying team should ensure that the system is working as expected before handing it over to the {ref}`System Managers <role_system_manager>`.
We suggest developing a security checklist for deployers to work through - an example of one used at the Alan Turing Institute is shown below.

For instructions on removing deployed resources, refer to the guide for {ref}`System Managers <administrator_manage_deployments>`.

[Safe Haven Management (SHM) deployment guide](deploy_shm.md)
: deploy a single Safe Haven Management (SHM) segment. This will deploy infrastructure shared between projects such as user management and package mirrors/proxies.

[Secure Research Desktop (SRD) build instructions](build_srd_image.md)
: build and publish our "batteries included" Secure Research Desktop (SRD) virtual machine image. Instructions about how to customise this are also available here.

[Secure Research Environment (SRE) deployment guide](deploy_sre.md)
: deploy one Secure Research Environment (SRE) for each project you want to have its own independent, isolated analysis environment.

[Security checklist](security_checklist.md)
: an example security checklist used at the Alan Turing Institute to help evaluate the security of our deployments.

````{warning}
Microsoft have renamed Azure Active Directory to [Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/fundamentals/new-name).
We have updated these guides in the light of this change.
However, as of February 2024, Microsoft have not completed the renaming process.
Some software and documentation retains the old Azure Active Directory name.
Our documentation reflects the name that is currently in use, rather than the name that will be used once the renaming process is complete.
Where we use the name "Azure Active Directory", if the corresponding software, menu option, or documentation cannot be found, look instead for a version using the Microsoft Entra ID name.
````
