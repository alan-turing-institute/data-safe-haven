import pulumi
import pulumi.runtime
from pulumi_azure_native import network, resources
from pytest import fixture

from data_safe_haven.infrastructure.common import DockerHubCredentials, SREDnsIpRanges
from data_safe_haven.infrastructure.programs.sre.dns_server_vm import (
    READINESS_CHECK_TIMEOUT_SECONDS,
    SREDnsServerVMComponent,
    SREDnsServerVMProps,
)
from data_safe_haven.resources import resources_path
from data_safe_haven.utility import FileReader
from tests.infrastructure.programs.resource_assertions import assert_equal

CLOUD_INIT_VALUES: dict[str, str] = {
    "adguardhome_yaml_content_encoded": "yaml",
    "container_image": "adguard/adguardhome:latest",
    "dockerhub_access_token": "token",
    "dockerhub_username": "username",
    "entrypoint_sh_content_encoded": "entrypoint",
}


@fixture
def dns_server_vm_component(
    dockerhub_credentials: DockerHubCredentials,
    location: str,
    resource_group: resources.ResourceGroup,
    stack_name: str,
) -> SREDnsServerVMComponent:
    virtual_network = network.VirtualNetwork(
        "dns_virtual_network",
        resource_group_name=resource_group.name,
        virtual_network_name="vnet-dns",
    )
    return SREDnsServerVMComponent(
        "dns_server_vm",
        stack_name,
        SREDnsServerVMProps(
            adguardhome_yaml_content="adguardhome: yaml",
            admin_password="password",
            dockerhub_credentials=dockerhub_credentials,
            entrypoint_sh_content="#!/bin/sh",
            location=location,
            maintenance_configuration_id="maintenance_configuration_id",
            resource_group_name=resource_group.name,
            subnet_dns=network.GetSubnetResult(
                address_prefix=SREDnsIpRanges.vnet.prefix,
                id="subnet_dns_id",
                name="DnsSubnet",
            ),
            virtual_network=virtual_network,
            vm_size="Standard_B2als_v2",
        ),
    )


class TestSREDnsServerVMComponent:
    @pulumi.runtime.test  # type: ignore
    def test_readiness_check_blocks_deployment(
        self, dns_server_vm_component: SREDnsServerVMComponent
    ) -> pulumi.Output[None]:
        """Check that the run command is synchronous and fails the deployment"""
        expected_script = FileReader(
            resources_path / "dns_server" / "wait_for_dns_server.sh"
        ).file_contents()
        readiness_check = dns_server_vm_component.readiness_check

        def check(values: list[bool | int | str]) -> None:
            async_execution, treat_failure, timeout, script = values
            assert async_execution is False
            assert treat_failure is True
            assert_equal(READINESS_CHECK_TIMEOUT_SECONDS, timeout)
            assert_equal(expected_script, script)

        return pulumi.Output.all(
            readiness_check.async_execution,
            readiness_check.treat_failure_as_deployment_failure,
            readiness_check.timeout_in_seconds,
            readiness_check.source.apply(lambda source: source.script),
        ).apply(check)

    def test_cloud_init_enables_adguardhome_service(self) -> None:
        """Check that AdGuard Home is enabled so it restarts after a reboot"""
        cloud_init = SREDnsServerVMComponent.template_cloudinit(**CLOUD_INIT_VALUES)
        assert "WantedBy=multi-user.target" in cloud_init
        assert "systemctl enable --now adguardhome" in cloud_init
