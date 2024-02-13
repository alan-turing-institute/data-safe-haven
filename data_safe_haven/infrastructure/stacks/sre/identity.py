"""Pulumi component for SRE identity"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, network, resources


class SREIdentityProps:
    """Properties for SREIdentityComponent"""

    def __init__(
        self,
        location: Input[str],
        subnet_containers: Input[network.GetSubnetResult]
    ) -> None:
        self.location = location
        self.subnet_containers_id = Output.from_input(subnet_containers).apply(lambda s: str(s.id))


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

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-identity",
            opts=child_opts,
            tags=child_tags,
        )

        # Define the LDAP server container group with Apricot
        container_group = containerinstance.ContainerGroup(
            f"{self._name}_container_group",
            container_group_name=f"{stack_name}-container-group-identity",
            containers=[
                containerinstance.ContainerArgs(
                    image="ghcr.io/alan-turing-institute/apricot:0.0.4",
                    name="apricot",
                    environment_variables=[
                        containerinstance.EnvironmentVariableArgs(
                            name="BACKEND",
                            value="MicrosoftEntra",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CLIENT_ID",
                            value="MicrosoftEntra",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="CLIENT_SECRET",
                            value="MicrosoftEntra",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="DOMAIN",
                            value="MicrosoftEntra",
                        ),
                        containerinstance.EnvironmentVariableArgs(
                            name="ENTRA_TENANT_ID",
                            value="MicrosoftEntra",
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
                            port=1389,
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
                        # containerinstance.VolumeMountArgs(
                        #     mount_path="/opt/adguardhome/custom",
                        #     name="adguard-opt-adguardhome-custom",
                        #     read_only=True,
                        # ),
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
            os_type=containerinstance.OperatingSystemTypes.LINUX,
            resource_group_name=resource_group.name,
            restart_policy=containerinstance.ContainerGroupRestartPolicy.ALWAYS,
            sku=containerinstance.ContainerGroupSku.STANDARD,
            subnet_ids=[containerinstance.ContainerGroupSubnetIdArgs(id=props.subnet_containers_id)],
            volumes=[],
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    delete_before_replace=True,
                    replace_on_changes=["containers"],
                ),
            ),
            tags=child_tags,
        )
