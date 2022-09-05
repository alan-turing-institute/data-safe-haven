(design_security_claims)=

# Security Objectives

The diagram below shows an overview of the security standards we're trying to meet for Secure Research Environments (SREs) hosted at the Turing.

```{caution}
The Turing does not yet operate any {ref}`policy_tier_4` environments and so our suggested default controls for {ref}`policy_tier_4` environments are still under development.
Organisations are responsible for making their own decisions about the suitability of any of our default controls, but should be especially careful about doing so if considering using the Data Safe Haven for projects at the {ref}`policy_tier_4` sensitivity level.
```

```{image} recommended_controls.png
:alt: Recommended security controls
:align: center
```

Below we outline how we attempt to meet this requirements

## 1. Multifactor authentication and password strength

### We claim:

- Users are required to authenticate with Multi-factor Authentication (MFA) in order to access the secure analysis environment.
- Passwords are strong.

### Which means:

- Users must set up MFA before accessing the secure analysis environment.
- Users cannot access the environment without MFA.
- Users are required/advised to create passwords of a certain strength.

## 2. Isolated Network

### We claim:

- The Data Safe Haven network is isolated from external connections (both {ref}`policy_tier_2` and {ref}`policy_tier_3`).

### Which means:

- {ref}`Researchers <role_researcher>` cannot access any part of the network from outside the network.
- VMs in the SHM are only accessible by {ref}`System Managers <role_system_manager>` using the management VPN.
- Whilst in the network, one cannot use the internet to connect outside the network.
- SREs in the same SHM are isolated from one another.

## 3. User devices

### We claim:

- At {ref}`policy_tier_3`, only managed devices can connect to the Data Safe Haven environment.
- At {ref}`policy_tier_2`, any device can connect to the Data Safe Haven environment (with VPN connection and correct credentials).

### Which means:

- Managed devices must be provided by an approved organisation and the user must not have administrator access to them.
- Network rules for higher tier environments permit access only from IP ranges corresponding to `Restricted` networks that only permit managed devices to connect.

## 4. Physical security

### We claim:

- At {ref}`policy_tier_3` access is limited to certain secure physical spaces.

### Which means:

- Medium security research spaces control the possibility of unauthorised viewing.
- Card access or other means of restricting entry to only known researchers (such as the signing in of guests on a known list) is required.
- Screen adaptations or desk partitions can be adopted in open-plan spaces if there is a high risk of "visual eavesdropping".
- Firewall rules for the Environments can permit access only from `Restricted` network IP ranges corresponding to these research spaces.

## 5. Remote connections

### We claim:

- Connections can only be made via remote desktop ({ref}`policy_tier_2` and above).
- This remote desktop connection is only available through a browser at a URL which can only be accessed from approved IP addresses.

### Which means:

- User can connect via remote desktop but cannot connect through other means such as `SSH`.

## 6. Copy-and-paste

### We claim:

- Copy and paste is disabled on the remote desktop for tiers 2 and above.

### Which means:

- Users cannot copy something from outside the network and paste it into the network.
- Users cannot copy something from within the network and paste it outside the network.

## 7. Data ingress

### We claim:

- All data transfer to the Data Safe Haven should be via our secure data transfer process, which gives the {ref}`role_data_provider_representative` time-limited, write-only access to a dedicated data ingress volume from a specific location.
- Data is stored securely until approved for user access.

### Which means:

- Prior to access to the ingress volume being provided, the {ref}`role_data_provider_representative` must provide the IP address(es) from which data will be uploaded and an email address to which a secure upload token can be sent.
- Once these details have been received, the data ingress volume should be opened for data upload.

To minimise the risk of unauthorised access to the dataset while the ingress volume is open for uploads, the following security measures are in place:

- Access to the ingress volume is restricted to a limited range of IP addresses associated with the **Dataset Provider** and the **host organisation**.
- The {ref}`role_data_provider_representative` receives a write-only upload token.
  - This allows them to upload, verify and modify the uploaded data, but does not viewing or download of the data.
  - This provides protection against an unauthorised party accessing the data, even they gain access to the upload token.
- The upload token expires after a time-limited upload window.
- The upload token is transferred to the Dataset Provider via a secure email system.

## 8. Data egress

### We claim:

- SREs contain an `/output` volume, in which SRE users can store data designated for egress.

### Which means::

- Users can write to the `/output` volume.
- A {ref}`role_system_manager` can view and download data in the `/output` volume via `Azure Storage Explorer`.

## 9. Software ingress

### We claim:

- The base SRD provided in the SREs comes with a wide range of common data science software pre-installed, as well as package mirrors.
- Additional software must be added separately via ingress.

### Which means:

- For {ref}`policy_tier_0` and {ref}`policy_tier_1` environments, outbound internet access means users can directly download their software from the internet.
- For {ref}`policy_tier_2` or higher environments we use the secure data transfer process.

- Installation during deployment
  - If known in advance, software can be installed during SRD deployment whilst there is still internet access, but before project data is added. Once the software is installed, the SRD undergoes ingress into the environment with a one way lock.
- Installation after deployment
  - Once an SRD has been deployed into the analysis environment it cannot be moved out. There is no outbound internet access.
  - Software is added via ingress in a similar manner to data:
    - Researchers are provided temporary write-only access to the software ingress volume.
    - The access is then revoked and the software is then reviewed.
    - If it passes review, the software is moved into the environment.
  - If the software requires administrator rights to install, a {ref}`role_system_manager` must do this. Otherwise, the researcher can do this themselves.

## 10. Software package repositories

### We claim:

- {ref}`policy_tier_2`: User can access all packages from PyPI/CRAN.
- {ref}`policy_tier_3`: User can only access approved packages from PyPI/CRAN. Allowed list is in `environment_configs/package_lists`.

### Which means::

- {ref}`policy_tier_2`: The user can access any package from our mirrors. They can freely use these packages without restriction.
- {ref}`policy_tier_3`: The user can only access a specific pre-agreed set of packages. They will be unable to download any package not on the allowed list.

## 11. Firewall controls

### We claim:

- An `Azure Firewall` ensures that all VMs within the safe haven have the minimal level of internet access required to function.

### Which means:

- Research accessible SRD VMs can only access a limited set of domains required for managing software and virus definition updates.
- Administrator accessible VMs can access additional domains required to perform their functionality (e.g. user authentication, providing SRD VMs access to authorised packages)
