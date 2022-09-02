(design_security_controls)=

# Technical controls

## Multifactor Authentication and Password strength

Once a user account is created by a {ref}`role_system_manager`, the user must then activate their account online.
They choose their own password, which must meet password strength requirements, and set up multi-factor authentication.

## Isolated network

Our network security model distinguishes three levels of access networks for user devices.

- A `Restricted` network
- An `Institutional` network
- An `Unrestricted` network (e.g. the open internet or any other non-`Restricted` or non-`Institutional` network)

(design_restricted_network)=

### Restricted network

A `Restricted` network corresponds to a network managed by a trusted institution that can support additional controls such as restricting access to a narrower set of users, devices or locations.
Access to SREs can be restricted such that access is only allowed by devices which are connected to a particular set of `Restricted` networks.
Access to a particular SRE may be permitted from multiple `Restricted` networks at multiple trusted organisations.
This can permit users from multiple organisations to access an SRE, as well permitting users to access the SRE while away from their home institution at another trusted institution.
However, remote access to a `Restricted` network (for example via VPN) is not permitted.

(design_institutional_network)=

### Institutional network

An `Institutional` network corresponds to a network managed by a trusted institution.
Guest access may be permitted on such networks (e.g. eduroam), but these guests should be known users.
Access to SREs can be restricted such that access is only allowed by devices which are connected to a particular set of `Institutional` networks.
However, it is assumed that a wide segment of the research community can access these networks.
This access may also be remote for authorised users (for example, via VPN).

At tier 2 or above SRE firewall rules permit inbound access only from network IP ranges corresponding to specific pre-approved `Institutional` and `Restricted` networks.
Similarly, at tier 2 or above, connections to resources outside the SRE private network (such as external websites) are not permitted.
Finally, different SREs within the same Data Safe Haven are isolated from one another at the network level.

## User Devices

We define two types of devices that {ref}`Researchers <role_researcher>` might use to connect to an SRE

- Managed devices
- Open devices

(design_managed_devices)=

### Managed devices

Managed devices are devices provided by a institution on which the user does not have administrator/root access, with the device instead administered by the institution's IT team.
They have an extensive suite of research software installed.
This includes the ability to install packages for standard programming environments without the need for administrator access.
{ref}`Researchers <role_researcher>` can compile and run their own executables in user space (the portion of system memory in which user processes run).

(design_open_devices)=

### Open devices

Open devices include personal devices such as researcher-owned laptops, but also include devices provided by an institution where the user has administrator/root access.
These devices permit the easy use of a wider range of software than managed devices, as well as easier access to peripheral hardware.
Firewall rules for the higher tier SREs should permit access only from Restricted network IP ranges that only managed devices are able to connect to.

For tier 2 and below, any device is allowed to connect to the SRE.
For tier 3 and above, only managed devices are permitted to connect.

## Physical security

Some data requires a physical security layer around not just the data centre,
but the physical space users are in when they connect to it.

We distinguish three levels of physical security for research spaces:

- Open research spaces
- Medium security research spaces
- High security research spaces

Open research spaces include university libraries, cafes and common rooms.

Medium security research spaces control the possibility of unauthorised viewing.
Card access or other means of restricting entry to only known researchers (such as the signing in of guests on a known list) is required.
Screen adaptations or desk partitions can be adopted in open-plan spaces if there is a high risk of "visual eavesdropping".

Secure research spaces control the possibility of the researcher deliberately removing data.
Devices will be locked to appropriate desks, and neither enter nor leave the space.
Mobile devices should be removed before entering, to block the 'photographic hole', where mobile phones are used to capture secure data from a screen.
Only {ref}`Researchers <role_researcher>` associated with a secure project have access to such a space.

For tier 3 and higher, we recommend limiting access to medium or high security research spaces.
This can be enforced by requiring access from Restricted network IP ranges that are only accessible inside such spaces.

## Remote connections

Inbound connections are only permitted via the remote desktop gateway.
This allows Researchers access to a Linux desktop with graphical interface applications running in the remote SRE.

## Copy-and-paste

At tier 2 and higher, the use of copy-and-paste is blocked by the remote desktop gateway.

```{attention}
Users cannot be absolutely prevented from copying data to the device they are using to access the SRE, since malicious users can script automated screen-grabs.
The aim of this control is to deter non-malicious workaround breach where Researchers misunderstand or misinterpret what is permitted.
```

## Data ingress

Data should be transferred securely to the dedicated `ingress` blob storage space for the appropriate SRE.
We recommend doing this using time-limited, write-only SAS tokens which should be sent to the {ref}`role_data_provider_representative` over a secure channel.
Access to the blob storage space should be locked down to only permit connections from known IP addresses that the {ref}`role_data_provider_representative` will be using.

This data is then exposed to users in the SRE as a secure data volume.
This is an Azure storage container which is mounted as read-only in the SRE that needs access to it.
One or more such volumes might be mounted depending on how many managed secure datasets the SRE has access to.

## Data egress

Any data or code that is a desired output of the SRE should be placed in the output volume.
This is an Azure storage container which is mounted as read-write in the SRE that needs access to it.

The {ref}`role_data_provider_representative`, {ref}`role_investigator` and {ref}`role_referee` (if applicable) should review the contents of this volume before deciding how and whether to bring them out of the SRE.
This can be done using the reverse of the data ingress process, with a time-limited, read-only SAS token.

## Software ingress

The analysis machines provided in the SRE come with a wide range of common data science software pre-installed.
Additionally, the on-demand installation of software packages from certain package repositories (such as PyPI for Python or CRAN for R) is also supported.

For lower tiers, with access to the internet, required software packages can be installed directly from their canonical sources on the internet.
For higher tiers, without access to the external internet, full or partial copies of specific package repositories are maintained in the Safe Haven.
For tier 2, a proxy server is maintained which allows access to any package from the supported repositories.
For tier 3 or higher, an allowlist of packages which are explicitly marked as safe is maintained for each SRE - a mirror server is made available which only contains these packages.

```{attention}
Installation of any packages which require administrative rights must be done by a {ref}`role_system_manager`
```

## Azure Firewalls

While user-facing machines can be completely isolated from the internet, there are several machines that form part of the supporting infrastructure which need wider internet access.
Although these can only be accessed by {ref}`System Managers <role_system_manager>` they are nevertheless restricted by firewall rules which limit them to only essential connections such as to update servers.
