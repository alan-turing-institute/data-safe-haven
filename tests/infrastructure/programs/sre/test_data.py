from typing import Any

import pulumi
import pulumi_random
from pulumi_azure_native import resources
from pytest import fixture

from data_safe_haven.infrastructure.programs.sre.data import (
    SREDataComponent,
    SREDataProps,
)
from data_safe_haven.infrastructure.programs.sre.dns_server import (
    SREDnsServerComponent,
)
from data_safe_haven.infrastructure.programs.sre.monitoring_elements import (
    SREMonitoringElementsComponent,
)
from data_safe_haven.infrastructure.programs.sre.networking import (
    SRENetworkingComponent,
)
from tests.infrastructure.programs.resource_assertions import assert_equal


@fixture
def data_component(
    dns: SREDnsServerComponent,
    location: str,
    monitoring_elements: SREMonitoringElementsComponent,
    networking: SRENetworkingComponent,
    resource_group: resources.ResourceGroup,
    sre_fqdn: str,
    stack_name: str,
    tags: dict[str, str],
) -> SREDataComponent:
    return SREDataComponent(
        "sre_data",
        stack_name,
        SREDataProps(
            admin_email_address="admin@example.com",
            admin_group_id="admin-group-id",
            admin_ip_addresses=["1.2.3.4"],
            data_provider_ip_addresses=["5.6.7.8"],
            dns_private_zones=dns.private_zones,
            dns_record=networking.shm_ns_record,
            dns_server_admin_password=pulumi_random.RandomPassword(
                "password_dns_server_admin", length=20
            ),
            location=location,
            log_analytics_workspace=monitoring_elements.workspace_analytics.workspace,
            resource_group=resource_group,
            sre_fqdn=sre_fqdn,
            storage_quota_gb_home=100,
            storage_quota_gb_shared=100,
            subnet_data_configuration=networking.subnet_data_configuration,
            subnet_data_private=networking.subnet_data_private,
            subscription_id="abcd-0123-abcd-0123",
            subscription_name="subscription-name",
            tenant_id="tenant-id",
        ),
        tags=tags,
    )


class TestSREDataComponent:
    @pulumi.runtime.test
    def test_exports_storage_account_data_private_sensitive_name(
        self, data_component: SREDataComponent
    ) -> Any:
        def check(args: list[Any]) -> None:
            exported_name, account_name = args
            assert exported_name
            assert_equal(account_name, exported_name)

        return pulumi.Output.all(
            data_component.exports["storage_account_data_private_sensitive_name"],
            data_component.storage_account_data_private_sensitive_name,
        ).apply(check)
