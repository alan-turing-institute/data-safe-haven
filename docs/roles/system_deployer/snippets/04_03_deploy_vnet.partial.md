![Powershell: five minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=five%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./deployment/secure_research_environment/setup/Setup_SRE_Networking.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>`for this SRE

```{note}
The VNet peerings may take a few minutes to provision after the script completes.
```
