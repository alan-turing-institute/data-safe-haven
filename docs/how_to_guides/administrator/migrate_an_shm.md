# Migrating an SHM

This document assumes that you have already deployed a [Safe Haven Management (SHM) environment](../../tutorial/deployment_tutorials/how-to-deploy-shm.md) and one or more [Secure Research Environments (SRE)](../../tutorial/deployment_tutorials/how-to-deploy-sre.md) that are linked to it.

It will help you update the SHM to a newer release by deploying a new SHM and migrating the users to it.

## :mailbox_with_mail: Table of contents

+ [:seedling: 1. Prerequisites](#seedling-1-prerequisites)
+ [:clipboard: 2. Safe Haven Management configuration](#clipboard-2-safe-haven-management-configuration)
+ [:door: 3. Configure DNS for the custom domain](#door-3-configure-dns-for-the-custom-domain)
+ [:file_folder: 4. Ensure the Azure Active Directory domain is registered](#file_folder-4-ensure-the-azure-active-directory-domain-is-registered)
+ [:key: 5. Deploy Key Vault for SHM secrets and create emergency admin account](#key-5-deploy-key-vault-for-shm-secrets-and-create-emergency-admin-account)
+ [:station: 6. Deploy network and VPN gateway](#station-6-deploy-network-and-vpn-gateway)
+ [:house_with_garden: 7. Deploy and configure domain controllers](#house_with_garden-7-deploy-and-configure-domain-controllers)
  + [:closed_lock_with_key: Suspend MFA for all users](#closed_lock_with_key-suspend-mfa-for-all-users)
  + [:arrow_right_hook: Copy SHM users from old domain controller](#arrow_right_hook-copy-shm-users-from-old-domain-controller)
  + [:unlock: Disconnect the old domain controller from the Azure Active Directory](#unlock-disconnect-the-old-domain-controller-from-the-azure-active-directory)
  + [:anchor: Install Azure Active Directory Connect](#anchor-install-azure-active-directory-connect)
  + [:recycle: Update Azure Active Directory Connect rules](#recycle-update-azure-active-directory-connect-rules)
  + [:ballot_box_with_check: Validate Active Directory synchronisation](#ballot_box_with_check-validate-active-directory-synchronisation)
+ [:police_car: 8. Deploy and configure network policy server](#police_car-8-deploy-and-configure-network-policy-server)
+ [:closed_lock_with_key: 9. Require MFA for all users](#closed_lock_with_key-9-require-mfa-for-all-users)
+ [:fire_engine: 10. Deploy firewall](#fire_engine-10-deploy-firewall)
+ [:package: 11. Deploy Python/R package repositories](#package-11-deploy-PythonR-package-repositories)
+ [:chart_with_upwards_trend: 12. Deploy logging](#chart_with_upwards_trend-12-deploy-logging)

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

## :station: 6. Deploy network and VPN gateway

![Powershell: twenty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=twenty%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

```pwsh
PS> ./Setup_SHM_Networking.ps1 -shmId <SHM ID>
```

+ where `<SHM ID>` is the [management environment ID](#management-environment-id) for this SHM

Follow the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#station-8-deploy-network-and-vpn-gateway) documentation for instructions on VPN gateway setup

## :house_with_garden: 7. Deploy and configure domain controllers

![Powershell: one hour](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=one%20hour) at :file_folder: `./deployment/safe_haven_management_environment/setup`

```pwsh
PS> ./Setup_SHM_DC.ps1 -shmId <SHM ID>
```

+ where `<SHM ID>` is the [management environment ID](#management-environment-id) for this SHM

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#house_with_garden-9-deploy-and-configure-domain-controllers) documentation for more details

#### :pencil: Notes
+ Do not configure the domain controller yet

### :closed_lock_with_key: Suspend MFA for all users

![Azure AD: under a minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=under%20a%20minute)

+ From the Azure portal, navigate to the AAD.
+ Click `Security` in the left hand sidebar
+ Click `Conditional access` in the left hand sidebar
+ Click the `Require MFA` policy from the policy list
  + Toggle `Enable policy` to `Off`
  + Click the `Save` button

### :arrow_right_hook: Copy SHM users from old domain controller

![Powershell: five minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=five%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

```pwsh
PS> ./Copy_SHM_Users.ps1 -oldShmId <old SHM ID> -newShmId <SHM ID>
```

+ where `<old SHM ID>` is the [management environment ID](#management-environment-id) for the previously deployed SHM
+ where `<SHM ID>` is the [management environment ID](#management-environment-id) for this SHM

### :unlock: Disconnect the old domain controller from the Azure Active Directory

![Remote: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=one%20minute)

+ Log into the **SHM primary domain controller** for the old SHM (`DC1-SHM-<old SHM ID>`) VM using the `private IP address`, `<admin login>` and `<admin password>` from the portal
+ Open Powershell as an administrator
  + Navigate to `C:\Installation`
  + Run `.\Disconnect_AD.ps1`
  + You will need to provide login credentials (including MFA if set up) for `<admin username>@<SHM domain>`
+ Full disconnection of the Azure Active Directory can take up to 72 hours but is typically less.

### :anchor: Install Azure Active Directory Connect

![Remote: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=ten%20minutes)

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#install-azure-active-directory-connect) documentation for more details

#### :pencil: Notes

Since you are trying to connect the new SHM to an Azure Active Directory that was already synchronised, you may find the `AzureADConnect` installation step requires you to wait for up to 72 hrs for the previous disconnection to complete.

### :recycle: Update Azure Active Directory Connect rules

![Remote: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=one%20minute)

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#update-azure-active-directory-connect-rules) documentation for more details

### :ballot_box_with_check: Validate Active Directory synchronisation

![Remote: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=one%20minute)

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#validate-active-directory-synchronisation) documentation for more details

## :police_car: 8. Deploy and configure network policy server

![Powershell: twenty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=twenty%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#police_car-10-deploy-and-configure-network-policy-server) documentation for more details

## :closed_lock_with_key: 9. Require MFA for all users

![Azure AD: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=a%20few%20minutes)

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#closed_lock_with_key-11-require-mfa-for-all-users) documentation for more details

## :fire_engine: 10. Deploy firewall

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#fire_engine-12-deploy-firewall) documentation for more details

## :package: 11. Deploy Python/R package repositories

![Powershell: thirty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=thirty%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#package-13-deploy-PythonR-package-repositories) documentation for more details

## :chart_with_upwards_trend: 12. Deploy logging

![Powershell: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#chart_with_upwards_trend-14-deploy-logging) documentation for more details