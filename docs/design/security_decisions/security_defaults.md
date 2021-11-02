# Default security configuration

Each secure research environment (SRE) belongs to one of five {ref}`project sensitivity tiers <policy_classification_sensitivity_tiers>`.
Depending on which tier a particular SRE belongs to, the following security controls are applied by default.
Any of these controls can be relaxed or tightened by the {ref}`role_system_manager` if a particular SRE requires it.

## Applicable to all SREs

### Accounts

- Researchers must use a dedicated Data Safe Haven account to log in.
- These accounts are created by a {ref}`role_system_manager` and are separate from any credentials used to access other services.
- Access to any particular SRE is further controlled through membership of a security group associated with that project.
  Only {ref}`System Managers <role_system_manager>` are able to assign users to groups.

### Authentication

- {ref}`Researchers <role_researcher>` access the SRE by connecting via SSL/TLS to the Remote Desktop Gateway.
- Authentication to the Remote Desktop Gateway requires all of:
  - username
  - password
  - multi-factor authentication (phonecall or phone app notification)

### Remote connections:

- Authenticated {ref}`Researchers <role_researcher>` must use an HTML5 web application running on the Remote Desktop Gateway to connect the SRE.
- SRE resources are available through an in-browser desktop.

### Custom software

- {ref}`Researchers <role_researcher>` are not provided with any administrative rights that would allow them to install their own software.
- {ref}`Researchers <role_researcher>` **are** allowed to install libraries into their userspace, for example packages from the `PyPI` or `CRAN` package repositories.

### Data access

- Data is stored in Azure cloud storage which only {ref}`System Managers <role_system_manager>` can access from outside the environment
- {ref}`Researchers <role_researcher>` have read-only access to the data and only from inside the environment.

### Infrastructure access

- {ref}`System Managers <role_system_manager>` are the only people able to make changes to infrastructure

## Tier-specific

```{important}
Tier 4 defaults are not discussed below as such environments are not currently supported by the Data Safe Haven.
```

### Inbound connections

Access to the gateway is only permitted from defined IP addresses associated with specific networks at the host organisation or its partner institutes:
- **Tier 3:** we recommend permitting access only from restricted networks, which are accessible only by a known subset of {ref}`Researchers <role_researcher>`.
- **Tier 2:** we recommend permitting access only from institutionally managed networks, such as EduRoam, which might also be accessible by non-Researchers.
- **Tier 0/1:** we recommend restricting access to IP addresses provided by researchers, but without restrictions about what these should correspond to.

```{caution}
Unrestricting which IP addresses can connect to the gateway increases the risk of DDOS attacks.
```

### Outbound connections

- **Tier 2/3:** outbound internet access from the SRE is blocked by network-level rules.
- **Tier 0/1:** outbound internet access from the SRE is permitted.

### User devices:

- **Tier 3:** {ref}`Researchers <role_researcher>` must connect from a managed device where they have no admin access (eg. a host-provided Chromebook).
- **Tier 0/1/2:** {ref}`Researchers <role_researcher>` can connect from their own devices.

### Physical security:

- **Tier 3:** {ref}`Researchers <role_researcher>` must only connect from dedicated secure spaces (eg. from a known office at the host institute) [NB. This may be relaxed depending on COVID restrictions]
- **Tier 0/1/2:** {ref}`Researchers <role_researcher>` can connect from anywhere


### Data transfer from user device

- **Tier 2/3:** Disabled between the user device and the remote secure environment. Copy-and-paste is also disabled.
- **Tier 0/1:** Copy and paste is enabled, but file transfer is not possible without using a web-based file transfer service.

```{note}
Note that this means that eg. password managers cannot be used]
```

### Sign-off on bringing data into the environment:

- **Tier 2/3:** {ref}`role_investigator`, {ref}`role_data_provider_representative` and {ref}`role_referee`.
- **Tier 0/1:** {ref}`role_investigator` and `role_data_provider_representative`.

### Sign-off on adding new users:

- **Tier 3:** {ref}`role_investigator` and {ref}`role_referee`
- **Tier 0/1/2:** {ref}`role_investigator`

### Sign-off on bringing external code/software into the environment:

- **Tier 3:** {ref}`role_investigator` and {ref}`role_referee`
- **Tier 0/1/2:** {ref}`role_investigator`


### Python/R package availability:

- **Tier 3:** A pre-agreed allowlist of packages from `CRAN` and `PyPI` (via local mirror).
- **Tier 2:** Anything on `CRAN` or `PyPI` (via proxy or local mirror).
- **Tier 0/1:** Direct access to any package repository.
