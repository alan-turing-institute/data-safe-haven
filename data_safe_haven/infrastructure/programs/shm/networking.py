"""Pulumi component for SHM networking"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, ResourceOptions
from pulumi_azure_native import network

from data_safe_haven.external import AzureIPv4Range


class SHMNetworkingProps:
    """Properties for SHMNetworkingComponent"""

    def __init__(
        self,
        fqdn: Input[str],
        location: Input[str],
        record_domain_verification: Input[str],
        resource_group_name: Input[str],
    ) -> None:
        # Virtual network and subnet IP ranges
        self.vnet_iprange = AzureIPv4Range("10.0.0.0", "10.0.255.255")
        # Monitoring subnet needs 13 IP addresses for log analytics
        self.subnet_monitoring_iprange = self.vnet_iprange.next_subnet(32)
        # Other variables
        self.fqdn = fqdn
        self.location = location
        self.record_domain_verification = record_domain_verification
        self.resource_group_name = resource_group_name


class SHMNetworkingComponent(ComponentResource):
    """Deploy SHM networking with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,  # noqa: ARG002
        props: SHMNetworkingProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:shm:NetworkingComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Define SHM DNS zone
        dns_zone = network.Zone(
            f"{self._name}_dns_zone",
            location="Global",
            resource_group_name=props.resource_group_name,
            zone_name=props.fqdn,
            zone_type=network.ZoneType.PUBLIC,
            opts=child_opts,
            tags=child_tags,
        )
        network.RecordSet(
            f"{self._name}_caa_record",
            caa_records=[
                network.CaaRecordArgs(
                    flags=0,
                    tag="issue",
                    value="letsencrypt.org",
                )
            ],
            record_type="CAA",
            relative_record_set_name="@",
            resource_group_name=props.resource_group_name,
            ttl=30,
            zone_name=dns_zone.name,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=dns_zone)),
        )
        network.RecordSet(
            f"{self._name}_domain_verification_record",
            record_type="TXT",
            relative_record_set_name="@",
            resource_group_name=props.resource_group_name,
            ttl=3600,
            txt_records=[
                network.TxtRecordArgs(value=[props.record_domain_verification])
            ],
            zone_name=dns_zone.name,
            opts=ResourceOptions.merge(child_opts, ResourceOptions(parent=dns_zone)),
        )

        # Register outputs
        self.dns_zone = dns_zone

        # Register exports
        self.exports = {
            "fqdn": self.dns_zone.name,
            "fqdn_nameservers": self.dns_zone.name_servers,
        }
