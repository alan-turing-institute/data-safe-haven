(deployment_security_checklist)=

# Security evaluation checklist

```{caution}
This security checklist is used by the Alan Turing Institute to evaluate compliance with our default controls.
Organisations are responsible for making their own decisions about the suitability of any of our default controls and should treat this checklist as an example, not a template to follow.
```

In this check list we aim to evaluate our deployment against the {ref}`security configuration <design_turing_security_configuration>` that we apply at the Alan Turing Institute.
The security checklist currently focuses on checks that can evaluate these security requirements for {ref}`policy_tier_2` (or greater) SREs (with some steps noted as specific to a tier):

## How to use this checklist

Ensure you have met the [](#prerequisites).
Work your way through the actions described in each section, taking care to notice each time you see a {{camera}} or a {{white_check_mark}} and the word Verify.

```{note}
- {{camera}} Where you see the camera icon, there should be accompanying screenshot(s) of evidence for this item in the checklist (you may wish to save your own equivalent screenshots as evidence)
- {{white_check_mark}} This indicates a checklist item for which a screenshot is either not appropriate or difficult
```

## Prerequisites

### Roles

The following roles will be needed for this checklist

- {ref}`role_researcher`
- {ref}`role_system_manager`
    - Ensure this person has an account with appropriate permission to deploy the Data Safe Haven
- {ref}`role_data_provider_representative`

Ideally, these roles would be conducted by different people with different IP addresses.
However, you can emulate this by using a VPN.

### Resources

The following resources should be deployed

- An SHM
- A [Tier 2](../deployment/deploy_sre.md#configuration) SRE
- A [Tier 3](../deployment/deploy_sre.md#configuration) SRE

In each SRE configuration

- Ensure the research user's IP address is added to the `research_user_ip_addresses` list.
- Ensure the system manager's IP address is added to the `admin_ip_addresses` list.
- Ensure the data provider's IP address is added to the `data_provider_ip_addresses` list.

### Accounts

[Create a user account](../management/index.md#add-users-to-the-data-safe-haven) for the research user in your SHM.
Do not register this user with any SRE yet.

## 1. Multifactor authentication and password strength

### Turing configuration setting:

- Users must set up MFA before accessing the secure analysis environment.
- Users cannot access the environment without MFA.
- Users are required/advised to create passwords of a certain strength.

### Implication:

- Users are required to authenticate with Multi-factor Authentication (MFA) in order to access the secure analysis environment.
- Passwords are strong

### Verify by:

#### Check: Users can reset their own password

- Attempt to login to the remote desktop web client as the research user.
- Click "Forgotten my password".
- Reset password.

````{attention}
{{camera}} <b>Verify that:</b>
 <details><summary> user can reset their own password</summary>

```{image} security_checklist/sspr.png
:align: center
```
```{image} security_checklist/sspr_success.png
:align: center
```

</details>
````

#### Check: Non-registered users cannot connect to any SRE workspace

Attempt to login to the remote desktop web client as the research user.

````{attention}
{{camera}} <b>Verify that:</b>
 <details><summary>user can authenticate but cannot see any workspaces</summary>

```{image} security_checklist/no_valid_workspaces.png
:align: center
```

</details>
````

#### Check: Registered users can see SRE workspaces

Check that the research user can authenticate using MFA and is granted access to the SRE.

- Login to the remote desktop web client as the research user.

````{attention}
{{camera}} <b>Verify that:</b>
<details><summary>user can authenticate and can see workspaces</summary>

```{image} security_checklist/valid_workspaces.png
:align: center
```

</details>
````

#### Check: Authenticated user can access workspaces

Check that the research user can access a workspace.

- Login to the remote desktop web client as the research user.
- Select a workspace and login as the research user.

````{attention}
{{camera}} <b>Verify that:</b>
<details><summary>you can connect to any workspace</summary>

```{image} security_checklist/workspace_xfce_initial.png
:align: center
```

</details>
````

## 2. Isolated Network

### Turing configuration setting:

- The only part of the SRE a {ref}`Researcher <role_researcher>` can access from the internet is the remote desktop web client.
- From within the SRE, a {ref}`Researcher <role_researcher>` cannot connect to clients outside the SRE network (with the exception of indirect, read-only access to package repositories).
- SREs are isolated from one another.

### Implication:

- The Data Safe Haven network is isolated from external connections (both {ref}`policy_tier_2` and {ref}`policy_tier_3`)

### Verify by:

#### Fail to connect to the internet from a workspace

- Connect to an SRE workspace by using the web client.
- Attempt to access the internet using a browser and CLI tools.

````{attention}
{{camera}} <b>Verify that:</b>

<details><summary>browsing to the service fails</i></summary>

```{image} security_checklist/no_internet_browser.png
:align: center
```

</details>

<details><summary>you cannot access the service using curl</summary>

```{image} security_checklist/no_internet_curl.png
:align: center
```

</details>

<details><summary>you cannot look up the IP address for the service using nslookup</summary>

```{image} security_checklist/no_nslookup.png
:align: center
```
</details>
````

## 3. User devices

### Turing configuration setting:

- Managed devices must be provided by an approved organisation and the user must not have administrator access to them.
- Access is only permitted from IPs listed in the `research_user_ip_addresses` configuration parameter.

### Implication:

- At {ref}`policy_tier_3`, only managed devices can connect to the Data Safe Haven environment.
- At {ref}`policy_tier_2`, any device can connect to the Data Safe Haven environment.

### Verify by:

#### User devices ({ref}`policy_tier_2`)

- Connect to the environment using an allowed IP address and credentials

```{attention}
{{white_check_mark}} Verify that: connection succeeds
```

- Connect to the environment from an IP address that is not allowed but with correct credentials.

```{attention}
{{white_check_mark}} Verify that: connection fails
```

#### User devices ({ref}`policy_tier_3`)

All managed devices should be provided by a known IT team at an approved organisation.

```{attention}
{{white_check_mark}} Verify that: the IT team of the approved organisation take responsibility for managing the device.
```

```{attention}
{{white_check_mark}} Verify that: the user does not have administrator permissions on the device.
```

```{attention}
{{white_check_mark}} Verify that: allowed IP addresses are exclusive to managed devices.
```

- Connect to the environment using an allowed IP address and credentials

```{attention}
{{white_check_mark}} Verify that: connection succeeds
```

- Connect to the environment from an IP address that is not allowed but with correct credentials.

```{attention}
{{white_check_mark}} Verify that: connection fails
```

#### Network rules ({ref}`policy_tier_2` and above):

There are network rules permitting access to the portal from allowed IP addresses only

- In the Azure portal navigate to the Guacamole application gateway NSG for this SRE `shm-<SHM ID>-sre-<SRE ID>-nsg-application-gateway`.

````{attention}
{{camera}} <b>Verify that:</b>

<details><summary>the NSG has network rules allowing Inbound access from allowed IP addresses only</summary>

```{image} security_checklist/nsg_inbound_access.png
:align: center
```
</details>
````

```{attention}
{{white_check_mark}} Verify that: all other NSGs have an inbound `Deny All` rule and no higher priority rule allowing inbound connections from outside the Virtual Network.
```

## 4. Physical security

### Turing configuration setting:

- Medium security research spaces control the possibility of unauthorised viewing.
- Card access or other means of restricting entry to only known researchers (such as the signing in of guests on a known list) is required.
- Screen adaptations or desk partitions can be adopted in open-plan spaces if there is a high risk of "visual eavesdropping".
- Firewall rules can permit access only from IP ranges corresponding to these research spaces.

### Implication:

- At {ref}`policy_tier_3` access is limited to certain secure physical spaces.

### Verify by:

#### Physical security ({ref}`policy_tier_3`)

Connection from outside the secure physical space is not possible.

- Attempt to connect to the {ref}`policy_tier_3` SRE web client from home using a managed device and the correct VPN connection and credentials.

```{attention}
{{white_check_mark}} Verify that: connection fails.
```

Connection from within the secure physical space is possible.

- Attempt to connect from research office using a managed device and the correct VPN connection and credentials.

```{attention}
{{white_check_mark}} Verify that: connection succeeds.
```

```{attention}
{{white_check_mark}} Verify that: check the network IP ranges corresponding to the research spaces and compare against the IPs accepted by the firewall.
```

```{attention}
{{white_check_mark}} Verify that: confirm in person that physical measures such as screen adaptions or desk partitions are present if risk of visual eavesdropping is high.
```

## 5. Remote connections

### Turing configuration setting:

- User can connect via remote desktop but cannot connect through other means such as SSH

### Implication:

- Connections can only be made via remote desktop ({ref}`policy_tier_2` and above)

### Verify by:

#### SSH connection is not possible

- Attempt to login as the research user via SSH with `ssh <user.name>@<SRE ID>.<safe haven domain>` (e.g. `ssh -v -o ConnectTimeout=10 ada.lovelace@sandbox.turingsafehaven.ac.uk`).

````{attention}
{{camera}} <b>Verify that:</b>

<details><summary>SSH login by fully-qualified domain name fails</summary>

```{image} security_checklist/no_ssh_fqdn.png
:align: center
```
</details>
````

- Find the public IP address for the remote desktop web client.
    - {{pear}} This will be given by the resource `shm-<SHM ID>-sre-<SRE ID>-public-ip`.
- Attempt to login as the research user via `SSH` with `ssh <user.name>@<public IP>` (_e.g._ `ssh ada.lovelace@8.8.8.8`).

````{attention}
{{camera}} <b>Verify that:</b>

<details><summary>SSH login by public IP address fails</summary>

```{image} security_checklist/no_ssh_ip.png
:align: center
```
</details>
````

```{attention}
{{white_check_mark}} Verify that: the remote desktop web client application gateway (`shm-<SHM ID>-sre-<SRE ID>-ag-entrypoint`), and the firewall, are the only SRE resources with public IP addresses.
```

## 6. Copy-and-paste

### Turing configuration setting:

- Users cannot copy data from outside the SRE and paste it into the SRE.
- Users cannot copy data from within the SRE and paste it outside the SRE.

### Implication:

- Copy and paste is disabled on the remote desktop.

### Verify by:

#### Users are unable to copy-and-paste between the SRD and their local device

- Copy some text from your local device.
- Connect to a workspace as the research user via the remote desktop web client.
- Open a text editor or terminal on the SRD and attempt to paste the text to it.

```{attention}
{{white_check_mark}} Verify that: paste fails
```

- Write some text in a text editor or terminal of the workspace and copy it.
- Attempt to paste the text on your local device.

```{attention}
{{white_check_mark}} Verify that: paste fails
```

## 7. Data ingress

### Turing configuration setting:

- Prior to access to the ingress volume being provided, the {ref}`role_data_provider_representative` must provide the IP address(es) from which data will be uploaded and a secure mechanism by which a time-limited upload token can be sent, such as an encrypted email system.
- Once these details have been received, the data ingress volume should be opened for data upload.

To minimise the risk of unauthorised access to the dataset while the ingress volume is open for uploads, the following security measures are in place:

- Access to the ingress volume is restricted to a limited range of IP addresses associated with the Dataset Provider and the host organisation.
- The {ref}`role_data_provider_representative` receives a write-only upload token.
    - This allows them to upload, verify and modify the uploaded data, but does not viewing or download of the data.
    - This provides protection against an unauthorised party accessing the data, even they gain access to the upload token.
- The upload token expires after a time-limited upload window.
- The upload token is transferred to the Dataset Provider via the provided secure mechanism.

### Implication:

- All data transfer to the Data Safe Haven should be via our secure data transfer process, which gives the {ref}`role_data_provider_representative` time-limited, write-only access to a dedicated data ingress volume from a specific location.
- Data is stored securely until approved for user access.

### Verify by:

#### Check that the {ref}`role_system_manager` can send an upload token to the {ref}`role_data_provider_representative` over a secure channel

- Use the IP address of your own device in place of that of the data provider.
- Generate an upload token with only Write and List permissions.

```{attention}
{{white_check_mark}} Verify that: the upload token is successfully created.
```

```{attention}
{{white_check_mark}} Verify that: you are able to send this token using a secure mechanism.
```

#### Ensure that data ingress works only for connections from the accepted IP address range

- As the {ref}`role_data_provider_representative`, ensure you're working from a device that has an allowed IP address.
- Using the upload token with write-only permissions and limited time period that you set up in the previous step, follow the ingress instructions for the {ref}`data provider <role_data_provider_representative>`.

```{attention}
{{white_check_mark}} Verify that: writing succeeds by uploading a file
```

```{attention}
{{white_check_mark}} Verify that: attempting to open or download any of the files results in the following error: `Failed to start transfer: Insufficient credentials.` under the `Activities` pane at the bottom of the MS Azure Storage Explorer window.
```

- Switch to a device without an allowed IP address (or change your IP with a VPN)
- Attempt to write to the ingress volume via the test device

```{attention}
{{white_check_mark}} Verify that: the access token fails.
```

#### Check that the upload fails if the token has expired

- Create a write-only token with short duration

```{attention}
{{white_check_mark}} Verify that: you can connect and write with the token during the duration
```

```{attention}
{{white_check_mark}} Verify that: you cannot connect and write with the token after the duration has expired
```

```{attention}
{{white_check_mark}} Verify that: the data ingress process works by uploading different kinds of files, e.g. data, images, scripts (if appropriate).
```

## 8. Data egress

### Turing configuration setting:

- Research users can write to the `/mnt/output` volume.
- A {ref}`role_system_manager` can view and download data in the `/mnt/output` volume via `Azure Storage Explorer`.

### Implication:

- SREs contain an `/mnt/output` volume, in which SRE users can store data designated for egress.

### Verify by:

#### Confirm that a non-privileged user is able to read the different storage volumes and write to output

- Login to an SRD as the research user via the remote desktop web client
- Open up a file explorer and search for the various storage volumes

```{attention}
{{white_check_mark}} Verify that: the `/mnt/output` volume exists and can be read and written to.
```

```{attention}
{{white_check_mark}} Verify that: the permissions of other storage volumes match that described in the [user guide](../roles/researcher/using_the_sre.md#-sharing-files-inside-the-sre).
```

#### Confirm that {ref}`role_system_manager` can see and download files from output

- As the {ref}`role_system_manager`, follow the instructions in the [project manager documentation](../roles/project_manager/data_egress.md#data-egress-process) on how to access files set for egress with `Azure Storage Explorer`.

```{attention}
{{white_check_mark}} Verify that: you can see the files written to the `/mnt/output` storage volume.
```

```{attention}
{{white_check_mark}} Verify that: a written file can be taken out of the environment via download
```

## 9. Software package repositories

### Turing configuration setting::

- {ref}`policy_tier_2`: The user can access any package from our mirrors or via our proxies. They can freely use these packages without restriction.
- {ref}`policy_tier_3`: The user can only access a specific pre-agreed set of packages. They will be unable to download any package not on the allowed list.

### Implication:

- {ref}`policy_tier_2`: User can access all packages from PyPI/CRAN.
- {ref}`policy_tier_3`: User can only access approved packages from PyPI/CRAN.

### Verify by:

#### {ref}`policy_tier_2`: Download a package that is not on the allow list

- Connect to a Tier 2 workspace as the research user via remote desktop web client.
- Attempt to install a package on the allowed list that is not included out-of-the-box (for example, try `python -m venv ./venv && source ./venv/bin/activate && pip install pytz`)

````{attention}
{{camera}} <b>Verify that:</b>

<details><summary>you can install the package</summary>

```{image} security_checklist/pypi_t2_allowed.png
:align: center
```
</details>
````

- Then attempt to install any package that is not on the allowed list (for example, try `pip install -q awscli`)

````{attention}
{{camera}} <b>Verify that:</b>

<details><summary>you can install the package</summary>

```{image} security_checklist/pypi_t2_disallowed.png
:align: center
```
</details>
````

#### {ref}`policy_tier_3`: Download a package on the allow list and one not on the allow list

- Connect to a Tier 3 workspace as the research user via remote desktop web client.
- Attempt to install a package on the allowed list that is not included out-of-the-box (for example, try `python -m venv ./venv && source ./venv/bin/activate && pip install pytz`).

````{attention}
{{camera}} <b>Verify that:</b>

<details><summary>you can install the package</summary>

```{image} security_checklist/pypi_t3_allowed.png
:align: center
```
</details>
````

- Then attempt to download a package that is not included in the allowed list (for example, try `pip install awscli`).

````{attention}
{{camera}} <b>Verify that:</b>

<details><summary>you cannot install the package</summary>

```{image} security_checklist/pypi_t3_disallowed.png
:align: center
```
</details>
````
