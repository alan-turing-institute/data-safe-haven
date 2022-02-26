![Powershell: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Setup_SRE_Key_Vault_And_Users.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE

This step will register service accounts with the SHM and also create a Key Vault in the SRE subscription (at `Resource Groups > RG_SHM_<SHM ID>_SRE_<SRE ID>_SECRETS > kv-<SHM ID>-sre-<SRE ID>`).
