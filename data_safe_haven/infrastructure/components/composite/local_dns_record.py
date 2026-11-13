from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import dns, privatedns


class LocalDnsRecordProps:
    """Properties for LocalDnsRecordComponent"""

    def __init__(
        self,
        base_fqdn: Input[str],
        private_ip_address: Input[str],
        record_name: Input[str],
        resource_group_name: Input[str],
    ) -> None:
        self.base_fqdn = base_fqdn
        self.private_ip_address = private_ip_address
        self.record_name = record_name
        self.resource_group_name = resource_group_name


class LocalDnsRecordComponent(ComponentResource):
    """Deploy public and private DNS records with Pulumi"""

    def __init__(
        self,
        name: str,
        props: LocalDnsRecordProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:common:LocalDnsRecordComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

        # Register the resource in a private DNS zone
        private_dns_record_set = privatedns.PrivateRecordSet(
            f"{self._name}_private_record_set",
            a_records=[
                privatedns.ARecordArgs(
                    ipv4_address=props.private_ip_address,
                )
            ],
            private_zone_name=Output.concat("privatelink.", props.base_fqdn),
            record_type="A",
            relative_record_set_name=props.record_name,
            resource_group_name=props.resource_group_name,
            ttl=30,
            opts=child_opts,
        )

        # Redirect the public DNS to private DNS
        self.public_dns_record_set = dns.RecordSet(
            f"{self._name}_public_record_set",
            cname_record=dns.CnameRecordArgs(
                cname=Output.concat(props.record_name, ".privatelink.", props.base_fqdn)
            ),
            record_type="CNAME",
            relative_record_set_name=props.record_name,
            resource_group_name=props.resource_group_name,
            ttl=3600,
            zone_name=props.base_fqdn,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=private_dns_record_set)
            ),
        )

        # Register outputs
        self.hostname = self.public_dns_record_set.fqdn.apply(
            lambda s: s.strip(".")  # strip trailing "."
        )

        self.private_record_set_id = private_dns_record_set.id

        self.register_outputs({})
