# Data access

## Admistrative access

Access to all Data Safe Haven Azure resources is controlled via ` Azure Active Directory`` (Azure AD) and Role-Based Access Control (RBAC). Only members of the  `Safe Haven Administrators` security group have administrative access to any element of the Safe Haven.

```{important}
Membership of this security group should be limited to {ref}`system deployers <role_system_deployer>` and {ref}`system managers <role_system_manager>`.
```

The following access is restricted to members of the `Safe Haven Administrators` security group:

### Administrative access to the underlying Azure resources

These comprise the software defined infrastructure of the Data Safe Haven, such as:

- subscriptions
- virtual networks
- network security groups
- virtual machines
- `Azure Active Directory`

Access to the underlying Azure resources requires administrators to log into Azure

```{hint}
We strongly recommend using institutional credentials that are separate from the Data Safe Haven `Azure Active Directory` together with multifactor authentication.
```

### Administrative access to the Safe Haven Management (SHM) segment.

Used primarily to manage users and security groups within the Safe Haven, as well as to troubleshoot any authentication issues.
Access is via an `Azure` point-to-site (P2S) VPN service, and requires both a client certificate and administrative login credentials.

### Administrative access to all project SREs.

Used to troubleshoot any issues and ingress data and code following review.
Access is via an `Azure` point-to-site (P2S) VPN service, and requires both a client certificate and administrative login credentials.

## Researcher access

Each SRE has its own security group in the SHM `Active Directory`.
User accounts are created in the SHM `Active Directory` and added to security groups as appropriate.
Access to individual project SREs is restricted to {ref}`Researchers <role_researcher>` who have been added to the associated security group.
This provides a central user management experience for the support staff and permits {ref}`Researchers <role_researcher>` to more easily work on multiple projects hosted within the Data Safe Haven.

Access to the remote desktop requires all of:

- connection from an IP address belonging to a known allowed range
- a valid username and password
- membership of the correct `Active Directory` security group
- successful multifactor authentication
