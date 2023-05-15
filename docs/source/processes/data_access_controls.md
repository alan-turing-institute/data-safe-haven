# Data access controls

In this section we describe how access to the Data Safe Haven is controlled at the Turing.
Much of the access control is provided by the technical controls configured when deploying a Data Safe Haven following our deployment guide.
However, some manual configuration steps are required and each organisation is responsible for verifying that the Data Safe Haven is deployed as expected and that the deployed configuration effectively supports their own information governance policies and processes.

## Administrative access

Access to all Data Safe Haven Azure resources is controlled via `Azure Active Directory` (Azure AD) and Role-Based Access Control (RBAC).
By default, only members of a specific administrator security group have administrative access to any element of the Safe Haven.

```{important}
Membership of the administrator security group should be limited to {ref}`System Managers <role_system_manager>`.
```

The following access is restricted to members of the administrator security group:

### Administrative access to the underlying Azure resources

These comprise the software defined infrastructure of the Data Safe Haven, such as:

- subscriptions
- virtual networks
- network security groups
- virtual machines
- `Azure Active Directory`

Access to the underlying Azure resources requires administrators to log into Azure.

```{hint}
Data Safe Haven administrator accounts should be separate from accounts used for any other purpose, including accessing the Data Safe Haven in any other role (e.g. as a {ref}`Researcher <role_researcher>`).
At the Turing, Data Safe Haven administrator accounts are configured on a separate institutional `Azure Active Directory` to the Data Safe Haven `Azure Active Directory`.
Other organisations may wish to follow the same model.
```

### Administrative access to the Data Safe Haven

Administrators can access VMs within the Data Safe Haven via an `Azure` point-to-site (P2S) VPN service, which requires both a client certificate and administrative login credentials.
This VPN is used to manage users and security groups and troubleshoot any issues with the SHM or SRE VMs.

At the Turing, administrators ingress and egress data and code by connecting directly to the Azure storage for an SRE using `Azure Storage Explorer` over a restricted connection.
Connections are only permitted from Turing managed devices via the Turing's restricted network. Administrators must authenticate using both their administrator credentials and multifactor authentication.

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
