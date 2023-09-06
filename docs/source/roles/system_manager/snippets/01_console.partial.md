Console access to the SRE VMs, including those for each web app and the `compute` VM, can be achieved through the `Azure` portal. All VMs share the same `<admin username>`, but each has its own `<admin password>`, which will need to be retrieved from the `SRE` key vault before accessing the console.

- From the `Azure` portal, navigate to the Resource Group `RG_SHM_<SHM ID>_SRE_<SRE ID>_SECRETS`
- Click on the `SRE` keyvault `kv-<SHM ID>_SRE_<SRE ID>`
- From the menu on the left, select `Secrets` from the `Objects` section.
- All VMs share the same `<admin username>`, found in the `sre-<SRE ID>-vm-admin-username` secret.
- Each VM has its own `<admin password>`, found in the `sre-<SRE ID>-vm-admin-password-<VM>` secret.

Once you have the `<admin username>` and `<admin password>`, you will be able to log in to the VM console as follows:

- From the `Azure` portal, navigate to the correct resource group:
    - `RG_SHM_<SHM ID>_SRE_<SRE ID>_WEBAPPS` for the web applications
    - `RG_SHM_<SHM ID>_SRE_<SRE ID>_COMPUTE` for the compute VM
- Click on the relevant VM
- From the menu on the left, scroll down to the `Help` section and select `Serial console`
- After a short time, you will be shown the console for the VM. You may need to press a key to be shown the login prompt.
- Log in with the details you retrieved earlier to be given root access to the VM.
