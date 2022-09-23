(design_sre)=

# Secure research environment design

Each project within the Safe Haven has its own separate Secure Research Environment (SRE).
Each of these SREs is completely isolated from the others and the security configuration of each SRE is set independently to match the needs of the project and Data Provider(s).
Each SRE is assigned to a security tier, depending on the sensitivity of the dataset(s) it will hold and the nature of the analysis to be performed within it.
Each tier is associated with a baseline security configuration, individual elements of which can be adjusted to meet the needs of the project and the Data Provider(s).

The infrastructure for each SRE is hosted in a separate Azure resource group.
This infrastructure comprises:

- One or more Secure Research Desktops (SRDs) with a range of data science software preinstalled
- A file server to host the project data
- A `Gitlab` server to provide source code management and version control
- A `CodiMD` server for collaborative writing
- A `CoCalc` server for collaborative editing of computational notebook
- A remote desktop server to provide secure remote desktop access to the SRE resources. This can be configured on a per-SRE basis as either `Apache Guacamole` or `Microsoft Remote Desktop Services`.

Hosting each secure project environment in its own resource group supports a clean lifecycle management process, making it easy to verifiably delete all project data and resources at the end of a project.

## Architecture

```{image} sre_architecture.png
:alt: Secure Research Environment (SRE) component
:align: center
```

The SREs use either `Microsoft Remote Desktop Services` or `Apache Guacamole` to provide a secure connection to the resources within the environment.
Only the remote desktop server is accessible from outside the SRE.
Connections to this are made via an SSL/TLS secured connection that requires the user to authenticate using credentials provided by the Data Safe Haven and validated with MFA.

For {ref}`policy_tier_2` environments and above, outbound internet access from within the SRE is blocked. Access to the SRE remote desktop is only permitted from approved networks, and the remote desktop server prevents the copying of information into or out of the SRE.

For management of the environment there is an Azure point-to-site (P2S) VPN service configured via the [Safe Haven Management (SHM)](shm_details.md) segment of the Data Safe Haven.
Access to this is limited to the Data Safe Haven administration team.
