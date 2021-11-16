# Migrating an SHM

This document assumes that you have already deployed a {ref}`Safe Haven Management (SHM) environment <deploy_shm>` and one or more {ref}`Secure Research Environments (SREs) <deploy_sre>` that are linked to it.

It will help you update the SHM to a newer release by deploying a new SHM and migrating the users to it.

Testing |:e-mail:| |:wrench:|

## :mailbox_with_mail: Table of contents

+ [:seedling: 1. Prerequisites](#seedling-1-prerequisites)
+ [:unlock: 2. Disconnect the old domain controller from the Azure Active Directory](#unlock-2-disconnect-the-old-domain-controller-from-the-azure-active-directory)
+ [:clipboard: 3. Safe Haven Management configuration](#clipboard-3-safe-haven-management-configuration)
+ [:door: 4. Configure DNS for the custom domain](#door-4-configure-dns-for-the-custom-domain)
+ [:file_folder: 5 Ensure the Azure Active Directory domain is registered](#file_folder-5-ensure-the-azure-active-directory-domain-is-registered)
+ [:key: 6. Deploy Key Vault for SHM secrets and create emergency admin account](#key-6-deploy-key-vault-for-shm-secrets-and-create-emergency-admin-account)
+ [:station: 7. Deploy network and VPN gateway](#station-7-deploy-network-and-vpn-gateway)
+ [:house_with_garden: 8. Deploy the domain controllers](#house_with_garden-8-deploy-the-domain-controllers)
+ [:zap: 9. Configure the new domain controllers](#zap-9-configure-the-new-domain-controllers)
  + [:lock_with_ink_pen: Suspend MFA for all users](#lock_with_ink_pen-suspend-mfa-for-all-users)
  + [:busts_in_silhouette: Copy SHM users from old domain controller](#busts_in_silhouette-copy-shm-users-from-old-domain-controller)
  + [:anchor: Reset Azure AD source anchors](#anchor-reset-azure-ad-source-anchors)
  + [:train: Install Azure Active Directory Connect](#train-install-azure-active-directory-connect)
  + [:recycle: Update Azure Active Directory Connect rules](#recycle-update-azure-active-directory-connect-rules)
  + [:put_litter_in_its_place: Unregister the old domain controller in Azure Active Directory](#put_litter_in_its_place-unregister-the-old-domain-controller-in-azure-active-directory)
  + [:ballot_box_with_check: Validate Active Directory synchronisation](#ballot_box_with_check-validate-active-directory-synchronisation)
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

The following variables will be used during deploying

+ `<old SHM ID>`: the [management environment ID](#management-environment-id) for the previously deployed SHM
+ `<SHM ID>`: the [management environment ID](#management-environment-id) for the new SHM you want to deploy
+ `<AAD tenant ID>`: the `Tenant ID` for the Azure Active Directory that your previously deployed SHM is connected to

## :unlock: 2. Disconnect the old domain controller from the Azure Active Directory

![Remote: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=one%20minute)

+ Log into the **SHM primary domain controller** for the old SHM (`DC1-SHM-<old SHM ID>`) VM using the `private IP address`, `<admin login>` and `<admin password>` from the portal
+ Open Powershell as an administrator
  + Navigate to `C:\Installation`
  + Run `.\Disconnect_AD.ps1`
  + You will need to provide login credentials (including MFA if set up) for `<admin username>@<SHM domain>`

+ :warning: Do not attempt to add users to the old SHM after this point as they will not be synchronised to the Azure Active Directory!

### :pencil: Notes

+ Full disconnection of the Azure Active Directory can take up to 72 hours but will typically take around one day

## :clipboard: 3. Safe Haven Management configuration

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

## :door: 4. Configure DNS for the custom domain

![Powershell: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#door-3-configure-dns-for-the-custom-domain) documentation for more details

## :file_folder: 5 Ensure the Azure Active Directory domain is registered

![Powershell: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#file_folder-4-setup-azure-active-directory-aad) documentation for more details

### :pencil: Notes

+ You will need to use an AAD global admin when the `AzureAD` module asks you to sign-in.

## :key: 6. Deploy Key Vault for SHM secrets and create emergency admin account

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#key-5-deploy-key-vault-for-shm-secrets-and-create-emergency-admin-account) documentation for more details

### :pencil: Notes

+ You will need to use an AAD global admin when the `AzureAD` module asks you to sign-in.

## :station: 7. Deploy network and VPN gateway

![Powershell: twenty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=twenty%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

Follow the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#station-8-deploy-network-and-vpn-gateway) documentation for instructions on VPN gateway setup

## :house_with_garden: 8. Deploy the domain controllers

![Powershell: one hour](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=one%20hour) at :file_folder: `./deployment/safe_haven_management_environment/setup`

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#house_with_garden-9-deploy-and-configure-domain-controllers) documentation for more details

### :pencil: Notes

+ Do **not** run any of the domain controller configuration steps yet

## :zap: 9. Configure the new domain controllers

### :lock_with_ink_pen: Suspend MFA for all users

![Azure AD: under a minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=under%20a%20minute)

+ From the Azure portal, navigate to the AAD.
+ Click `Security` in the left hand sidebar
+ Click `Conditional access` in the left hand sidebar
+ Click the `Require MFA` policy from the policy list
  + Toggle `Enable policy` to `Off`
  + Click the `Save` button

### :busts_in_silhouette: Copy SHM users from old domain controller

![Powershell: five minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=five%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

```powershell
PS> ./Copy_SHM_Users.ps1 -oldShmId <old SHM ID> -newShmId <SHM ID>
```

+ where `<old SHM ID>` is the [management environment ID](#management-environment-id) for the previously deployed SHM
+ where `<SHM ID>` is the [management environment ID](#management-environment-id) for this SHM

### :anchor: Reset Azure AD source anchors

![Remote: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=ten%20minutes)

+ Log into the **SHM primary domain controller** (`DC1-SHM-<SHM ID>`) VM that you have just deployed using the `private IP address`, `<admin login>` and `<admin password>` that you obtained from the portal

Run the following `Powershell` commands

```powershell
# Get local users
$userOuPath = (Get-ADObject -Filter * | Where-Object { $_.Name -eq "Safe Haven Research Users" }).DistinguishedName
$users = Get-ADUser -Filter * -SearchBase "$userOuPath" -Properties *

# Connect to AzureAD
# Use the credentials for an AzureAD global admin (eg. `aad.admin.firstname.surname@<SHM domain>`)
Connect-MsolService

# Reset source anchor for AzureAD users
foreach ($user in $users) {
  $immutableId = [System.Convert]::ToBase64String($user.ObjectGUID.ToByteArray())
  Set-MsolUser -UserPrincipalName $($user.UserPrincipalName) -immutableID $immutableId
  Write-Host "Set source anchor for $($user.UserPrincipalName) to $immutableId"
}
```

#### :pencil: Notes

+ Note that all research users in this SHM will have to go to `aka.ms/sspr` to reset their passwords although their MFA configuration will stay the same

### :train: Install Azure Active Directory Connect

![Remote: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=ten%20minutes)

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#install-azure-active-directory-connect) documentation for more details

#### :pencil: Notes

Since you are trying to connect the new SHM to an Azure Active Directory that was already synchronised, you may find the `AzureADConnect` installation fails with an error like the one below. If this happens then you will need to wait for up to 72 hrs for the previous disconnection to complete.

<details><summary><b>Directory synchronisation failure</b></summary>

![aad_connection_failure](../../images/deploy_shm/aad_connection_failure.png)
</details>

### :recycle: Update Azure Active Directory Connect rules

![Remote: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=one%20minute)

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#update-azure-active-directory-connect-rules) documentation for more details

### :put_litter_in_its_place: Unregister the old domain controller in Azure Active Directory

![Azure AD: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=one%20minute)

+ From the Azure portal, navigate to the AAD you have created.
+ Select `Azure AD Connect` from the left hand menu
+ Under `Health And Analytics` click `Azure AD Connect Health`
+ Select `Sync services` from the left hand menu
+ Click on `<Safe Haven identifier>.onmicrosoft.com` whose `Status` will be marked as `Unhealthy`
+ Click on the `Azure Active Directory Connect Server` that corresponds to the **old** DC (marked as `Unhealthy`)
+ Click `Delete` in the top bar, type the server name when prompted then click `Delete`

### :ballot_box_with_check: Validate Active Directory synchronisation

![Remote: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=one%20minute)

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#validate-active-directory-synchronisation) documentation for more details

## :police_car: 10. Deploy and configure network policy server

![Powershell: twenty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=twenty%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#police_car-10-deploy-and-configure-network-policy-server) documentation for more details

## :closed_lock_with_key: 11. Require MFA for all users

![Azure AD: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=a%20few%20minutes)

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#closed_lock_with_key-11-require-mfa-for-all-users) documentation for more details

## :fire_engine: 12. Deploy firewall

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#fire_engine-12-deploy-firewall) documentation for more details

## :package: 13. Deploy Python/R package repositories

![Powershell: thirty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=thirty%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#package-13-deploy-PythonR-package-repositories) documentation for more details

## :chart_with_upwards_trend: 14. Deploy logging

![Powershell: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20minutes) at :file_folder: `./deployment/safe_haven_management_environment/setup`

See the [Safe Haven Management](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#chart_with_upwards_trend-14-deploy-logging) documentation for more details
