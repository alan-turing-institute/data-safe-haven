"""Storage naming must fix new deployments without renaming existing data."""

from types import SimpleNamespace

import pulumi
import pulumi.runtime
import pulumi_random
import pytest
from pulumi_azure_native import (
    network,
    operationalinsights,
    privatedns,
    resources,
    storage,
)

from data_safe_haven.functions import get_sre_storage_account_name
from data_safe_haven.infrastructure.programs.sre.data import (
    SREDataComponent,
    SREDataProps,
)
from data_safe_haven.infrastructure.programs.sre.desired_state import (
    SREDesiredStateComponent,
    SREDesiredStateProps,
)
from data_safe_haven.types import AzureDnsZoneNames


@pytest.mark.parametrize("kind", ["data", "desired_state"])
@pulumi.runtime.test
def test_storage_resources_preserve_names_on_updates(kind, mocker):
    captured = {}

    def capture(args):
        if args.type_ == "azure-native:storage:StorageAccount":
            captured[args.name] = args

    monitor = pulumi.runtime.settings.get_monitor()
    original_new_resource = monitor.mocks.new_resource

    def with_names(args):
        resource_id, outputs = original_new_resource(args)
        if args.typ == "azure-native:storage:StorageAccount":
            outputs["name"] = args.inputs["accountName"]
        return resource_id, outputs

    mocker.patch.object(monitor.mocks, "new_resource", side_effect=with_names)
    mocker.patch.object(
        storage,
        "list_storage_account_keys",
        return_value=SimpleNamespace(keys=[SimpleNamespace(value="test-key")]),
    )
    group = resources.ResourceGroup("naming_group", resource_group_name="rg-names")
    workspace = operationalinsights.Workspace(
        "naming_workspace", resource_group_name=group.name, location="uksouth"
    )
    zones = {
        name: privatedns.PrivateZone(
            "naming_" + name,
            private_zone_name=name,
            resource_group_name=group.name,
            location="global",
        )
        for name in AzureDnsZoneNames.STORAGE_ACCOUNT
    }
    subnet = network.GetSubnetResult(id="/subscriptions/test/subnets/storage")
    stack_name = "shm-pro-sre-dsg1234"
    opts = pulumi.ResourceOptions(transformations=[capture], ignore_changes=["tags"])
    if kind == "data":
        component = SREDataComponent(
            "naming_data",
            stack_name,
            SREDataProps(
                admin_email_address="admin@example.com",
                admin_group_id="00000000-0000-0000-0000-000000000001",
                admin_ip_addresses=[],
                data_provider_ip_addresses=[],
                dns_private_zones=zones,
                dns_record=group,
                dns_server_admin_password=pulumi_random.RandomPassword(
                    "naming_password", length=20
                ),
                location="uksouth",
                log_analytics_workspace=workspace,
                resource_group=group,
                sre_fqdn="sre.example.com",
                storage_quota_gb_home=100,
                storage_quota_gb_shared=100,
                subnet_data_configuration=subnet,
                subnet_data_private=subnet,
                subscription_id="00000000-0000-0000-0000-000000000002",
                subscription_name="test",
                tenant_id="test",
            ),
            opts=opts,
        )
        expected = {
            "naming_data_storage_account_data_configuration": ("configdata", 14, None),
            "naming_data_storage_account_data_private_sensitive": (
                "sensitivedata",
                11,
                "naming_data",
            ),
            "naming_data_storage_account_data_private_user": (
                "userdata",
                16,
                "naming_data",
            ),
        }
    else:
        component = SREDesiredStateComponent(
            "naming_desired_state",
            stack_name,
            SREDesiredStateProps(
                admin_ip_addresses=[],
                allow_workspace_internet=False,
                clamav_mirror_hostname="clamav.example.com",
                database_service_admin_password="test-password",
                dns_private_zones=zones,
                gitea_hostname="gitea.example.com",
                hedgedoc_hostname="hedgedoc.example.com",
                ldap_group_filter="group",
                ldap_group_search_base="DC=example",
                ldap_server_hostname="ldap.example.com",
                ldap_server_port=636,
                ldap_user_filter="user",
                ldap_user_search_base="DC=example",
                location="uksouth",
                log_analytics_workspace=workspace,
                resource_group=group,
                software_repository_hostname="nexus.example.com",
                subscription_name="test",
                subnet_desired_state=subnet,
            ),
            opts=opts,
        )
        expected = {
            "naming_desired_state_storage_account": (
                "desiredstate",
                11,
                "naming_desired_state",
            ),
        }

    def check(_):
        assert captured.keys() == expected.keys()
        for name, (purpose, budget, component_name) in expected.items():
            args = captured[name]
            assert "account_name" in args.opts.ignore_changes
            assert "tags" in args.opts.ignore_changes
            assert args.opts.parent is not None
            assert args.props["account_name"] == get_sre_storage_account_name(
                stack_name, purpose, budget, component_name
            )

    return component.urn.apply(check)
