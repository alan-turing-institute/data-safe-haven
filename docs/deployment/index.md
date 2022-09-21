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

[Safe Haven Management (SHM) deployment guide](deploy_shm.md)
: deploy a single Safe Haven Management (SHM) segment. This will deploy infrastructure shared between projects such as user management and package mirrors/proxies.

[Secure Research Desktop (SRD) build instructions](build_srd_image.md)
: build and publish our "batteries included" Secure Research Desktop (SRD) virtual machine image. Instructions about how to customise this are also available here.

[Secure Research Environment (SRE) deployment guide](deploy_sre.md)
: deploy one Secure Research Environment (SRE) for each project you want to have its own independent, isolated analysis environment.

[Security checklist](security_checklist.md)
: an example security checklist used at the Alan Turing Institute to help evaluate the security of our deployments.
