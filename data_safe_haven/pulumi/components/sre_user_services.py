# Standard library imports
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
)
from ..dynamic.file_share_file import FileShareFile, FileShareFileProps


class SREUserServicesProps:
    """Properties for SREUserServicesComponent"""

    def __init__(
        self,
        ldap_root_dn: Input[str],
        ldap_search_password: Input[str],
        ldap_server_ip: Input[str],
        ldap_sre_security_group_name: Input[str],
        location: Input[str],
        sre_fqdn: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group_name: Input[str],
        subnet: Input[network.GetSubnetResult],
        virtual_network: Input[network.VirtualNetwork],
        virtual_network_resource_group_name: Input[str],
    ):
        self.ldap_root_dn = ldap_root_dn
        self.ldap_search_password = ldap_search_password
        self.ldap_server_ip = ldap_server_ip
        self.ldap_sre_security_group_name = ldap_sre_security_group_name
        self.location = location
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


class SREUserServicesComponent(ComponentResource):
    """Deploy secure research desktops with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SREUserServicesProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:sre:SREUserServicesComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-user-services",
            opts=child_opts,
        )

        # Define configuration file shares
        file_share_vcs_caddy = storage.FileShare(
            f"{self._name}_file_share_vcs_caddy",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="user-services-vcs-caddy",
            share_quota=1,
            opts=child_opts,
        )

        # Set resources path
        resources_path = (
            pathlib.Path(__file__).parent.parent.parent / "resources" / "user_services"
        )

        # Upload caddy file
        reader = FileReader(resources_path / "vcs" / "caddy" / "Caddyfile")
        file_share_vcs_caddy_caddyfile = FileShareFile(
            f"{self._name}_file_share_vcs_caddy_caddyfile",
            FileShareFileProps(
                destination_path=reader.name,
                share_name=file_share_vcs_caddy.name,
                file_contents=Output.secret(reader.file_contents()),
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
                            name="ipconfiguserservices",
                            subnet=network.SubnetArgs(
                                id=props.subnet_id,
                            ),
                        )
                    ],
                    name="networkinterfaceconfiguserservices",
                )
            ],
            network_profile_name=f"{stack_name}-np-user-services",
            resource_group_name=props.virtual_network_resource_group_name,
            opts=ResourceOptions.merge(
                ResourceOptions(depends_on=[props.virtual_network]), child_opts
            ),
        )

        # Define the container group with guacd, guacamole and caddy
        container_group_vcs = containerinstance.ContainerGroup(
            f"{self._name}_container_group_vcs",
            container_group_name=f"{stack_name}-container-group-vcs",
            containers=[
                containerinstance.ContainerArgs(
                    image="caddy:latest",
                    name=f"{stack_name[:37]}-container-group-vcs-caddy",  # maximum of 63 characters
                    ports=[
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
                            mount_path="/etc/caddy",
                            name="vcs-caddy-caddyfile",
                            read_only=False,
                        ),
                    ],
                ),
                containerinstance.ContainerArgs(
                    image="gitea/gitea:latest",
                    name=f"{stack_name[:37]}-container-group-vcs-gitea",  # maximum of 63 characters
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="APP_NAME", value="Data Safe Haven Git server"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="RUN_MODE", value="dev"
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__security__INSTALL_LOCK", value="true"
                        ),
                    ],
                    ports=[
                        containerinstance.ContainerPortArgs(
                            port=22,
                            protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                        ),
                    ],
                    resources=containerinstance.ResourceRequirementsArgs(
                        requests=containerinstance.ResourceRequestsArgs(
                            cpu=2,
                            memory_in_gb=2,
                        ),
                    ),
                    volume_mounts=[],
                ),
            ],
            ip_address=containerinstance.IpAddressArgs(
                ip=props.subnet_ip_addresses[0],
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
                        share_name=file_share_vcs_caddy.name,
                        storage_account_key=props.storage_account_key,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="vcs-caddy-caddyfile",
                ),
            ],
            opts=child_opts,
        )
