"""Built-in Log Analytics saved queries for SRE operational monitoring.

Keep these searches restricted to tables already collected by Data Safe Haven.
Sign-in failures here are Linux workspace syslog events, not Entra sign-in logs.
"""

from typing import Final

# Stable keys also feed the deterministic Azure saved-search IDs.
DEFAULT_SAVED_QUERIES: Final[dict[str, tuple[str, str]]] = {
    "failed_workspace_logins": (
        "Workspace - failed Linux authentication",
        """Syslog
| where TimeGenerated >= ago(24h)
| where Facility in~ ("auth", "authpriv")
| where SyslogMessage has_any ("Failed password", "authentication failure", "Invalid user")
| project TimeGenerated, Computer, ProcessName, SyslogMessage
| order by TimeGenerated desc""",
    ),
    "ingress_uploads": (
        "Sensitive data - ingress uploads",
        """StorageBlobLogs
| where TimeGenerated >= ago(7d)
| where Uri contains "/ingress/"
| where OperationName in~ ("PutBlob", "PutBlock", "PutBlockList", "CopyBlob")
| project TimeGenerated, Uri, OperationName, StatusCode, CallerIpAddress
| order by TimeGenerated desc""",
    ),
    "egress_downloads": (
        "Sensitive data - egress downloads",
        """StorageBlobLogs
| where TimeGenerated >= ago(7d)
| where Uri contains "/egress/"
| where OperationName =~ "GetBlob"
| project TimeGenerated, Uri, OperationName, StatusCode, CallerIpAddress
| order by TimeGenerated desc""",
    ),
}
