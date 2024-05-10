def azure_dns_zone_names(resource_type: str | None = None) -> tuple[str, ...]:
    """
    Return a list of DNS zones used by a given Azure resource type.
    See https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns for details.
    """
    dns_zones = {
        "Azure Automation": ("azure-automation.net",),
        "Azure Monitor": (
            "agentsvc.azure-automation.net",
            "blob.core.windows.net",
            "monitor.azure.com",
            "ods.opinsights.azure.com",
            "oms.opinsights.azure.com",
        ),
        "Storage account": ("blob.core.windows.net", "file.core.windows.net"),
    }
    if resource_type and (resource_type in dns_zones):
        return dns_zones[resource_type]
    return tuple(sorted({zone for zones in dns_zones.values() for zone in zones}))
