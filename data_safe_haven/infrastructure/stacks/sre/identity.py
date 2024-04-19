"""Pulumi component for SRE identity"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, network, resources, storage

from data_safe_haven.infrastructure.common import (
    get_ip_address_from_container_group,
)
from data_safe_haven.infrastructure.components import (
    AzureADApplication,
    AzureADApplicationProps,
)


class SREIdentityProps:
    """Properties for SREIdentityComponent"""

    def __init__(
        self,
        aad_application_name: Input[str],
        aad_auth_token: Input[str],
        aad_tenant_id: Input[str],
        location: Input[str],
        shm_fqdn: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group_name: Input[str],
        subnet_containers: Input[network.GetSubnetResult],
    ) -> None:
        self.aad_application_name = aad_application_name
        self.aad_auth_token = aad_auth_token
        self.aad_tenant_id = aad_tenant_id
        self.location = location
        self.shm_fqdn = shm_fqdn
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.storage_account_resource_group_name = storage_account_resource_group_name
        self.subnet_containers_id = Output.from_input(subnet_containers).apply(
            lambda s: str(s.id)
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

        # Define configuration file shares
        file_share_redis = storage.FileShare(
            f"{self._name}_file_share_redis",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="identity-redis",
            share_quota=5120,
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
                        share_name=file_share_redis.name,
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

        # Register outputs
        self.ip_address = get_ip_address_from_container_group(container_group)
