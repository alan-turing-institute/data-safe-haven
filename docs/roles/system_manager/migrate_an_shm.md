# Migrating an SHM

These instructions will walk you through migrating an existing Safe Haven Management (SHM) environment to a newer **Data Safe Haven** release and migrating the users to it.

```{note}
This document assumes that you have already deployed a {ref}`Safe Haven Management (SHM) environment <deploy_shm>` and one or more {ref}`Secure Research Environments (SREs) <deploy_sre>` that are linked to it.
```

```{danger}
This is a complex operation and may not always work. You may lose data or user accounts in the migration process.
```

```{include} ../../deployment/snippets/00_symbols.partial.md
:relative-images:
```

## 1. {{seedling}} Prerequisites

- All of the {ref}`Safe Haven Management (SHM) environment <deploy_shm_prerequisites>` prerequisites

The following variables will be used during deploying

- `<old SHM ID>`: the {ref}`management environment ID <roles_deployer_shm_id>` for the previously deployed SHM
- `<SHM ID>`: the {ref}`management environment ID <roles_deployer_shm_id>` for the new SHM you want to deploy
- `<AAD tenant ID>`: the {ref}`Tenant ID <roles_deployer_aad_tenant_id>` for the `Azure Active Directory` that your previously deployed SHM is connected to

## 2. {{unlock}} Disconnect the old domain controller from the Azure Active Directory

![Remote: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=one%20minute)

- Log into the **SHM primary domain controller** for the old SHM (`DC1-SHM-<old SHM ID>`) VM using the `private IP address`, `<admin login>` and `<admin password>` from the portal
- Open `Powershell` as an administrator

  - Navigate to `C:\Installation`
  - Run `.\Disconnect_AD.ps1`
  - You will need to provide login credentials (including MFA if set up) for `<admin username>@<SHM domain>`

```{warning}
Do not attempt to add users to the old SHM after this point as they will not be synchronised to the `Azure` Active Directory!
```

```{attention}
Full disconnection of the `Azure` Active Directory can take up to 72 hours but will typically take around one day.
```

## 3. {{clipboard}} Safe Haven Management configuration

- Create a copy of the configuration file for your previous SHM
- You may want to change some of the following attributes:

```json
{
  "azure": {
    "subscriptionName": "Azure subscription to deploy the SHM into. You might want to use a different subscription than for your previous SHM."
  },
  "shmId": "The <SHM ID> for the new SHM. If you try to deploy two SHMs with the same ID into the same subscription some resources will not deploy correctly."
}
```

## 4. {{door}} Configure DNS for the custom domain

![Powershell: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

See the {ref}`Safe Haven Management documentation <roles_deployer_deploy_shm>` for more details.

## 5. {{file_folder}} Ensure the Azure Active Directory domain is registered

![Powershell: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

See the {ref}`Safe Haven Management documentation <roles_deployer_deploy_shm>` for more details.

```{note}
You will need to use an AAD global admin when the `AzureAD` module asks you to sign-in.
```

## 6. {{key}} Deploy Key Vault for SHM secrets and create emergency admin account

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

See the {ref}`Safe Haven Management documentation <roles_deployer_deploy_shm>` for more details.

```{note}
You will need to use an AAD global admin when the `AzureAD` module asks you to sign-in.
```

## 7. {{station}} Deploy network and VPN gateway

![Powershell: twenty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=twenty%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

See the {ref}`Safe Haven Management documentation <roles_deployer_deploy_shm>` for more details.

## 8. {{house_with_garden}} Deploy the domain controllers

![Powershell: one hour](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=one%20hour) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

See the {ref}`Safe Haven Management documentation <roles_deployer_deploy_shm>` for more details.

```{important}
Do **not** run any of the domain controller configuration steps yet
```

## 9. {{zap}} Configure the new domain controllers

### {{lock_with_ink_pen}} Suspend MFA for all users

![Azure AD: under a minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=under%20a%20minute)

- From the `Azure` portal, navigate to the AAD.
- Click `Security` in the left hand sidebar
- Click `Conditional access` in the left hand sidebar
- Click the `Require MFA` policy from the policy list
  - Toggle `Enable policy` to `Off`
  - Click the `Save` button

### {{busts_in_silhouette}} Copy SHM users from old domain controller

![Powershell: five minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=five%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

```powershell
PS> ./Copy_SHM_Users.ps1 -oldShmId <old SHM ID> -newShmId <SHM ID>
```

- where `<old SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for the previously deployed SHM
- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SHM

### {{anchor}} Reset Azure AD source anchors

![Remote: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=ten%20minutes)

- Log into the **SHM primary domain controller** (`DC1-SHM-<SHM ID>`) VM that you have just deployed using the `private IP address`, `<admin login>` and `<admin password>` that you obtained from the portal

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
  Write-Output "Set source anchor for $($user.UserPrincipalName) to $immutableId"
}
```

```{note}
All research users in this SHM will have to go to `https://aka.ms/sspr` to reset their passwords although their MFA configuration will stay the same.
```

### {{train}} Install Azure Active Directory Connect

![Remote: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=ten%20minutes)

See the {ref}`Safe Haven Management documentation <roles_deployer_shm_aad_connect>` for more details.

````{error}
Since you are trying to connect the new SHM to an `Azure` Active Directory that was already synchronised, you may find the `AzureADConnect` installation fails due to a `Directory synchronisation failure`.

```{image} migrate_shm/aad_connection_failure.png
:alt: AAD connection failure
:align: center
```

If this happens then you will need to wait for the previous disconnection to complete, which may take up to 72 hours.
````

### {{recycle}} Update Azure Active Directory Connect rules

![Remote: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=one%20minute)

See the {ref}`Safe Haven Management documentation <roles_system_deployer_shm_aad_connect_rules>` for more details.

### {{put_litter_in_its_place}} Unregister the old domain controller in `Azure` Active Directory

![Azure AD: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=one%20minute)

- From the `Azure` portal, navigate to the AAD you have created.
- Select `Azure AD Connect` from the left hand menu
- Under `Health And Analytics` click `Azure AD Connect Health`
- Select `Sync services` from the left hand menu
- Click on `<Safe Haven identifier>.onmicrosoft.com`
- Click on the `Azure Active Directory Connect Server` that corresponds to the **old** DC (marked as `Unhealthy`)
- Click `Delete` in the top bar, type the server name when prompted then click `Delete`

### {{ballot_box_with_check}} Validate Active Directory synchronisation

![Remote: one minute](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=one%20minute)

See the {ref}`Safe Haven Management documentation <roles_deployer_deploy_shm>` for more details.

## 10. {{police_car}} Deploy and configure network policy server

![Powershell: twenty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=twenty%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

See the {ref}`Safe Haven Management documentation <roles_deployer_deploy_shm>` for more details.

## 11. {{closed_lock_with_key}} Require MFA for all users

![Azure AD: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=a%20few%20minutes)

See the {ref}`Safe Haven Management documentation <roles_deployer_deploy_shm>` for more details.

## 12. {{no_pedestrians}} Block portal access for normal users

![Azure AD: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=a%20few%20minutes)

See the {ref}`Safe Haven Management documentation <roles_deployer_deploy_shm>` for more details.

## 13. {{package}} Deploy Python/R package repositories

![Powershell: thirty minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=thirty%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

See the {ref}`Safe Haven Management documentation <roles_deployer_deploy_shm>` for more details.

## 14. {{chart_with_upwards_trend}} Deploy logging

![Powershell: a few minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

See the {ref}`Safe Haven Management documentation <roles_deployer_deploy_shm>` for more details.

## 15. {{fire_engine}} Deploy firewall

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at {{file_folder}} `./deployment/safe_haven_management_environment/setup`

See the {ref}`Safe Haven Management documentation <roles_deployer_deploy_shm>` for more details.
