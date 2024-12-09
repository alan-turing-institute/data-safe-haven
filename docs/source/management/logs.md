# Monitoring logs

Logs are collected for numerous parts of a Data Safe Haven.
Some of these logs are ingested into a central location, an Azure [Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-workspace-overview), and others are stored separately.

## Log workspace

Each SRE has its own Log Analytics Workspace.
You can view the workspaces by going to the Azure portal and navigating to [Log Analytics Workspaces](https://portal.azure.com/#browse/Microsoft.OperationalInsights%2Fworkspaces).
Select which Log Analytics Workspace you want to view by clicking on the workspace named `shm-<YOUR_SHM_NAME>-sre-<YOUR_SRE_NAME>-log`.

The logs can be filtered using [Kusto Query Language (KQL)](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-query-overview).

## Storage logs

Depending on how different parts of Data Safe Haven storage are provisioned, logs may differ.

### Sensitive data logs

The sensitive data containers are the [ingress and egress containers](./data.md).
Logs from these containers are ingested into the [SRE's log analytics workspace](#log-workspace).
There are two tables,

`StorageBlobLogs`
: Events occurring on the blob containers.
: For example data being uploaded, extracted or read.

`AzureMetrics`
: Various metrics on blob container utilisation and performance.
: This table is not reserved for the sensitive data containers and other resources may log to it.

### Desired state data logs

The desired state container holds the data necessary to configure virtual machines in an SRE.
Logs from the desired state container are ingested into the [SRE's log analytics workspace](#log-workspace).
There are two tables,

`StorageBlobLogs`
: Events occurring on the blob containers.
: For example data being uploaded, extracted or read.

`AzureMetrics`
: Various metrics on blob container utilisation and performance.
: This table is not reserved for the desired state data container and other resources may log to it.

### User data logs

The user data file share holds the {ref}`researchers'<role_researcher>` [home directories](https://refspecs.linuxfoundation.org/FHS_3.0/fhs/ch03s08.html), where they will store their personal data and configuration.
Logs from the share are ingested into the [SRE's log analytics workspace](#log-workspace).
There are two tables,

`StorageFileLogs`
: NFS events occurring on the file share.
: For example data being written or directories being accessed

`AzureMetrics`
: Various metrics on file share utilisation and performance.
: This table is not reserved for the user data share and other resources may log to it.

### Configuration data logs

There are multiple configuration data file shares.
Each contains the configuration and state data for the Data Safe Haven [services deployed as containers](#container-logs).
Logs from the share are ingested into the [SRE's log analytics workspace](#log-workspace).
There are two tables,

`StorageFileLogs`
: SMB events occurring on the file share.
: For example data being written or directories being accessed

`AzureMetrics`
: Various metrics on file share utilisation and performance.
: This table is not reserved for the configuration data shares and other resources may log to it.

## Container logs

Some of the Data Safe Haven infrastructure is provisioned as containers.
These include,

- remote desktop portal
- package proxy
- Gitea and Hedgedoc

Logs from all containers are ingested into the [SRE's log analytics workspace](#log-workspace).
There are two tables,

`ContainerEvents_CL`
: Event logs for the container instance resources such as starting, stopping, crashes and pulling images.

`ContainerInstanceLog_CL`
: Container process logs.
: This is where you can view the output of the containerised applications and will be useful for debugging problems.

## Workspace logs

Logs from all user workspaces are ingested into the [SRE's log analytics workspace](#log-workspace) using the [Azure Monitor Agent](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-overview).

There are three tables,

`Perf`
: Usage statistics for individual workspaces, such as percent memory used and percent disk space used.

`Syslog`
: [syslog](https://www.paessler.com/it-explained/syslog) events from workspaces.
: Syslog is the _de facto_ standard protocol for logging on Linux and most applications will log to it.
: These logs will be useful for debugging problems with the workspace or workspace software.

`Heartbeat`
: Verification that the Azure Monitor Agent is present on the workspaces and is able to connect to the [log analytics workspace](#log-workspace).

## Firewall logs

The firewall plays a critical role in the security of a Data Safe Haven.
It filters all outbound traffic through a set of FQDN rules so that each component may only reach necessary and allowed domains.

Logs from the firewall are ingested into the [SREs log workspace](#log-workspace).
There are three tables,

`AZFWApplicationRule`
: Logs from the firewalls FDQN filters.
: Shows requests to the outside of the Data Safe Haven and why they have been approved or rejected.

`AZFWDnsQuery`
: DNS requests handled by the firewall.

`AzureMetrics`
: Various metrics on firewall utilisation and performance.
: This table is not reserved for the firewall and other resources may log to it.
