(role_system_deployer)=
# System Deployer

```{toctree}
:hidden:

deploy_shm.md
build_compute_vm_image.md
deploy_sre.md
security_checklist.md
```

Members of technical staff responsible for deploying the Safe Haven.
Typically these might be members of an institutional IT team or external contractors.

[Safe Haven Management (SHM) deployment guide](deploy_shm.md)
: deploy a single Safe Haven Management (SHM) segment. This will deploy the user management and software package mirrors.

[Data Science virtual machine build instructions](build_compute_vm_image.md)
: build and publish our "batteries included" Data Science Compute virtual machine image. Customise if necessary.

[Secure Research Environment (SRE) deployment guide](deploy_sre.md)
: deploy one Secure Research Environment (SRE) for each project you want to have its own independent, isolated analysis environment.

[Security checklist](security_checklist.md)
: use this checklist to validate that your deployment meets the requirements listed in {ref}`policy_technical_controls`.
