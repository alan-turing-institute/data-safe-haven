![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Add_DSVM.ps1 -shmId <SHM ID> -sreId <SRE ID> -ipLastOctet <IP last octet> [-vmSize <VM size>]
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE
- where `<IP last octet>` is last octet of the IP address
- [optional] where `<VM size>` is the [Azure VM size](https://docs.microsoft.com/en-us/azure/virtual-machines/sizes) for this compute VM

This will deploy a new compute VM into the SRE environment.

```{tip}
If this SRE needs additional software or settings that are not in your default VM image, you can create a custom cloud init file on your **deployment machine**.

- By default, compute VM deployments will use the `cloud-init-compute-vm.template.yaml` configuration file in the `deployment/secure_research_environment/cloud_init/` folder. This does all the necessary steps to configure the VM to work with LDAP.
- If you require additional steps to be taken at deploy time while the VM still has access to the internet (e.g. to install some additional project-specific software), copy the default cloud init file to a file named `cloud-init-compute-vm-shm-<SHM ID>-sre-<SRE ID>.template.yaml` in the same folder and add any additional required steps in the `SRE-SPECIFIC COMMANDS` block marked with comments.
```

```{admonition} Alan Turing Institute default
- CPU-based VMs are deployed with the next unused last octet in the range `160` to `179`
- GPU-based VMs are deployed with the next unused last octet in the range `180` and `199`
```
