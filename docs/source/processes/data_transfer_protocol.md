# Data transfer at the Turing

The Turing operates the following data transfer protocol for {ref}`policy_tier_2` and {ref}`policy_tier_3` Secure Research Environments within its Data Safe Haven instance.

```{caution}
The Turing does not yet operate any {ref}`policy_tier_4` environments and has not evaluated whether this process would be suitable for such environments.
```

```{important}
The Turing does not generally use its Data Safe Haven for {ref}`policy_tier_0` and {ref}`policy_tier_1` projects.
When it does do so, it operates the same protocol except that the {ref}`role_investigator` for a project may make the sole determination that the {ref}`Sensitivity Tier <policy_classification_sensitivity_tiers>` for the **combination** of the data to be ingressed
```

This protocol limits the following aspects of the transfer to provide the minimum necessary exposure:

- The time window during which dataset can be transferred
- The networks from which it can be transferred
- The people and devices who are able to initiate data transfer

For data ingress the following protocol is followed:

- A separate Azure storage account is created for each project which is only accessible by {ref}`System Managers <role_system_manager>`.
- Each Data Provider has an independent storage container within this account
- The {ref}`role_data_provider_representative`, {ref}`role_investigator` and {ref}`role_referee` agree that the {ref}`Sensitivity Tier <policy_classification_sensitivity_tiers>` for the **combination** of the data to be ingressed **and** the data already present within the environment is appropriate for the {ref}`Sensitivity Tier <policy_classification_sensitivity_tiers>` of the environment.
- A set of IP addresses is communicated to the {ref}`role_system_manager` by the {ref}`role_data_provider_representative`.
- The {ref}`role_system_manager` grants access permission to this IP address range while excluding other connections.
- The {ref}`role_system_manager` generates a time-limited Shared Access Signature (SAS) token with write, list and append permissions for the relevant storage container.
- The {ref}`role_system_manager` sends the SAS token to the {ref}`role_data_provider_representative` over a secure channel.
- The {ref}`role_data_provider_representative` uses the SAS token to upload their data.

```{important}
Excluding **read** and **download** permissions from the SAS token provides an added layer of protection against loss or interception of the token.
```

```{important}
Limiting the validity of the SAS token minimises the chance of malicious actors at the Data Provider poisoning the data upload.
```
