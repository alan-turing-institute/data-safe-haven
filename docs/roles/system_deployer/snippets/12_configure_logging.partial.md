![Powershell: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`

```powershell
PS> ./Setup_SRE_Logging.ps1 -shmId <SHM ID> -sreId <SRE ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM
- where `<SRE ID>` is the {ref}`secure research environment ID <roles_deployer_sre_id>` for this SRE

````{error}
Installing the logging agent can take several minutes, so the API call that installs the logging extensions to the VMs might time out before installation is complete.
Then this happens, you will see a failure message reporting that installation of the extension was not successful for the VM(s) for which the API timed out.
You may also get this message for other failures in installation.

If you see these errors, re-run:

```powershell
PS> ./Setup_SRE_Logging.ps1 -shmId $shmId -sreId $sreId
```

this will attempt to install the extensions again, skipping any VMs that already have the extensions installed.

Where the issue was an API timeout, these VMs will report that the extension is already installed when the logging set up script is run again.
Where there was a genuine failure in the installation of a VM extension, the script will try again to install the extension when the logging set up script is run again.
If you get consistent failure messages after re-running the logging set up script a few times, then further investigation will be required.
````
