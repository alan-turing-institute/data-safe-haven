from collections.abc import Mapping, Sequence

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import insights, storage

from data_safe_haven.external import AzureIPv4Range
from data_safe_haven.infrastructure.components.wrapped import (
    WrappedLogAnalyticsWorkspace,
)


class NFSV3StorageAccountProps:
    def __init__(
        self,
        account_name: Input[str],
        allowed_ip_addresses: Input[Sequence[str]] | None,
        location: Input[str],
        log_analytics_workspace: Input[WrappedLogAnalyticsWorkspace],
        resource_group_name: Input[str],
        subnet_id: Input[str],
    ):
        self.account_name = account_name
        self.allowed_ip_addresses = allowed_ip_addresses
        self.location = location
        self.log_analytics_workspace = log_analytics_workspace
        self.resource_group_name = resource_group_name
        self.subnet_id = subnet_id


class NFSV3StorageAccountComponent(ComponentResource):
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
        name: str,
        props: NFSV3StorageAccountProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ):
        super().__init__("dsh:sre:NFSV3StorageAccountComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = {"component": "data"} | (tags if tags else {})

        ip_rules = Output.from_input(props.allowed_ip_addresses).apply(
            lambda ip_ranges: [
                storage.IPRuleArgs(
                    action=storage.Action.ALLOW,
                    i_p_address_or_range=str(ip_address),
                )
                for ip_range in sorted(ip_ranges)
                for ip_address in AzureIPv4Range.from_cidr(ip_range).all_ips()
            ]
        )

        # Deploy storage account
        self.storage_account = storage.StorageAccount(
            f"{self._name}",
            account_name=props.account_name,
            allow_blob_public_access=False,
            enable_https_traffic_only=True,
            enable_nfs_v3=True,
            encryption=self.encryption_args,
            is_hns_enabled=True,
            kind=storage.Kind.BLOCK_BLOB_STORAGE,
            location=props.location,
            minimum_tls_version=storage.MinimumTlsVersion.TLS1_2,
            network_rule_set=storage.NetworkRuleSetArgs(
                bypass=storage.Bypass.AZURE_SERVICES,
                default_action=storage.DefaultAction.DENY,
                ip_rules=ip_rules,
                virtual_network_rules=[
                    storage.VirtualNetworkRuleArgs(
                        virtual_network_resource_id=props.subnet_id,
                    )
                ],
            ),
            public_network_access=storage.PublicNetworkAccess.ENABLED,
            resource_group_name=props.resource_group_name,
            sku=storage.SkuArgs(name=storage.SkuName.PREMIUM_ZRS),
            opts=child_opts,
            tags=child_tags,
        )

        # Add diagnostic setting for blobs
        insights.DiagnosticSetting(
            f"{self.storage_account._name}_diagnostic_setting",
            name=f"{self.storage_account._name}_diagnostic_setting",
            log_analytics_destination_type="Dedicated",
            logs=[
                {
                    "category_group": "allLogs",
                    "enabled": True,
                    "retention_policy": {
                        "days": 0,
                        "enabled": False,
                    },
                },
                {
                    "category_group": "audit",
                    "enabled": True,
                    "retention_policy": {
                        "days": 0,
                        "enabled": False,
                    },
                },
            ],
            metrics=[
                {
                    "category": "Transaction",
                    "enabled": True,
                    "retention_policy": {
                        "days": 0,
                        "enabled": False,
                    },
                }
            ],
            resource_uri=self.storage_account.id.apply(
                # This is the URI of the blobServices resource which is automatically
                # created.
                lambda resource_id: resource_id
                + "/blobServices/default"
            ),
            workspace_id=props.log_analytics_workspace.id,
        )

        self.register_outputs({})
