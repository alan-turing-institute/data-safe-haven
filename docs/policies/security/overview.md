# Security overview

A brief overview of our default controls at each tier.

```{note}
All of the choices described below are configurable on an environment-by-environment basis.
```

## Software installation

- **Tier 3+:** package mirrors (copies of external repositories inside the secure Environment) should only include explicitly allowed software packages.
- **Tier 2:**, package mirrors should include all software packages.
- **Tier 2+:** all software not available from a package mirror must be installed either at the time the analysis machine is first deployed or by ingressing the software installer as data, with an associated ingress review.
- **Tier 0/1:** all software installation should be from the internet.

## Inbound connections

- **Tier 2:** analysis machines and other Environment resources are not accessible directly from client devices. Secure web-based remote desktop facilities are used to indirectly access the analysis Environments.
- **Tier 0/1:** analysis machines and other Environment resources are directly accessible from client devices.
- **Tier 3+:** Environment access nodes are only available from approved Restricted networks.
- **Tier 2:** Environment access nodes are only be accessible from approved Institutional networks.
- **Tier 0/1:** Environment resources are accessible from the open internet

## Outbound connections

- **Tier 2+:** no connections are permitted from the Environment private network to the internet or other external resources.
- **Tier 0/1:** the internet is accessible from inside the Environment.

## Data ingress

- **Tier 2+:** the high-security data transfer process is required (i.e. write only access from particular locations for a limited time).
- **Tier 0/1:** the use of standard secure data transfer processes (e.g. SCP/SFTP) may be permitted.

## Data egress

- **Tier 3+:** the Data Provider Representative, Investigator and Referee are all required to sign off all egress of data or code from the Environment.
- **Tier 2:** only the Investigator and Referee are required to review and approve all egress of data or code from the Environment.
- **Tier 0/1:** users are permitted to copy out data when they believe their local device is secure, with the permission of the Investigator.

