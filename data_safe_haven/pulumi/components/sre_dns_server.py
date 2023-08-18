"""Pulumi component for SRE DNS management"""
import pathlib

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, network, storage

# from data_safe_haven.external import AzureIPv4Range
from data_safe_haven.pulumi.common import get_id_from_subnet
from data_safe_haven.pulumi.dynamic.file_share_file import (
    FileShareFile,
    FileShareFileProps,
)
from data_safe_haven.utility import FileReader


class SREDnsServerProps:
    """Properties for SREDnsServerComponent"""

    def __init__(
        self,
        resource_group_name: Input[str],
        subnet: Input[network.GetSubnetResult],
        storage_account_name: Input[str],
        storage_account_key: Input[str],
        storage_account_resource_group_name: Input[str],
        virtual_network: Input[network.VirtualNetwork],
    ) -> None:
        self.resource_group_name = resource_group_name
        self.subnet_id = Output.from_input(subnet).apply(get_id_from_subnet)
        self.storage_account_name = storage_account_name
        self.storage_account_key = Output.secret(storage_account_key)
        self.storage_account_resource_group_name = storage_account_resource_group_name
        self.virtual_network = virtual_network


class SREDnsServerComponent(ComponentResource):
    """Deploy DNS management with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREDnsServerProps,
        opts: ResourceOptions | None = None,
    ) -> None:
        super().__init__("dsh:sre:DnsServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))

        # Define configuration file shares
        file_share_dns_adguard = storage.FileShare(
            f"{self._name}_file_share_dns_adguard",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="dns-adguard",
            share_quota=1,
            opts=child_opts,
        )

        # Upload PiHole entrypoint script
        resources_path = (
            pathlib.Path(__file__).parent.parent.parent / "resources" / "dns_server"
        )
        dns_adguard_adguardhome_yaml_reader = FileReader(
            resources_path / "AdGuardHome.yaml"
        )
        file_share_dns_adguard_adguardhome_yaml = FileShareFile(
            f"{self._name}_file_share_dns_adguard_adguardhome_yaml",
            FileShareFileProps(
                destination_path=dns_adguard_adguardhome_yaml_reader.name,
                share_name=file_share_dns_adguard.name,
                file_contents=Output.secret(
                    dns_adguard_adguardhome_yaml_reader.file_contents()
                ),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=file_share_dns_adguard)
            ),
        )

        # Define a network profile
        container_network_profile = network.NetworkProfile(
            f"{self._name}_container_network_profile",
            container_network_interface_configurations=[
                network.ContainerNetworkInterfaceConfigurationArgs(
                    ip_configurations=[
                        network.IPConfigurationProfileArgs(
                            name="ipconfigdnscontainers",
                            subnet=network.SubnetArgs(
                                id=props.subnet_id,
                            ),
                        )
                    ],
                    name="networkinterfaceconfigdnscontainers",
                )
            ],
            network_profile_name=f"{stack_name}-np-dns-containers",
            resource_group_name=props.resource_group_name,
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    depends_on=[props.virtual_network],
                    ignore_changes=[
                        "container_network_interface_configurations"
                    ],  # allow container groups to be registered to this interface
                ),
            ),
        )

        # Define the DNS container group with AdGuard
        containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"{stack_name}-container-group-dns",
            containers=[
                containerinstance.ContainerArgs(
                    image="adguard/adguardhome:v0.107.36",
                    name="adguardhome",
                    ports=[
                        containerinstance.ContainerPortArgs(
                            port=53,
                            protocol=containerinstance.ContainerGroupNetworkProtocol.UDP,
                        ),
                        containerinstance.ContainerPortArgs(
                            port=80,
                            protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                        ),
                    ],
                    resources=containerinstance.ResourceRequirementsArgs(
                        requests=containerinstance.ResourceRequestsArgs(
                            cpu=1,
                            memory_in_gb=1,
                        ),
                    ),
                    volume_mounts=[
                        containerinstance.VolumeMountArgs(
                            mount_path="/opt/adguardhome/conf",
                            name="adguard-opt-adguardhome-conf",
                            read_only=False,
                        ),
                    ],
                ),
            ],
            ip_address=containerinstance.IpAddressArgs(
                ports=[
                    containerinstance.PortArgs(
                        port=80,
                        protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                    )
                ],
                type=containerinstance.ContainerGroupIpAddressType.PRIVATE,
            ),
            network_profile=containerinstance.ContainerGroupNetworkProfileArgs(
                id=container_network_profile.id,
            ),
            os_type=containerinstance.OperatingSystemTypes.LINUX,
            resource_group_name=props.resource_group_name,
            restart_policy=containerinstance.ContainerGroupRestartPolicy.ALWAYS,
            sku=containerinstance.ContainerGroupSku.STANDARD,
            volumes=[
                containerinstance.VolumeArgs(
                    azure_file=containerinstance.AzureFileVolumeArgs(
                        share_name=file_share_dns_adguard.name,
                        storage_account_key=props.storage_account_key,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="adguard-opt-adguardhome-conf",
                ),
            ],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    delete_before_replace=True,
                    depends_on=[
                        file_share_dns_adguard_adguardhome_yaml,
                    ],
                    replace_on_changes=["containers"],
                ),
            ),
        )
