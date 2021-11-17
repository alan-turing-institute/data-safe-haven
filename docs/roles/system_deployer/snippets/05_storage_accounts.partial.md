![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Setup_SRE_Storage_Accounts.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>`for this SRE

This script will create a storage account in the `RG_SHM_<shmId>_DATA_PERSISTENT` resource group, a corresponding private end point in `RG_SRE_NETWORKING` and will configure the DNS zone of the storage account to the right IP address.
