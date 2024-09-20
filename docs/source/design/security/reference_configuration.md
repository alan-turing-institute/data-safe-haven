(design_turing_security_configuration)=

# Turing security configuration

The set of controls applied at the Alan Turing Institute are discussed here, together with their implications.

## 1. Multifactor authentication and password strength

### Turing configuration setting:

- Users must set up MFA before accessing the secure analysis environment.
- Users cannot access the environment without MFA.
- Users are required to create passwords that meet the [Microsoft Entra policy](https://learn.microsoft.com/en-us/entra/identity/authentication/concept-sspr-policy) requirements.

### Implication:

- Users will need multi-factor authentication (MFA) in order to access the secure analysis environment.
- Users will have strong passwords.

## 2. Isolated Network

### Turing configuration setting:

- {ref}`Researchers <role_researcher>` cannot access any part of the network from outside the network.
- VMs in the SHM are only accessible by {ref}`System Managers <role_system_manager>` using the management VPN.
- Whilst in the network, one cannot use the internet to connect outside the network (for {ref}`policy_tier_2` and {ref}`policy_tier_3`).
- SREs in the same SHM are isolated from one another.

### Implication:

- SREs at {ref}`policy_tier_2` and {ref}`policy_tier_3` are isolated from external connections.

## 3. User devices

### Turing configuration setting:

- Managed devices must be provided by an approved organisation and the user must not have administrator access to them.
- Network rules for higher tier environments permit access only from IP ranges corresponding to **Restricted** networks that only permit managed devices to connect.

### Implication:

- At {ref}`policy_tier_3`, only Turing managed devices can connect to the Data Safe Haven environment.
- At {ref}`policy_tier_2`, only user devices authenticated against the Turing VPN can connect to the Data Safe Haven environment.

## 4. Physical security

### Turing configuration setting:

- Medium security research spaces control the possibility of unauthorised viewing.
- Card access or other means of restricting entry to only known researchers (such as the signing in of guests on a known list) is required.
- Screen adaptations or desk partitions should be adopted in open-plan spaces if there is a high risk of unauthorised people viewing the user's screen.
- Firewall rules for the SREs only permit access from **Restricted** network IP ranges corresponding to these research spaces.

### Implication:

- At {ref}`policy_tier_3` access is limited to certain secure physical spaces.

## 5. Remote connections

### Turing configuration setting:

- Connections can only be made through the remote desktop gateway, other means such as `SSH` are forbidden.
- The gateway URL is only accessible from approved IP addresses.

### Implication:

- Users can only connect through a browser from an approved IP address.

## 6. Copy-and-paste

### Turing configuration setting:

- Users cannot copy something from outside the network and paste it into the network ({ref}`policy_tier_2` and {ref}`policy_tier_3`).
- Users cannot copy something from within the network and paste it outside the network ({ref}`policy_tier_2` and {ref}`policy_tier_3`).

### Implication:

- Copy and paste is disabled on the remote desktop for {ref}`policy_tier_2` and {ref}`policy_tier_3`.

## 7. Data ingress

### Turing configuration setting:

- Prior to access to the ingress volume being provided, the {ref}`role_data_provider_representative` must provide the IP address(es) from which data will be uploaded and an email address to which a secure upload token can be sent.
- Once these details have been received, the data ingress volume should be opened for data upload.

To minimise the risk of unauthorised access to the dataset while the ingress volume is open for uploads, the following security measures are in place:

- Access to the ingress volume is restricted to a limited range of IP addresses associated with the **Dataset Provider** and the **host organisation**.
- The {ref}`role_data_provider_representative` receives a write-only upload token.
    - This allows them to upload, verify and modify the uploaded data, but does not viewing or download of the data.
    - This provides protection against an unauthorised party accessing the data, even if they gain access to the upload token.
- The upload token expires after a time-limited upload window.
- The upload token is transferred to the Dataset Provider via a secure email system.

### Implication:

- All data transfer to the Data Safe Haven will be carried out via a secure data transfer process, which gives the {ref}`role_data_provider_representative` time-limited, write-only access to a dedicated data ingress volume from a specific location.
- Data is stored securely until approved for user access.

## 8. Data egress

### Turing configuration setting::

- Users can write to the `/mnt/output` volume.
- A {ref}`role_system_manager` can view and download data in the `/mnt/output` volume via **Azure Storage Explorer**.

### Implication:

- SRE users can mark data as ready for egress approval by placing it in the `/mnt/output` volume.

## 9. Software ingress

### Turing configuration setting:

- For {ref}`policy_tier_0` and {ref}`policy_tier_1` environments, outbound internet access means users can directly download their software from the internet.
- For {ref}`policy_tier_2` or higher environments we use a secure data transfer process.

- Installation during deployment
    - If known in advance, software can be installed during SRD deployment whilst there is still internet access, but before project data is added. Once the software is installed, the SRD undergoes ingress into the environment with a one way lock.
- Installation after deployment
    - Once an SRD has been deployed into the analysis environment it cannot be moved out. There is no outbound internet access.
    - Software is added via ingress in a similar manner to data:
        - Researchers are provided temporary write-only access to the software ingress volume.
        - The access is then revoked and the software is then reviewed.
        - If it passes review, the software is moved into the environment.
    - If the software requires administrator rights to install, a {ref}`role_system_manager` must do this. Otherwise, the researcher can do this themselves.

### Implication:

- The base SRD provided in the SREs comes with a wide range of common data science software pre-installed, as well as package mirrors.
- Additional software must be added separately via ingress.

## 10. Software package repositories

### Turing configuration setting:

- {ref}`policy_tier_2`: The user can access any package via our repositories. They can freely use these packages without restriction.
- {ref}`policy_tier_3`: The user can only access a specific pre-agreed set of packages. They will be unable to download any package not on the allowed list.

### Implication:

- {ref}`policy_tier_2`: User can access all packages from PyPI/CRAN.
- {ref}`policy_tier_3`: User can only access approved packages from PyPI/CRAN. Allowed list is in `environment_configs/package_lists`.

## 11. Firewall controls

### Turing configuration setting:

- An **Azure Firewall** ensures that all VMs within the safe haven have the minimal level of internet access required to function.

### Implication:

- Research accessible SRD VMs can only access a limited set of domains required for managing software and virus definition updates.
- Administrator accessible VMs can access additional domains required to perform their functionality (e.g. user authentication, providing SRD VMs access to authorised packages)
