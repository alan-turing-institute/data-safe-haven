(design_architecture)=

# Architecture

```{toctree}
:hidden: true
:maxdepth: 2

shm_details.md
sre_details.md
```

The Data Safe Haven is designed to be deployed on the [Microsoft Azure](https://azure.microsoft.com/en-gb/) platform taking advantage of its cloud-computing infrastructure.

Each deployment of the Data Safe Haven consists of two components:

- one **Safe Haven Management** (SHM) component
- one or more **Secure Research Environments** (SREs).

```{image} safe_haven_architecture.png
:alt: High-level architecture
:align: center
```

The SHM controls the authentication process for the infrastructure.
The identity provider is Microsoft Active Directory, which is synchronised with AzureAD to provide cloud and multifactor authentication into the individual project Secure Research Environment (SRE).

The SHM is connected to each SRE through virtual network peering, which allows authentication requests from the SRE servers to be resolved by the SHM Active Directory.
Although all SREs are peered with the SHM, they are not able to connect directly to one another, ensuring the isolation of each project.

[Safe Haven Management (SHM)](shm_details.md)
: details about the design of the SHM component

[Secure Research Environment (SRE)](sre_details.md)
: details about the design of the SRE component
