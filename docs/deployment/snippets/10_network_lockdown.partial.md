![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Apply_SRE_Network_Configuration.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE

This will apply the locked-down network settings which will restrict access into/out of this SRE.

```{error}
If you encounter the following error, log in to the Azure portal and start the named VM before re-running Apply_SRE_Network_Configuration.ps1:
[FAILURE]: [x] Running '/path/to/data-safe-haven/deployment/secure_research_environment/setup/../remote/network_configuration/scripts/update_mirror_settings.sh' on remote VM 'SRE-<SRE ID>-0-SRD-<DATE>' failed.
```
