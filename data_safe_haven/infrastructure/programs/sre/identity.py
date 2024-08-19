"""Pulumi component for SRE identity"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, network, storage

from data_safe_haven.infrastructure.common import (
    DockerHubCredentials,
    get_id_from_subnet,
    get_ip_address_from_container_group,
)
from data_safe_haven.infrastructure.components import (
    EntraApplication,
    EntraApplicationProps,
    LocalDnsRecordComponent,
    LocalDnsRecordProps,
)


class SREIdentityProps:
    """Properties for SREIdentityComponent"""

    def __init__(
        self,
        dns_server_ip: Input[str],
        dockerhub_credentials: DockerHubCredentials,
        entra_application_name: Input[str],
        entra_auth_token: str,
        entra_tenant_id: Input[str],
        location: Input[str],
        resource_group_name: Input[str],
        shm_fqdn: Input[str],
        sre_fqdn: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        subnet_containers: Input[network.GetSubnetResult],
    ) -> None:
        self.dns_server_ip = dns_server_ip
        self.dockerhub_credentials = dockerhub_credentials
        self.entra_application_name = entra_application_name
        self.entra_auth_token = entra_auth_token
        self.entra_tenant_id = entra_tenant_id
        self.location = location
        self.resource_group_name = resource_group_name
        self.shm_fqdn = shm_fqdn
        self.sre_fqdn = sre_fqdn
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
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
        child_tags = {"component": "identity"} | (tags if tags else {})

        # The port that the server will be hosted on
        self.server_port = 1389

        # Define configuration file share
        file_share = storage.FileShare(
            f"{self._name}_file_share",
            access_tier=storage.ShareAccessTier.TRANSACTION_OPTIMIZED,
            account_name=props.storage_account_name,
            resource_group_name=props.resource_group_name,
            share_name="identity-redis",
            share_quota=1,
            signed_identifiers=[],
            opts=child_opts,
        )

        # Define Entra ID application
        entra_application = EntraApplication(
            f"{self._name}_entra_application",
            EntraApplicationProps(
                application_name=props.entra_application_name,
                application_role_assignments=["User.Read.All", "GroupMember.Read.All"],
                application_secret_name="Apricot Authentication Secret",
                delegated_role_assignments=["User.Read.All"],
                public_client_redirect_uri="urn:ietf:wg:oauth:2.0:oob",
            ),
            auth_token=props.entra_auth_token,
            opts=child_opts,
        )

        # Define the LDAP server container group with Apricot
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"{stack_name}-container-group-identity",
            containers=[
                containerinstance.ContainerArgs(
                    image="ghcr.io/alan-turing-institute/apricot:0.0.7",
                    name="apricot",
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="BACKEND",
                            value="MicrosoftEntra",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CLIENT_ID",
                            value=entra_application.application_id,
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CLIENT_SECRET",
                            secure_value=entra_application.application_secret,
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
                            value=props.entra_tenant_id,
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
                    image="redis:7.4.0",
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
            # Required due to DockerHub rate-limit: https://docs.docker.com/docker-hub/download-rate-limit/
            image_registry_credentials=[
                {
                    "password": Output.secret(props.dockerhub_credentials.access_token),
                    "server": props.dockerhub_credentials.server,
                    "username": props.dockerhub_credentials.username,
                }
            ],
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
            location=props.location,
            os_type=containerinstance.OperatingSystemTypes.LINUX,
            resource_group_name=props.resource_group_name,
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
                private_ip_address=get_ip_address_from_container_group(container_group),
                record_name="identity",
                resource_group_name=props.resource_group_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=container_group)
            ),
        )

        # Register outputs
        self.hostname = local_dns.hostname
