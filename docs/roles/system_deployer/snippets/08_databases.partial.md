![Powershell: up to seventy minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=up%20to%20seventy%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Setup_SRE_Databases.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>`for this SRE

This will deploy any databases that you specified in the core config file. The time taken will depend on which (if any) databases you chose.

```{important}
- The deployment of an `MS-SQL` database will take **around 60 minutes** to complete.
- The deployment of a `PostgreSQL` database will take **around 10 minutes** to complete.
```
