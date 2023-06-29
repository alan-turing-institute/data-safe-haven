"""Pulumi component for SRE monitoring"""
# Standard library import
import pathlib
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, network, resources, storage


# Local imports
from data_safe_haven.helpers import FileReader
from data_safe_haven.pulumi.common.transformations import (
    get_available_ips_from_subnet,
    get_id_from_subnet,
    get_ip_address_from_container_group,
)
from ..dynamic.file_share_file import FileShareFile, FileShareFileProps


class SRESoftwareRepositoriesProps:
    """Properties for SRESoftwareRepositoriesComponent"""

    def __init__(
        self,
        location: Input[str],
        networking_resource_group_name: Input[str],
        nexus_admin_password: Input[str],
        software_packages: str,
        sre_fqdn: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group_name: Input[str],
        subnet: Input[network.GetSubnetResult],
        virtual_network: Input[network.VirtualNetwork],
        virtual_network_resource_group_name: Input[str],
    ) -> None:
        self.location = location
        self.networking_resource_group_name = networking_resource_group_name
        self.nexus_admin_password = Output.secret(nexus_admin_password)
        try:
            self.nexus_packages = {"any": "all", "pre-approved": "selected"}[
                software_packages
            ]
        except KeyError:
            self.nexus_packages = None
        self.sre_fqdn = sre_fqdn
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.storage_account_resource_group_name = storage_account_resource_group_name
        self.subnet_id = Output.from_input(subnet).apply(get_id_from_subnet)
        self.subnet_ip_addresses = Output.from_input(subnet).apply(
            get_available_ips_from_subnet
        )
        self.virtual_network = virtual_network
        self.virtual_network_resource_group_name = virtual_network_resource_group_name


class SRESoftwareRepositoriesComponent(ComponentResource):
    """Deploy SRE update servers with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SRESoftwareRepositoriesProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:sre:SRESoftwareRepositoriesComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-software-repositories",
            opts=child_opts,
        )

        # Define configuration file shares
        file_share_caddy = storage.FileShare(
            f"{self._name}_file_share_caddy",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="software-repositories-caddy",
            share_quota=1,
            opts=child_opts,
        )
        file_share_nexus = storage.FileShare(
            f"{self._name}_file_share_nexus",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="software-repositories-nexus",
            share_quota=5120,
            opts=child_opts,
        )
        file_share_nexus_allowlists = storage.FileShare(
            f"{self._name}_file_share_nexus_allowlists",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="software-repositories-nexus-allowlists",
            share_quota=1,
            opts=child_opts,
        )

        # Upload Caddyfile
        resources_path = pathlib.Path(__file__).parent.parent.parent / "resources"
        caddyfile_reader = FileReader(
            resources_path / "software_repositories" / "caddy" / "Caddyfile"
        )
        caddyfile = FileShareFile(
            f"{self._name}_file_share_caddyfile",
            FileShareFileProps(
                destination_path=caddyfile_reader.name,
                share_name=file_share_caddy.name,
                file_contents=Output.secret(caddyfile_reader.file_contents()),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=child_opts,
        )

        # Upload Nexus allowlists
        cran_reader = FileReader(
            resources_path / "software_repositories" / "allowlists" / "cran.allowlist"
        )
        cran_allowlist = FileShareFile(
            f"{self._name}_file_share_cran_allowlist",
            FileShareFileProps(
                destination_path=cran_reader.name,
                share_name=file_share_nexus_allowlists.name,
                file_contents=cran_reader.file_contents(),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=child_opts,
        )
        pypi_reader = FileReader(
            resources_path / "software_repositories" / "allowlists" / "pypi.allowlist"
        )
        pypi_allowlist = FileShareFile(
            f"{self._name}_file_share_pypi_allowlist",
            FileShareFileProps(
                destination_path=pypi_reader.name,
                share_name=file_share_nexus_allowlists.name,
                file_contents=pypi_reader.file_contents(),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=child_opts,
        )

        # Define a network profile
        container_network_profile = network.NetworkProfile(
            f"{self._name}_container_network_profile",
            container_network_interface_configurations=[
                network.ContainerNetworkInterfaceConfigurationArgs(
                    ip_configurations=[
                        network.IPConfigurationProfileArgs(
                            name="ipconfigsoftwarerepositories",
                            subnet=network.SubnetArgs(
                                id=props.subnet_id,
                            ),
                        )
                    ],
                    name="networkinterfaceconfigsoftwarerepositories",
                )
            ],
            network_profile_name=f"{stack_name}-np-software-repositories",
            resource_group_name=props.virtual_network_resource_group_name,
            opts=ResourceOptions.merge(
                ResourceOptions(
                    depends_on=[props.virtual_network],
                    ignore_changes=[
                        "container_network_interface_configurations"
                    ],  # allow container groups to be registered to this interface
                ),
                child_opts,
            ),
        )

        # Define the container group with nexus and caddy
        if props.nexus_packages:
            container_group = containerinstance.ContainerGroup(
                f"{self._name}_container_group",
                container_group_name=f"{stack_name}-container-software-repositories",
                containers=[
                    containerinstance.ContainerArgs(
                        image="caddy:2",
                        name="caddy"[:63],
                        ports=[
                            containerinstance.ContainerPortArgs(
                                port=80,
                                protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                            )
                        ],
                        resources=containerinstance.ResourceRequirementsArgs(
                            requests=containerinstance.ResourceRequestsArgs(
                                cpu=0.5,
                                memory_in_gb=0.5,
                            ),
                        ),
                        volume_mounts=[
                            containerinstance.VolumeMountArgs(
                                mount_path="/etc/caddy",
                                name="caddy-etc-caddy",
                                read_only=True,
                            ),
                        ],
                    ),
                    containerinstance.ContainerArgs(
                        image="sonatype/nexus3:latest",
                        name="nexus"[:63],
                        environment_variables=[],
                        ports=[],
                        resources=containerinstance.ResourceRequirementsArgs(
                            requests=containerinstance.ResourceRequestsArgs(
                                cpu=3,
                                memory_in_gb=4,
                            ),
                        ),
                        volume_mounts=[
                            containerinstance.VolumeMountArgs(
                                mount_path="/nexus-data",
                                name="nexus-nexus-data",
                                read_only=False,
                            ),
                        ],
                    ),
                    containerinstance.ContainerArgs(
                        image="ghcr.io/alan-turing-institute/nexus-allowlist:v0.3.0",
                        name="nexus-allowlist"[:63],
                        environment_variables=[
                            containerinstance.EnvironmentVariableArgs(
                                name="NEXUS_ADMIN_PASSWORD",
                                secure_value=props.nexus_admin_password,
                            ),
                            containerinstance.EnvironmentVariableArgs(
                                name="NEXUS_PACKAGES",
                                value=props.nexus_packages,
                            ),
                            containerinstance.EnvironmentVariableArgs(
                                name="NEXUS_HOST",
                                value="localhost",
                            ),
                            containerinstance.EnvironmentVariableArgs(
                                name="NEXUS_PORT",
                                value="8081",
                            ),
                        ],
                        ports=[],
                        resources=containerinstance.ResourceRequirementsArgs(
                            requests=containerinstance.ResourceRequestsArgs(
                                cpu=0.5,
                                memory_in_gb=0.5,
                            ),
                        ),
                        volume_mounts=[
                            containerinstance.VolumeMountArgs(
                                mount_path="/allowlists",
                                name="nexus-allowlists-allowlists",
                                read_only=True,
                            ),
                            containerinstance.VolumeMountArgs(
                                mount_path="/nexus-data",
                                name="nexus-nexus-data",
                                read_only=True,
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
                resource_group_name=resource_group.name,
                restart_policy=containerinstance.ContainerGroupRestartPolicy.ALWAYS,
                sku=containerinstance.ContainerGroupSku.STANDARD,
                volumes=[
                    containerinstance.VolumeArgs(
                        azure_file=containerinstance.AzureFileVolumeArgs(
                            share_name=file_share_caddy.name,
                            storage_account_key=props.storage_account_key,
                            storage_account_name=props.storage_account_name,
                        ),
                        name="caddy-etc-caddy",
                    ),
                    containerinstance.VolumeArgs(
                        azure_file=containerinstance.AzureFileVolumeArgs(
                            share_name=file_share_nexus.name,
                            storage_account_key=props.storage_account_key,
                            storage_account_name=props.storage_account_name,
                        ),
                        name="nexus-nexus-data",
                    ),
                    containerinstance.VolumeArgs(
                        azure_file=containerinstance.AzureFileVolumeArgs(
                            share_name=file_share_nexus_allowlists.name,
                            storage_account_key=props.storage_account_key,
                            storage_account_name=props.storage_account_name,
                        ),
                        name="nexus-allowlists-allowlists",
                    ),
                ],
                opts=child_opts,
            )
            # Register the container group in the SRE private DNS zone
            nexus_private_record_set = network.PrivateRecordSet(
                f"{self._name}_nexus_private_record_set",
                a_records=[
                    network.ARecordArgs(
                        ipv4_address=get_ip_address_from_container_group(
                            container_group
                        ),
                    )
                ],
                private_zone_name=Output.concat("privatelink.", props.sre_fqdn),
                record_type="A",
                relative_record_set_name="nexus",
                resource_group_name=props.networking_resource_group_name,
                ttl=3600,
                opts=child_opts,
            )
            # Redirect the public DNS to private DNS
            nexus_public_record_set = network.RecordSet(
                f"{self._name}_nexus_public_record_set",
                cname_record=network.CnameRecordArgs(
                    cname=Output.concat("nexus.privatelink.", props.sre_fqdn)
                ),
                record_type="CNAME",
                relative_record_set_name="nexus",
                resource_group_name=props.networking_resource_group_name,
                ttl=3600,
                zone_name=props.sre_fqdn,
                opts=child_opts,
            )
