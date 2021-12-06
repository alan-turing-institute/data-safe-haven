## Explanation of symbols used in this guide

````{admonition} Powershell command
![Powershell: estimate of time needed](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=estimate%20of%20time%20needed)

- This indicates a `Powershell` command which you will need to run locally on your machine
- Ensure you have checked out (or downloaded) the appropriate tag of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a `Powershell` terminal and navigate to the indicated directory of your locally checked-out version of the Safe Haven repository
- Ensure that you are logged into Azure by running the `Connect-AzAccount` command
  ```{tip}
  If your account is a guest in additional Azure tenants, you may need to add the `-Tenant <Tenant ID>` flag, where `<Tenant ID>` is the ID of the Azure tenant you want to deploy into.
  ```
- This command will give you a URL and a short alphanumeric code.
- Go to URL in a web browser, enter the code and log in to your account on Azure.
  ```{tip}
  If you have several Azure accounts, make sure you use one that has permissions to make changes to the subscription you are using
  ```
````

````{admonition} Remote command
![Remote: estimate of time needed](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=estimate%20of%20time%20needed)

- This indicates a command which you will need to run remotely on an Azure virtual machine (VM) using `Microsoft Remote Desktop`
- Open `Microsoft Remote Desktop` and click `Add Desktop` / `Add PC`
- Enter the private IP address of the VM that you need to connect to in the `PC name` field (this can be found by looking in the Azure portal)
- Enter the name of the VM (for example `DC1-SHM-PROJECT`) in the `Friendly name` field
- Click `Add`
- Ensure you are connected to the SHM VPN that you have set up
- Double click on the desktop that appears under `Saved Desktops` or `PCs`.
- Use the `username` and `password` specified by the appropriate section of the guide

```{tip}
If you see a warning dialog that the certificate cannot be verified as root, accept this and continue.
```
````

```{admonition} Azure Portal operation
![Portal: estimate of time needed](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-azure&label=portal&color=blue&message=estimate%20of%20time%20needed)

- This indicates an operation which needs to be carried out in the [`Azure Portal`](https://portal.azure.com) using a web browser on your local machine.
- You will need to login to the portal using an account with privileges to make the necessary changes to the resources you are altering
```

```{admonition} Azure Active Directory operation
![Azure AD: estimate of time needed](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=estimate%20of%20time%20needed)

- This indicates an operation which needs to be carried out in the [`Azure Portal`](https://portal.azure.com) using a web browser on your local machine.
- You will need to login to the portal using an account with administrative privileges on the `Azure Active Directory` that you are altering.
- Note that this might be different from the account which is able to create/alter resources in the Azure subscription where you are building the Safe Haven.
```

```{admonition} OS-dependent steps
The following icons indicate steps that depend on the OS you are using to deploy the SHM

- ![macOS](https://img.shields.io/badge/-555?&logo=apple&logoColor=white) **MacOS**
- ![Windows](https://img.shields.io/badge/-555?&logo=windows&logoColor=white) **Windows**
- ![Linux](https://img.shields.io/badge/-555?&logo=linux&logoColor=white) **Linux**
```
