"""Pulumi component for SRE identity"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, network, resources, storage

from data_safe_haven.infrastructure.common import (
    get_id_from_subnet,
    get_ip_address_from_container_group,
)
from data_safe_haven.infrastructure.components import (
    AzureADApplication,
    AzureADApplicationProps,
    LocalDnsRecordComponent,
    LocalDnsRecordProps,
)


class SREIdentityProps:
    """Properties for SREIdentityComponent"""

    def __init__(
        self,
        aad_application_name: Input[str],
        aad_auth_token: Input[str],
        aad_tenant_id: Input[str],
        dns_resource_group_name: Input[str],
        dns_server_ip: Input[str],
        location: Input[str],
        networking_resource_group_name: Input[str],
        shm_fqdn: Input[str],
        sre_fqdn: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group_name: Input[str],
        subnet_containers: Input[network.GetSubnetResult],
    ) -> None:
        self.aad_application_name = aad_application_name
        self.aad_auth_token = aad_auth_token
        self.aad_tenant_id = aad_tenant_id
        self.dns_resource_group_name = dns_resource_group_name
        self.dns_server_ip = dns_server_ip
        self.location = location
        self.networking_resource_group_name = networking_resource_group_name
        self.shm_fqdn = shm_fqdn
        self.sre_fqdn = sre_fqdn
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.storage_account_resource_group_name = storage_account_resource_group_name
        self.subnet_containers_id = Output.from_input(subnet_containers).apply(
            get_id_from_subnet
        )


class SREIdentityComponent(ComponentResource):
    """Deploy SRE backup with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SREIdentityProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:IdentityComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # The port that the server will be hosted on
        self.server_port = 1389

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-identity",
            opts=child_opts,
            tags=child_tags,
        )

        # Define configuration file share
        file_share = storage.FileShare(
            f"{self._name}_file_share",
            access_tier=storage.ShareAccessTier.COOL,
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="identity-redis",
            share_quota=5,
            signed_identifiers=[],
            opts=child_opts,
        )

        # Define AzureAD application
        aad_application = AzureADApplication(
            f"{self._name}_aad_application",
            AzureADApplicationProps(
                application_name=props.aad_application_name,
                application_role_assignments=["User.Read.All", "GroupMember.Read.All"],
                application_secret_name="Apricot Authentication Secret",
                auth_token=props.aad_auth_token,
                delegated_role_assignments=["User.Read.All"],
                public_client_redirect_uri="urn:ietf:wg:oauth:2.0:oob",
            ),
            opts=child_opts,
        )

        # Define the LDAP server container group with Apricot
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"{stack_name}-container-group-identity",
            containers=[
                containerinstance.ContainerArgs(
                    image="ghcr.io/alan-turing-institute/apricot:0.0.5",
                    name="apricot",
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="BACKEND",
                            value="MicrosoftEntra",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CLIENT_ID",
                            value=aad_application.application_id,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CLIENT_SECRET",
                            secure_value=aad_application.application_secret,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="DEBUG",
                            value="true",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="DOMAIN",
                            value=props.shm_fqdn,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="ENTRA_TENANT_ID",
                            value=props.aad_tenant_id,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="REDIS_HOST",
                            value="localhost",
                        ),
                    ],
                    # All Azure Container Instances need to expose port 80 on at least
                    # one container even if there's nothing behind it.
                    ports=[
                        containerinstance.ContainerPortArgs(
                            port=80,
                            protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                        ),
                        containerinstance.ContainerPortArgs(
                            port=self.server_port,
                            protocol=containerinstance.ContainerGroupNetworkProtocol.TCP,
                        ),
                    ],
                    resources=containerinstance.ResourceRequirementsArgs(
                        requests=containerinstance.ResourceRequestsArgs(
                            cpu=1,
                            memory_in_gb=1,
                        ),
                    ),
                    volume_mounts=[],
                ),
                containerinstance.ContainerArgs(
                    image="redis:7.2.4",
                    name="redis",
                    environment_variables=[],
                    ports=[
                        containerinstance.ContainerPortArgs(
                            port=6379,
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
                            mount_path="/data",
                            name="identity-redis-data",
                            read_only=False,
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
                        port=self.server_port,
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
                    id=props.subnet_containers_id
                )
            ],
            volumes=[
                containerinstance.VolumeArgs(
                    azure_file=containerinstance.AzureFileVolumeArgs(
                        share_name=file_share.name,
                        storage_account_key=props.storage_account_key,
                        storage_account_name=props.storage_account_name,
                    ),
                    name="identity-redis-data",
                ),
            ],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    delete_before_replace=True,
                    replace_on_changes=["containers"],
                ),
            ),
            tags=child_tags,
        )

        # Register the container group in the SRE DNS zone
        local_dns = LocalDnsRecordComponent(
            f"{self._name}_dns_record_set",
            LocalDnsRecordProps(
                base_fqdn=props.sre_fqdn,
                public_dns_resource_group_name=props.networking_resource_group_name,
                private_dns_resource_group_name=props.dns_resource_group_name,
                private_ip_address=get_ip_address_from_container_group(container_group),
                record_name="identity",
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=container_group)
            ),
        )

        # Register outputs
        self.hostname = local_dns.hostname
