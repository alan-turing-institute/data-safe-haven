![Powershell: thirty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=thirty%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Setup_SRE_Monitoring.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE

````{error}
As installing the logging agent can take several minutes, it is possible that some of the commands run in this script might time out.
The script should automatically retry any that fail, if you see any failure messages, please re-run:

```powershell
PS> ./Setup_SRE_Monitoring.ps1 -shmId $shmId -sreId $sreId
```

this will attempt to install the extensions again, skipping any VMs that already have the extensions installed.
````
