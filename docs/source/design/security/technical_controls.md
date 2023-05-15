# Built-in technical controls

Each secure research environment (SRE) belongs to one of five {ref}`project sensitivity tiers <policy_classification_sensitivity_tiers>`.
Depending on which tier a particular SRE belongs to, the following technical security controls are applied by default.
Most of these controls can be relaxed or tightened by the {ref}`role_system_manager` if a particular SRE requires it.

## Applicable to all SREs

### Accounts

- Researchers must use a dedicated Data Safe Haven account to log in.
- These accounts are created by a {ref}`role_system_manager` and are separate from any credentials used to access other services.
- Access to any particular SRE is further controlled through membership of a security group associated with that project.
- Only {ref}`System Managers <role_system_manager>` are able to assign users to groups.

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
- {ref}`Researchers <role_researcher>` **are** allowed to install libraries into their userspace, for example packages from the `PyPI` or `CRAN` package repositories may be permitted.

### Data access

- Data is stored in Azure storage which only {ref}`System Managers <role_system_manager>` can access from outside the environment
- {ref}`Researchers <role_researcher>` have read-only access to the data and only from inside the environment.

### Infrastructure access

- {ref}`System Managers <role_system_manager>` are the only people able to make changes to infrastructure

## Tier-specific

```{caution}
{ref}`policy_tier_4` defaults are not discussed below as such environments are not currently supported by the Data Safe Haven.
```

```{important}
While {ref}`policy_tier_0` and {ref}`policy_tier_1` are discussed below, at the Alan Turing Institute we do not generally use our Data Safe Haven for {ref}`policy_tier_0` or {ref}`policy_tier_1` environments.
While SREs can be configured as {ref}`policy_tier_0` or {ref}`policy_tier_1`, we generally favour supporting researchers to apply sensible controls on organisational devices and standard cloud resources for such lower sensitivity projects.
```

### Inbound connections

Access to the gateway is only permitted from defined IP addresses associated with specific networks at the host organisation or its partner institutes:

- **{ref}`policy_tier_3`:** Access is restricted to a defined set of IP addresses. At the Alan Turing Institute, we permit access only from a restricted set of networks, which are accessible only by a known subset of {ref}`Researchers <role_researcher>`.
- **{ref}`policy_tier_2`:** Access is restricted to a defined set of IP addresses. At the Alan Turing Institute we permit access only from institutionally managed networks, which will generally be accessible to {ref}`Researchers <role_researcher>` not authorised to access the Data Safe Haven and might also be accessible to non-Researchers.
- **{ref}`policy_tier_0` and {ref}`policy_tier_1`:** Access is permitted from any IP address by default. At the Alan Turing Institute we do not generally use our Data Safe Haven for {ref}`policy_tier_0` or {ref}`policy_tier_1`. Organisations choosing to do so may wish to consider only allowing inbound internet access from a specific range of networks {ref}`Researchers <role_researcher>` are known to work from.

```{caution}
Having no restrictions on which IP addresses can connect to the gateway increases the risk of external attacks, many of which may be untargeted but might still result in a degradation of service.
```

### Outbound connections

- **{ref}`policy_tier_2` and {ref}`policy_tier_3`:** Outbound internet access from the SRE is blocked by network-level rules.
- **{ref}`policy_tier_0` and {ref}`policy_tier_1`:** Outbound internet access from the SRE is permitted.

### User devices:

- **{ref}`policy_tier_3`:** At the Alan Turing Institute we only permit {ref}`Researchers <role_researcher>` to connect to {ref}`policy_tier_3` environments from a device managed by the Alan Turing Institute or a partner organisation. {ref}`Researchers <role_researcher>` must not have administrator access on such devices, the devices must have anti virus software installed, and software on the devices must be regularly updated. At the Alan Turing Institute we have a restricted network that only permits access from Turing managed devices. When permitting access to {ref}`policy_tier_3` environments from partner networks we require that they can similarly restrict access to devices they manage.
- **{ref}`policy_tier_0` to {ref}`policy_tier_2`:** {ref}`Researchers <role_researcher>` can connect from their own devices.

### Physical security:

- **{ref}`policy_tier_3`:** {ref}`Researchers <role_researcher>` must only connect from dedicated medium security spaces with access restricted via card access or other means and the risk of unauthorised people viewing the user's screen must be controlled (e.g. by device location, screen adaptation or desk partitions). At the Alan Turing Institute access is limited to such areas by policy. A {ref}`Researcher's <role_researcher>` home or non-Turing office may be considered a medium security space if sufficient care is taken to avoid unauthorised people, such as family or colleagues, viewing the user's screen.
- **{ref}`policy_tier_0` to {ref}`policy_tier_2`:** {ref}`Researchers <role_researcher>` can connect from anywhere.

### Data transfer from user device

- **{ref}`policy_tier_2` and {ref}`policy_tier_3`:** Copy-and-paste and file transfer between the SRE and the {ref}`Researcher's <role_researcher>` device are disabled.
- **{ref}`policy_tier_0` and {ref}`policy_tier_1`:** Copy and paste is enabled between the SRE and the {ref}`Researcher's <role_researcher>` device is enabled but file transfer is not possible for non administrators.

```{note}
Note that this means that eg. password managers cannot be used to autofill a {ref}`Researcher's <role_researcher>` SRE login credentials.
```

### Sign-off on bringing data into the environment:

- **{ref}`policy_tier_2` and {ref}`policy_tier_3`:** At the Alan Turing Institute all three of {ref}`role_investigator`, {ref}`role_data_provider_representative` and {ref}`role_referee` must agree the data is suitable for the environment Tier.
- **{ref}`policy_tier_0` and {ref}`policy_tier_1`:** At the Alan Turing Institute both {ref}`role_investigator` and {ref}`role_data_provider_representative` must agree the data is suitable for the environment Tier.

### Sign-off on bringing data out of the environment:

- **{ref}`policy_tier_2` and {ref}`policy_tier_3`:** At the Alan Turing Institute all three of {ref}`role_investigator`, {ref}`role_data_provider_representative` and {ref}`role_referee` must agree the data is suitable for its destination before it is egressed from an SRE.
- **{ref}`policy_tier_0` and {ref}`policy_tier_1`:** At the Alan Turing Institute both {ref}`role_investigator` and {ref}`role_data_provider_representative` must agree the data is suitable for its destination before it is egressed from an SRE.

### Sign-off on adding new users:

- **{ref}`policy_tier_3`:** At the Alan Turing Institute the {ref}`role_investigator` and {ref}`role_referee` must both authorise access to an SRE at {ref}`policy_tier_3`.
- **{ref}`policy_tier_0` to {ref}`policy_tier_2`:** At the Alan Turing Institute the {ref}`role_investigator` can authorise access to an SRE at {ref}`policy_tier_0` to {ref}`policy_tier_2`.

### Sign-off on bringing external code/software into the environment:

- **{ref}`policy_tier_3`:** At the Alan Turing Institute both the {ref}`role_investigator` and {ref}`role_referee` must authorise the ingress of code or software to an SRE at {ref}`policy_tier_3`.
- **{ref}`policy_tier_0` to {ref}`policy_tier_2`:** At the Alan Turing Institute the {ref}`role_investigator` can authorise ingress of code or software to an SRE at {ref}`policy_tier_0` to {ref}`policy_tier_2`.

### Python/R package availability:

- **{ref}`policy_tier_3`:** A pre-agreed allowlist of packages from `CRAN` and `PyPI` (via proxy or local mirror).
- **{ref}`policy_tier_2`:** Anything on `CRAN` or `PyPI` (via proxy or local mirror).
- **{ref}`policy_tier_0` and {ref}`policy_tier_1`:** Direct access to any package repository.
