from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network


class LocalDnsRecordProps:
    """Properties for LocalDnsRecordComponent"""

    def __init__(
        self,
        base_fqdn: Input[str],
        public_dns_resource_group_name: Input[str],
        private_dns_resource_group_name: Input[str],
        private_ip_address: Input[str],
        record_name: Input[str],
    ) -> None:
        self.base_fqdn = base_fqdn
        self.public_dns_resource_group_name = public_dns_resource_group_name
        self.private_dns_resource_group_name = private_dns_resource_group_name
        self.private_ip_address = private_ip_address
        self.record_name = record_name


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
        private_dns_record_set = network.PrivateRecordSet(
            f"{self._name}_private_record_set",
            a_records=[
                network.ARecordArgs(
                    ipv4_address=props.private_ip_address,
                )
            ],
            private_zone_name=Output.concat("privatelink.", props.base_fqdn),
            record_type="A",
            relative_record_set_name=props.record_name,
            resource_group_name=props.private_dns_resource_group_name,
            ttl=3600,
            opts=child_opts,
        )

        # Redirect the public DNS to private DNS
        network.RecordSet(
            f"{self._name}_public_record_set",
            cname_record=network.CnameRecordArgs(
                cname=Output.concat(props.record_name, ".privatelink.", props.base_fqdn)
            ),
            record_type="CNAME",
            relative_record_set_name=props.record_name,
            resource_group_name=props.public_dns_resource_group_name,
            ttl=3600,
            zone_name=props.base_fqdn,
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=private_dns_record_set)
            ),
        )

        # Register outputs
        self.hostname = Output.concat(props.record_name, ".", props.base_fqdn)
