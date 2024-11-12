from collections.abc import Mapping, Sequence

from pulumi import Input, Output, ResourceOptions
from pulumi_azure_native import storage

from data_safe_haven.external import AzureIPv4Range
from data_safe_haven.types import AzureServiceTag


class WrappedNFSV3StorageAccount(storage.StorageAccount):
    encryption_args = storage.EncryptionArgs(
        key_source=storage.KeySource.MICROSOFT_STORAGE,
        services=storage.EncryptionServicesArgs(
            blob=storage.EncryptionServiceArgs(
                enabled=True, key_type=storage.KeyType.ACCOUNT
            ),
            file=storage.EncryptionServiceArgs(
                enabled=True, key_type=storage.KeyType.ACCOUNT
            ),
        ),
    )

    def __init__(
        self,
        resource_name: str,
        *,
        account_name: Input[str],
        allowed_ip_addresses: Input[Sequence[str]] | None,
        allowed_service_tag: AzureServiceTag | None,
        location: Input[str],
        resource_group_name: Input[str],
        subnet_id: Input[str],
        opts: ResourceOptions,
        tags: Input[Mapping[str, Input[str]]],
    ):
        if allowed_service_tag == AzureServiceTag.INTERNET:
            default_action = storage.DefaultAction.ALLOW
            ip_rules = []
        else:
            default_action = storage.DefaultAction.DENY
            ip_rules = Output.from_input(allowed_ip_addresses).apply(
                lambda ip_ranges: [
                    storage.IPRuleArgs(
                        action=storage.Action.ALLOW,
                        i_p_address_or_range=str(ip_address),
                    )
                    for ip_range in sorted(ip_ranges)
                    for ip_address in AzureIPv4Range.from_cidr(ip_range).all_ips()
                ]
            )

        self.resource_group_name_ = Output.from_input(resource_group_name)
        super().__init__(
            resource_name,
            account_name=account_name,
            allow_blob_public_access=False,
            enable_https_traffic_only=True,
            enable_nfs_v3=True,
            encryption=self.encryption_args,
            is_hns_enabled=True,
            kind=storage.Kind.BLOCK_BLOB_STORAGE,
            location=location,
            minimum_tls_version=storage.MinimumTlsVersion.TLS1_2,
            network_rule_set=storage.NetworkRuleSetArgs(
                bypass=storage.Bypass.AZURE_SERVICES,
                default_action=default_action,
                ip_rules=ip_rules,
                virtual_network_rules=[
                    storage.VirtualNetworkRuleArgs(
                        virtual_network_resource_id=subnet_id,
                    )
                ],
            ),
            public_network_access=storage.PublicNetworkAccess.ENABLED,
            resource_group_name=resource_group_name,
            sku=storage.SkuArgs(name=storage.SkuName.PREMIUM_ZRS),
            opts=opts,
            tags=tags,
        )
