from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, resources, storage

from data_safe_haven.functions import allowed_dns_lookups
from data_safe_haven.infrastructure.common import (
    get_id_from_subnet,
    get_ip_address_from_container_group,
)
from data_safe_haven.infrastructure.components import (
    FileShareFile,
    FileShareFileProps,
    LocalDnsRecordComponent,
    LocalDnsRecordProps,
)


class SREAptProxyServerProps:
    """Properties for SREAptProxyServerComponent"""

    def __init__(
        self,
        containers_subnet: Input[str],
        dns_resource_group_name: Input[str],
        dns_server_ip: Input[str],
        location: Input[str],
        networking_resource_group_name: Input[str],
        sre_fqdn: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group_name: Input[str],
    ) -> None:
        self.containers_subnet_id = Output.from_input(containers_subnet).apply(
            get_id_from_subnet
        )
        self.dns_resource_group_name = dns_resource_group_name
        self.dns_server_ip = dns_server_ip
        self.location = location
        self.networking_resource_group_name = networking_resource_group_name
        self.sre_fqdn = sre_fqdn
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.storage_account_resource_group_name = storage_account_resource_group_name


class SREAptProxyServerComponent(ComponentResource):
    """Deploy APT proxy server with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREAptProxyServerProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:AptProxyServerComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-apt-proxy-server",
            opts=child_opts,
            tags=child_tags,
        )

        # Define configuration file shares
        file_share_apt_proxy_server = storage.FileShare(
            f"{self._name}_file_share_apt_proxy_server",
            access_tier=storage.ShareAccessTier.COOL,
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="apt-proxy-server",
            share_quota=1,
            signed_identifiers=[],
            opts=child_opts,
        )

        # Upload allowed repositories
        # reader = FileReader(resources_path / "apt_proxy_server" / "repositories.acl")
        repositories = "\n".join(allowed_dns_lookups("apt_repositories"))
        file_share_apt_proxy_server_repositories = FileShareFile(
            f"{self._name}_file_share_apt_proxy_server_repositories",
            FileShareFileProps(
                destination_path="repositories.acl",
                share_name=file_share_apt_proxy_server.name,
                file_contents=repositories,
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=file_share_apt_proxy_server)
            ),
        )

        # Define the container group with squid-deb-proxy
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"{stack_name}-container-group-apt-proxy-server",
            containers=[
                containerinstance.ContainerArgs(
                    image="ghcr.io/alan-turing-institute/squid-deb-proxy:main",
                    name="squid-deb-proxy"[:63],
                    environment_variables=[],
                    # All Azure Container Instances need to expose port 80 on at least
                    # one container. In this case, there is nothing there.
                    ports=[
                        containerinstance.ContainerPortArgs(
                            port=80,
                            protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                        ),
                        containerinstance.ContainerPortArgs(
                            port=8000,
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
                            mount_path="/app/allowlists",
                            name="proxy-app-allowlists",
                            read_only=True,
                        ),
                    ],
                ),
            ],
            dns_config=containerinstance.DnsConfigurationArgs(
                name_servers=[props.dns_server_ip],
            ),
            ip_address=containerinstance.IpAddressArgs(
                ports=[
                    containerinstance.PortArgs(
                        port=80,
                        protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                    ),
                    containerinstance.PortArgs(
                        port=8000,
                        protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                    ),
                ],
                type=containerinstance.ContainerGroupIpAddressType.PRIVATE,
            ),
            os_type=containerinstance.OperatingSystemTypes.LINUX,
            resource_group_name=resource_group.name,
            restart_policy=containerinstance.ContainerGroupRestartPolicy.ALWAYS,
            sku=containerinstance.ContainerGroupSku.STANDARD,
            subnet_ids=[
                containerinstance.ContainerGroupSubnetIdArgs(
                    id=props.containers_subnet_id
                )
            ],
            volumes=[
                containerinstance.VolumeArgs(
                    azure_file=containerinstance.AzureFileVolumeArgs(
                        share_name=file_share_apt_proxy_server.name,
                        storage_account_key=props.storage_account_key,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="proxy-app-allowlists",
                ),
            ],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    delete_before_replace=True,
                    depends_on=[
                        file_share_apt_proxy_server,
                        file_share_apt_proxy_server_repositories,
                    ],
                    replace_on_changes=["containers"],
                ),
            ),
            tags=child_tags,
        )

        # Register the container group in the SRE DNS zone
        local_dns = LocalDnsRecordComponent(
            f"{self._name}_apt_proxy_server_dns_record_set",
            LocalDnsRecordProps(
                base_fqdn=props.sre_fqdn,
                public_dns_resource_group_name=props.networking_resource_group_name,
                private_dns_resource_group_name=props.dns_resource_group_name,
                private_ip_address=get_ip_address_from_container_group(container_group),
                record_name="apt",
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=container_group)
            ),
        )

        # Register outputs
        self.hostname = local_dns.hostname
