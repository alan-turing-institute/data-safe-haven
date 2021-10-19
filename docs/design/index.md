# Design

## Introduction

The Safe Haven is designed to be deployed on the [Microsoft Azure](https://azure.microsoft.com/en-gb/) platform taking advantage of its cloud-computing infrastructure.
This document describes the architecture of the Safe Haven and the security measures in place to protect the sensitive data handled within it.

Each deployment of the Safe Haven contains two major components: one Safe Haven Management (SHM) component together with one or more Secure Research Environments (SREs).

## High-level architecture

The Management segment hosts the authentication providers for the infrastructure.
The identity provider is Microsoft Active Directory, which is synchronised with AzureAD to provide cloud and multifactor authentication into the individual project Secure Research Environment (SRE).

```{image} safe_haven_architecture.png
:alt: High-level architecture
:align: center
```

The Management segment is connected to the SREs using Azure Virtual Network Peering. This connection passes authentication traffic between the servers in the SRE to AD servers within the Management subscription. While all SREs are peered with the Management segment, there is no connectivity between SREs directly.

### Safe Haven Management component (SHM)

More details about the SHM design [can be found here](implementation/shm_details.md)

### Secure Research Environment component (SRE)

More details about the SRE design [can be found here](implementation/sre_details.md)

## Security

### Default security configuration

- Authentication
  - Researchers access the SRE by connecting via SSL/TLS to the Remote Desktop Gateway
  - After authenticating with username/password and multi-factor authentication (phonecall or phone app notification) they use an HTML5 web application to access SRE resources
- Connection
  - Access to the gateway is only permitted from the IP addresses associated with specific networks at the Turing or its partner institutes.
  - For tier 2, we recommend permitting access only from institutionally managed networks, which might also be accessible by non-Researchers.
  - For tier 3, we recommend permitting access only from restricted networks, which are accessible only by a known subset of Researchers and, optionally, only available in certain physical locations.
- Accounts
  - Researchers must log into the RDS Gateway using a dedicated Safe Haven user account, created in the Safe Haven Management segment and separate from any credentials used to access other services.
  - Only Researchers assigned to the security group associated with a specific project in the Management segment can log into the SRE for that project.
- Data transfer
  - For tier 2 and above, the copying of information into or out of any of the resources in the SRE is prevented by the gateway configuration.
- Internet access
  - For tier 2 and above, access to the internet from within the SRE is blocked by network-level rules.
- Custom software
  - Researchers are not provided with any administrative rights that would allow them to install their own software
  - Researchers **are** allowed to install Python and/or R packages into their userspace from the PyPI and CRAN package servers.
  - For tier 2, a proxy server is used to access all packages in the official PyPI and CRAN servers.
  - For tier 3, a local mirror provides access to an SRE-specific allowlist of packages

### Design decisions

Two assumptions about the research user community are critical to our design:

- Firstly, we must consider not only accidental breach and deliberate attack, but also the possibility of "workaround breach", where well-intentioned researchers, in an apparent attempt to make their scholarly processes easier, circumvent security measures, for example, by copying out datasets to their personal device. Our user community are relatively technically able; the casual use of technical circumvention measures, not by adversaries but by colleagues, must be considered. This can be mitigated by increasing awareness and placing inconvenience barriers in the way of undesired behaviours, even if those barriers are in principle not too hard to circumvent.
- Secondly, research institutions need to be open about the research we carry out, and hence, the datasets we hold. This is because of both the need to publish our research as part of our impact cases to funders, and because of the need to maintain the trust of society, which provides our social licence. This means we cannot rely on "security through obscurity": we must make our security decisions assuming that adversaries know what we have, what we are doing with it, and how we secure it.

We detail various design decisions that impact the security of our Safe Haven implementation.
This includes reasoning for our different choices but also highlights potential limitations for our Safe Havens and how this may affect things like cyber security.

- [Data access](security_decisions/data_access.md) - Documentation on how access to sensitive data is controlled in the Safe Haven.
- [Physical resilience](security_decisions/physical_resilence_and_availability.md) - Documentation on the physical resilience of the Safe Haven and our design decisions involved.

### Security assessments

We have run a [self-assessment](certifications/DSPT.md) against the [NHS DSPT](https://www.dsptoolkit.nhs.uk/) criteria.
We have also developed a [risk register](certifications/risk_register.md) of the most likely risks involved in running a Safe Haven.

