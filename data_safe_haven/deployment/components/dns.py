# Standard library imports
from typing import Sequence

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network


class DnsProps:
    """Properties for DnsComponent"""

    def __init__(
        self,
        dns_name: Input[str],
        public_ip: Input[str],
        resource_group_name: Input[str],
        subdomains: Input[Sequence[str]],
    ):
        self.dns_name = dns_name
        self.public_ip = public_ip
        self.resource_group_name = resource_group_name
        self.subdomains = subdomains


class DnsComponent(ComponentResource):
    """Deploy DNS zones and records with Pulumi"""

    def __init__(self, name: str, props: DnsProps, opts: ResourceOptions = None):
        super().__init__("dsh:dns:DnsComponent", name, {}, opts)
        child_opts = ResourceOptions(parent=self)

        dns_zone = network.Zone(
            "dns_zone",
            location="Global",
            resource_group_name=props.resource_group_name,
            zone_name=props.dns_name,
            zone_type="Public",
            opts=child_opts,
        )
        dns_a_record = network.RecordSet(
            "dns_a_record",
            a_records=[
                network.ARecordArgs(
                    ipv4_address=props.public_ip,
                )
            ],
            record_type="A",
            relative_record_set_name="@",
            resource_group_name=props.resource_group_name,
            ttl=30,
            zone_name=dns_zone.name,
            opts=child_opts,
        )
        dns_caa_record = network.RecordSet(
            "dns_caa_record",
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
            opts=child_opts,
        )
        for cname in props.subdomains:
            network.RecordSet(
                f"dns_cname_record_{cname}",
                cname_record=network.CnameRecordArgs(
                    cname=dns_zone.name,
                ),
                record_type="CNAME",
                relative_record_set_name=cname,
                resource_group_name=props.resource_group_name,
                ttl=30,
                zone_name=dns_zone.name,
                opts=child_opts,
            )

        # Register outputs
        self.resource_group_name = Output.from_input(props.resource_group_name)
