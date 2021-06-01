# Migrating an SHM

This document assumes that you have already deployed a [Safe Haven Management (SHM) environment](../../tutorial/deployment_tutorials/how-to-deploy-shm.md) and one or more [Secure Research Environments (SRE)](../../tutorial/deployment_tutorials/how-to-deploy-sre.md) that are linked to it.

It will help you update the SHM to a newer release by deploying a new SHM and migrating the users to it.


## :mailbox_with_mail: Table of contents

+ [:seedling: 1. Prerequisites](#seedling-1-prerequisites)
+ [:clipboard: 2. Safe Haven Management configuration](#clipboard-2-safe-haven-management-configuration)
+ [:door: 3. Configure DNS for the custom domain](#door-3-configure-dns-for-the-custom-domain)
+ [:file_folder: 4. Ensure the Azure Active Directory domain is registered](#file_folder-4-ensure-the-azure-active-directory-domain-is-registered)
+ [:key: 5. Deploy Key Vault for SHM secrets and create emergency admin account](#key-5-deploy-key-vault-for-shm-secrets-and-create-emergency-admin-account)
<!-- + [:iphone: 6. Enable MFA and self-service password reset](#iphone-6-enable-mfa-and-self-service-password-reset)
+ [:id: 7. Configure internal administrator accounts](#id-7-configure-internal-administrator-accounts) -->
+ [:station: 8. Deploy network and VPN gateway](#station-8-deploy-network-and-vpn-gateway)
+ [:house_with_garden: 9. Deploy and configure domain controllers](#house_with_garden-9-deploy-and-configure-domain-controllers)
+ [:police_car: 10. Deploy and configure network policy server](#police_car-10-deploy-and-configure-network-policy-server)
+ [:closed_lock_with_key: 11. Require MFA for all users](#closed_lock_with_key-11-require-mfa-for-all-users)
+ [:fire_engine: 12. Deploy firewall](#fire_engine-12-deploy-firewall)
+ [:package: 13. Deploy Python/R package repositories](#package-13-deploy-PythonR-package-repositories)
+ [:chart_with_upwards_trend: 14. Deploy logging](#chart_with_upwards_trend-14-deploy-logging)


## Explanation of symbols used in this guide

![Powershell: estimate of time needed](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=estimate%20of%20time%20needed)

+ This indicates a `Powershell` command which you will need to run locally on your machine
+ Ensure you have checked out the appropriate version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
+ Open a `Powershell` terminal and navigate to the indicated directory of your locally checked-out version of the Safe Haven repository
+ Ensure that you are logged into Azure by running the `Connect-AzAccount` command
  + :pencil: If your account is a guest in additional Azure tenants, you may need to add the `-Tenant <Tenant ID>` flag, where `<Tenant ID>` is the ID of the Azure tenant you want to deploy into.
+ This command will give you a URL and a short alphanumeric code.
  + You will need to visit that URL in a web browser, enter the code and log in to your account on Azure
  + :pencil: If you have several Azure accounts, make sure you use one that has permissions to make changes to the subscription you are using

![Remote: estimate of time needed](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=estimate%20of%20time%20needed)

+ This indicates a command which you will need to run remotely on an Azure virtual machine (VM) using `Microsoft Remote Desktop`
+ Open `Microsoft Remote Desktop` and click `Add Desktop` / `Add PC`
+ Enter the private IP address of the VM that you need to connect to in the `PC name` field (this can be found by looking in the Azure portal)
+ Enter the name of the VM (for example `DC1-SHM-TESTA`) in the `Friendly name` field
+ Click `Add`
+ Ensure you are connected to the SHM VPN that you have set up
+ Double click on the desktop that appears under `Saved Desktops` or `PCs`.
+ Use the `username` and `password` specified by the appropriate section of the guide
+ :pencil: If you see a warning dialog that the certificate cannot be verified as root, accept this and continue.

![Portal: estimate of time needed](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-azure&label=portal&color=blue&message=estimate%20of%20time%20needed)

+ This indicates an operation which needs to be carried out in the [`Azure Portal`](https://portal.azure.com) using a web browser on your local machine.
+ You will need to login to the portal using an account with privileges to make the necessary changes to the resources you are altering

![Azure AD: estimate of time needed](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=estimate%20of%20time%20needed)

+ This indicates an operation which needs to be carried out in the [`Azure Portal`](https://portal.azure.com) using a web browser on your local machine.
+ You will need to login to the portal using an account with administrative privileges on the `Azure Active Directory` that you are altering.
+ Note that this might be different from the account which is able to create/alter resources in the Azure subscription where you are building the Safe Haven.

:pencil: **Notes**

+ This indicates some explanatory notes or examples that provide additional context for the current step.

:warning: **Troubleshooting**

+ This indicates a set of troubleshooting instructions to help diagnose and fix common problems with the current step.

![macOS](https://img.shields.io/badge/-555?&logo=apple&logoColor=white)![Windows](https://img.shields.io/badge/-555?&logo=windows&logoColor=white)![Linux](https://img.shields.io/badge/-555?&logo=linux&logoColor=white)

+ These indicate steps that depend on the OS that you are using to deploy the SHM

## :seedling: 1. Prerequisites

+ All of the [Safe Haven Management (SHM) environment](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#seedling-1-prerequisites) prerequisites

## :clipboard: 2. Safe Haven Management configuration

+ Create a copy of the configuration file for your previous SHM
+ You may want to change some of the following attributes:

```json
{
    "azure": {
        "subscriptionName": "Azure subscription to deploy the SHM into. You might want to use a different subscription than for your previous SHM.",
    },
    "shmId": "The <SHM ID> for the new SHM. If you try to deploy two SHMs with the same ID into the same subscription some resources will not deploy correctly.",
}
```

## :door: 3. Configure DNS for the custom domain

![Powershell: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

```pwsh
PS> ./Setup_SHM_DNS_Zone.ps1 -shmId <SHM ID>
```
+ where `<SHM ID>` is the [management environment ID](#management-environment-id) for this SHM

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#door-3-configure-dns-for-the-custom-domain) documentation for more details

## :file_folder: 4. Ensure the Azure Active Directory domain is registered

![Powershell: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

```pwsh
PS> pwsh { ./Setup_SHM_AAD_Domain.ps1 -shmId <SHM ID> -tenantId <AAD tenant ID> }
```

+ where `<SHM ID>` is the [management environment ID](#management-environment-id) for this SHM
+ where `<AAD tenant ID>` is the `Tenant ID` for the AAD

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#file_folder-4-setup-azure-active-directory-aad) documentation for more details

#### :pencil: Notes
+ You will need to use an AAD global admin when the `AzureAD` module asks you to sign-in.

## :key: 5. Deploy Key Vault for SHM secrets and create emergency admin account

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

```pwsh
PS> pwsh { ./Setup_SHM_Key_Vault_And_Emergency_Admin.ps1 -shmId <SHM ID> -tenantId <AAD tenant ID> }
```

+ where `<SHM ID>` is the [management environment ID](#management-environment-id) for this SHM
+ where `<AAD tenant ID>` is the `Tenant ID` for the AAD

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#key-5-deploy-key-vault-for-shm-secrets-and-create-emergency-admin-account) documentation for more details

#### :pencil: Notes
+ You will need to use an AAD global admin when the `AzureAD` module asks you to sign-in.

## :station: 8. Deploy network and VPN gateway

![Powershell: twenty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=twenty%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

```pwsh
PS> ./Setup_SHM_Networking.ps1 -shmId <SHM ID>
```

+ where `<SHM ID>` is the [management environment ID](#management-environment-id) for this SHM

Follow the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#station-8-deploy-network-and-vpn-gateway) documentation for instructions on VPN gateway setup

## :house_with_garden: 9. Deploy and configure domain controllers

![Powershell: one hour](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=one%20hour) at :file_folder: `./deployment/safe_haven_management_environment/setup`

```pwsh
PS> ./Setup_SHM_DC.ps1 -shmId <SHM ID>
```

+ where `<SHM ID>` is the [management environment ID](#management-environment-id) for this SHM

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#house_with_garden-9-deploy-and-configure-domain-controllers) documentation for more details

#### :pencil: Notes
+ Do not configure the domain controller yet

## :closed_lock_with_key: 11. Suspend MFA for all users

![Azure AD: under a minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=under%20a%20minute)

+ From the Azure portal, navigate to the AAD.
+ Click `Security` in the left hand sidebar
+ Click `Conditional access` in the left hand sidebar
+ Click the `Require MFA` policy from the policy list
  + Toggle `Enable policy` to `Off`
  + Click the `Save` button

## Copy SHM users

![Powershell: five minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=five%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

```pwsh
PS> ./Copy_SHM_Users.ps1 -oldShmId <old SHM ID> -newShmId <SHM ID>
```

+ where `<old SHM ID>` is the [management environment ID](#management-environment-id) for the previously deployed SHM
+ where `<SHM ID>` is the [management environment ID](#management-environment-id) for this SHM
