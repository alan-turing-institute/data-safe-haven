(administrator_manage_users)=

# Managing web applications

```{important}
This document assumes that you already have access to a {ref}`Safe Haven Management (SHM) environment <deploy_shm>` and one or more {ref}`Secure Research Environments (SREs) <deploy_sre>` that are linked to it.
```

During deployment of an SRE, distinct virtual machines are created to host each of the three standard web applications - CoCalc, CodiMD, and Gitlab.

In principle, these should require no further direct interaction. Researchers using Secure Research Desktops will be able to interact with the servers through a web interface. CoCalc allows to create their own user accounts, while CodiMD and Gitlab authenticate with the Azure Active Directory via LDAP.

However, should it is possible for the virtual machine hosting the web app servers to successfully start without the web app servers themselves actually running. For example, Researchers using an SRD may find that the web apps are unavailable, or do not successfully authenticate log-in attempts. In such cases, command line access to the virtual machines hosting the web app servers may help to diagnose and resolve problems.

In the rest of this document, `<SHM ID>` is the management environment ID for the SHM, and `<SRE ID>` is the research environment ID for the SRE. 

### Checking build logs

An initial step could be to check the build logs of the virtual machine to ascertain whether any clear errors occurred during the process (e.g. the installation of the server software may have failed.).

- From the `Azure` portal, navigate to the web app resource group `RG_SHM_<SHM ID>_SRE_<SRE ID>_WEBAPPS`.
- Click on the relevant VM (e.g. `COCALC-SRE-<SRE ID>`)
- From the menu on the left, scroll down to the `Help` section and select `Boot diagnostics`
- Click `Serial log` to access a full text log of the booting up of the VM.

From the log, you may be able to determine whether and why part of the build process failed. In some cases it may be sufficient to delete and rebuild the VM.

- From the menu on the left, click `Overview`
- Click `Delete`
- Redeploy the web app servers using `Powershell` locally

![Powershell: five minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=five%20minutes) at {{file_folder}} `./deployment/secure_research_environment/setup`
```powershell
PS> ./Setup_SRE_WebApp_Servers.ps1
```

If the reason for failure is less clear, accessing the command line interface directly may help.

### Accessing the console

- Retrieve the login details for the web app virtual machines from the SRE key vault. From the `Azure` portal, navigate to the Resource Group `RG_SHM_<SHM ID>_SRE_<SRE ID>_SECRETS`
- Click on the keyvault `kv-<SHM ID>_SRE_<SRE ID>`
- From the menu on the left, select `Secrets`
- All web app virtual machines share the same admin username, found at `sre-<SRE ID>-vm-admin-username`
- Each web app has its own admin password, found at `sre-<SRE ID>-vm-admin-password-<WEB APP>`
- From the `Azure` portal, navigate to the web app resource group `RG_SHM_<SHM ID>_SRE_<SRE ID>_WEBAPPS`.
- Click on the relevant VM (e.g. `COCALC-SRE-<SRE ID>`)
- From the menu on the left, scroll down to the `Help` section and select `Serial console`
- After a short time, you will be shown the console for the VM. You may need to press a key to be shown the login prompt.
- Log in with the details you retrieved earlier to be given root access to the VM.