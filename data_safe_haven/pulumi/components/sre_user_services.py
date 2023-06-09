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
        ldap_security_group_name: Input[str],
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
        self.ldap_security_group_name = ldap_security_group_name
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
        file_share_vcs_gitea = storage.FileShare(
            f"{self._name}_file_share_vcs_gitea",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="user-services-vcs-gitea",
            share_quota=1,
            opts=child_opts,
        )

        # Set resources path
        resources_path = (
            pathlib.Path(__file__).parent.parent.parent / "resources" / "user_services"
        )

        # Upload caddy file
        caddy_caddyfile_reader = FileReader(resources_path / "vcs" / "caddy" / "Caddyfile")
        file_share_vcs_caddy_caddyfile = FileShareFile(
            f"{self._name}_file_share_vcs_caddy_caddyfile",
            FileShareFileProps(
                destination_path=caddy_caddyfile_reader.name,
                share_name=file_share_vcs_caddy.name,
                file_contents=Output.secret(caddy_caddyfile_reader.file_contents()),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=child_opts,
        )

        # Upload Gitea configuration script
        gitea_configure_sh_reader = FileReader(resources_path / "vcs" / "gitea" / "configure.mustache.sh")
        gitea_configure_sh = Output.all(
            admin_email="dshadmin@example.com",
            admin_username="dshadmin",
            ldap_root_dn=props.ldap_root_dn,
            ldap_search_password=props.ldap_search_password,
            ldap_server_ip=props.ldap_server_ip,
            ldap_security_group_name=props.ldap_security_group_name,
        ).apply(lambda mustache_values: gitea_configure_sh_reader.file_contents(mustache_values))
        file_share_vcs_gitea_configure_sh = FileShareFile(
            f"{self._name}_file_share_vcs_gitea_configure_sh",
            FileShareFileProps(
                destination_path=gitea_configure_sh_reader.name,
                share_name=file_share_vcs_gitea.name,
                file_contents=Output.secret(gitea_configure_sh),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=child_opts,
        )
        # Upload Gitea entrypoint script
        gitea_entrypoint_sh_reader = FileReader(resources_path / "vcs" / "gitea" / "entrypoint.sh")
        file_share_vcs_gitea_entrypoint_sh = FileShareFile(
            f"{self._name}_file_share_vcs_gitea_entrypoint_sh",
            FileShareFileProps(
                destination_path=gitea_entrypoint_sh_reader.name,
                share_name=file_share_vcs_gitea.name,
                file_contents=Output.secret(gitea_entrypoint_sh_reader.file_contents()),
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
                    image="gitea/gitea:latest",
                    name=f"{stack_name[:37]}-container-group-vcs-gitea",  # maximum of 63 characters
                    command=["/app/custom/entrypoint.sh"],
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
                        containerinstance.EnvironmentVariableArgs(
                            name="GITEA__log__LEVEL",
                            value="Debug",  # Options are: "Trace", "Debug", "Info" [default], "Warn", "Error", "Critical" or "None".
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
                    volume_mounts=[
                        containerinstance.VolumeMountArgs(
                            mount_path="/app/custom",
                            name="gitea-app-custom",
                            read_only=True,
                        ),
                    ],
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
                    name="caddy-etc-caddy",
                ),
                containerinstance.VolumeArgs(
                    azure_file=containerinstance.AzureFileVolumeArgs(
                        share_name=file_share_vcs_gitea.name,
                        storage_account_key=props.storage_account_key,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="gitea-app-custom",
                ),
            ],
            opts=child_opts,
        )
