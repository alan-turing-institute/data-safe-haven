# Standard library imports
import pathlib
from typing import Optional

# Third party imports
from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, network, storage

# Local imports
from data_safe_haven.helpers import FileReader
from ..dynamic.file_share_file import FileShareFile, FileShareFileProps


class SREGiteaServerProps:
    """Properties for SREGiteaServerComponent"""

    def __init__(
        self,
        container_ip_address: Input[str],
        ldap_bind_dn: Input[str],
        ldap_root_dn: Input[str],
        ldap_search_password: Input[str],
        ldap_server_ip: Input[str],
        ldap_security_group_name: Input[str],
        ldap_user_search_base: Input[str],
        location: Input[str],
        networking_resource_group_name: Input[str],
        network_profile_id: Input[str],
        sre_fqdn: Input[str],
        sre_private_dns_zone_id: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group_name: Input[str],
        user_services_resource_group_name: Input[str],
        virtual_network: Input[network.VirtualNetwork],
        virtual_network_resource_group_name: Input[str],
    ):
        self.container_ip_address = container_ip_address
        self.ldap_bind_dn = ldap_bind_dn
        self.ldap_root_dn = ldap_root_dn
        self.ldap_search_password = ldap_search_password
        self.ldap_server_ip = ldap_server_ip
        self.ldap_security_group_name = ldap_security_group_name
        self.ldap_user_search_base = ldap_user_search_base
        self.location = location
        self.networking_resource_group_name = networking_resource_group_name
        self.network_profile_id = network_profile_id
        self.sre_fqdn = sre_fqdn
        self.sre_private_dns_zone_id = sre_private_dns_zone_id
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.storage_account_resource_group_name = storage_account_resource_group_name
        self.user_services_resource_group_name = user_services_resource_group_name
        self.virtual_network = virtual_network
        self.virtual_network_resource_group_name = virtual_network_resource_group_name


class SREGiteaServerComponent(ComponentResource):
    """Deploy secure research desktops with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        sre_name: str,
        props: SREGiteaServerProps,
        opts: Optional[ResourceOptions] = None,
    ):
        super().__init__("dsh:sre:GiteaServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(ResourceOptions(parent=self), opts)

        # Define configuration file shares
        file_share_gitea_caddy = storage.FileShare(
            f"{self._name}_file_share_gitea_caddy",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="gitea-caddy",
            share_quota=1,
            opts=child_opts,
        )
        file_share_gitea_gitea = storage.FileShare(
            f"{self._name}_file_share_gitea_gitea",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="gitea-gitea",
            share_quota=1,
            opts=child_opts,
        )

        # Set resources path
        resources_path = (
            pathlib.Path(__file__).parent.parent.parent / "resources" / "gitea"
        )

        # Upload caddy file
        caddy_caddyfile_reader = FileReader(resources_path / "caddy" / "Caddyfile")
        file_share_gitea_caddy_caddyfile = FileShareFile(
            f"{self._name}_file_share_gitea_caddy_caddyfile",
            FileShareFileProps(
                destination_path=caddy_caddyfile_reader.name,
                share_name=file_share_gitea_caddy.name,
                file_contents=Output.secret(caddy_caddyfile_reader.file_contents()),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=child_opts,
        )

        # Upload Gitea configuration script
        gitea_configure_sh_reader = FileReader(
            resources_path / "gitea" / "configure.mustache.sh"
        )
        gitea_configure_sh = Output.all(
            admin_email="dshadmin@example.com",
            admin_username="dshadmin",
            ldap_bind_dn=props.ldap_bind_dn,
            ldap_root_dn=props.ldap_root_dn,
            ldap_search_password=props.ldap_search_password,
            ldap_security_group_name=props.ldap_security_group_name,
            ldap_server_ip=props.ldap_server_ip,
            ldap_user_search_base=props.ldap_user_search_base,
        ).apply(
            lambda mustache_values: gitea_configure_sh_reader.file_contents(
                mustache_values
            )
        )
        file_share_gitea_gitea_configure_sh = FileShareFile(
            f"{self._name}_file_share_gitea_gitea_configure_sh",
            FileShareFileProps(
                destination_path=gitea_configure_sh_reader.name,
                share_name=file_share_gitea_gitea.name,
                file_contents=Output.secret(gitea_configure_sh),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=child_opts,
        )
        # Upload Gitea entrypoint script
        gitea_entrypoint_sh_reader = FileReader(
            resources_path / "gitea" / "entrypoint.sh"
        )
        file_share_gitea_gitea_entrypoint_sh = FileShareFile(
            f"{self._name}_file_share_gitea_gitea_entrypoint_sh",
            FileShareFileProps(
                destination_path=gitea_entrypoint_sh_reader.name,
                share_name=file_share_gitea_gitea.name,
                file_contents=Output.secret(gitea_entrypoint_sh_reader.file_contents()),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=child_opts,
        )

        # Define the container group with guacd, guacamole and caddy
        container_group_gitea = containerinstance.ContainerGroup(
            f"{self._name}_container_group_gitea",
            container_group_name=f"{stack_name}-container-group-gitea",
            containers=[
                containerinstance.ContainerArgs(
                    image="caddy:latest",
                    name=f"{stack_name[:35]}-container-group-gitea-caddy",  # maximum of 63 characters
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
                    name=f"{stack_name[:35]}-container-group-gitea-gitea",  # maximum of 63 characters
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
                ip=props.container_ip_address,
                ports=[
                    containerinstance.PortArgs(
                        port=80,
                        protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                    )
                ],
                type=containerinstance.ContainerGroupIpAddressType.PRIVATE,
            ),
            network_profile=containerinstance.ContainerGroupNetworkProfileArgs(
                id=props.network_profile_id,
            ),
            os_type=containerinstance.OperatingSystemTypes.LINUX,
            resource_group_name=props.user_services_resource_group_name,
            restart_policy=containerinstance.ContainerGroupRestartPolicy.ALWAYS,
            sku=containerinstance.ContainerGroupSku.STANDARD,
            volumes=[
                containerinstance.VolumeArgs(
                    azure_file=containerinstance.AzureFileVolumeArgs(
                        share_name=file_share_gitea_caddy.name,
                        storage_account_key=props.storage_account_key,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="caddy-etc-caddy",
                ),
                containerinstance.VolumeArgs(
                    azure_file=containerinstance.AzureFileVolumeArgs(
                        share_name=file_share_gitea_gitea.name,
                        storage_account_key=props.storage_account_key,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="gitea-app-custom",
                ),
            ],
            opts=ResourceOptions.merge(
                ResourceOptions(
                    depends_on=[
                        file_share_gitea_caddy_caddyfile,
                        file_share_gitea_gitea_configure_sh,
                        file_share_gitea_gitea_entrypoint_sh,
                    ]
                ),
                child_opts,
            ),
        )

        # Register this in the SRE private DNS zone
        gitea_private_record_set = network.PrivateRecordSet(
            f"{self._name}_gitea_private_record_set",
            a_records=[
                network.ARecordArgs(
                    ipv4_address=props.container_ip_address,
                )
            ],
            private_zone_name=Output.concat("privatelink.", props.sre_fqdn),
            record_type="A",
            relative_record_set_name="gitea",
            resource_group_name=props.networking_resource_group_name,
            ttl=3600,
            opts=child_opts,
        )
        # Redirect the public DNS to private DNS
        gitea_public_record_set = network.RecordSet(
            f"{self._name}_gitea_public_record_set",
            cname_record=network.CnameRecordArgs(
                cname=Output.concat("gitea.privatelink.", props.sre_fqdn)
            ),
            record_type="CNAME",
            relative_record_set_name="gitea",
            resource_group_name=props.networking_resource_group_name,
            ttl=3600,
            zone_name=props.sre_fqdn,
            opts=child_opts,
        )
