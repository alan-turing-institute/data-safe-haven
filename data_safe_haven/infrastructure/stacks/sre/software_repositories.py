"""Pulumi component for SRE monitoring"""

from collections.abc import Mapping

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import containerinstance, storage

from data_safe_haven.infrastructure.common import (
    get_ip_address_from_container_group,
)
from data_safe_haven.infrastructure.components import (
    FileShareFile,
    FileShareFileProps,
    LocalDnsRecordComponent,
    LocalDnsRecordProps,
)
from data_safe_haven.resources import resources_path
from data_safe_haven.utility import FileReader, SoftwarePackageCategory


class SRESoftwareRepositoriesProps:
    """Properties for SRESoftwareRepositoriesComponent"""

    def __init__(
        self,
        dns_resource_group_name: Input[str],
        dns_server_ip: Input[str],
        location: Input[str],
        networking_resource_group_name: Input[str],
        nexus_admin_password: Input[str],
        software_packages: SoftwarePackageCategory,
        sre_fqdn: Input[str],
        storage_account_key: Input[str],
        storage_account_name: Input[str],
        storage_account_resource_group_name: Input[str],
        subnet_id: Input[str],
        user_services_resource_group_name: Input[str],
    ) -> None:
        self.dns_resource_group_name = dns_resource_group_name
        self.dns_server_ip = dns_server_ip
        self.location = location
        self.networking_resource_group_name = networking_resource_group_name
        self.nexus_admin_password = Output.secret(nexus_admin_password)
        self.nexus_packages: str | None = {
            SoftwarePackageCategory.ANY: "all",
            SoftwarePackageCategory.PRE_APPROVED: "selected",
            SoftwarePackageCategory.NONE: None,
        }[software_packages]
        self.user_services_resource_group_name = user_services_resource_group_name
        self.sre_fqdn = sre_fqdn
        self.storage_account_key = storage_account_key
        self.storage_account_name = storage_account_name
        self.storage_account_resource_group_name = storage_account_resource_group_name
        self.subnet_id = subnet_id


class SRESoftwareRepositoriesComponent(ComponentResource):
    """Deploy SRE update servers with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SRESoftwareRepositoriesProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:sre:SoftwareRepositoriesComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Define configuration file shares
        file_share_caddy = storage.FileShare(
            f"{self._name}_file_share_caddy",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="software-repositories-caddy",
            share_quota=1,
            signed_identifiers=[],
            opts=child_opts,
        )
        file_share_nexus = storage.FileShare(
            f"{self._name}_file_share_nexus",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="software-repositories-nexus",
            share_quota=5120,
            signed_identifiers=[],
            opts=child_opts,
        )
        file_share_nexus_allowlists = storage.FileShare(
            f"{self._name}_file_share_nexus_allowlists",
            access_tier="TransactionOptimized",
            account_name=props.storage_account_name,
            resource_group_name=props.storage_account_resource_group_name,
            share_name="software-repositories-nexus-allowlists",
            share_quota=1,
            signed_identifiers=[],
            opts=child_opts,
        )

        # Upload Caddyfile
        caddyfile_reader = FileReader(
            resources_path / "software_repositories" / "caddy" / "Caddyfile"
        )
        FileShareFile(
            f"{self._name}_file_share_caddyfile",
            FileShareFileProps(
                destination_path=caddyfile_reader.name,
                share_name=file_share_caddy.name,
                file_contents=Output.secret(caddyfile_reader.file_contents()),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=file_share_caddy)
            ),
        )

        # Upload Nexus allowlists
        cran_reader = FileReader(
            resources_path / "software_repositories" / "allowlists" / "cran.allowlist"
        )
        FileShareFile(
            f"{self._name}_file_share_cran_allowlist",
            FileShareFileProps(
                destination_path=cran_reader.name,
                share_name=file_share_nexus_allowlists.name,
                file_contents=cran_reader.file_contents(),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=file_share_nexus)
            ),
        )
        pypi_reader = FileReader(
            resources_path / "software_repositories" / "allowlists" / "pypi.allowlist"
        )
        FileShareFile(
            f"{self._name}_file_share_pypi_allowlist",
            FileShareFileProps(
                destination_path=pypi_reader.name,
                share_name=file_share_nexus_allowlists.name,
                file_contents=pypi_reader.file_contents(),
                storage_account_key=props.storage_account_key,
                storage_account_name=props.storage_account_name,
            ),
            opts=ResourceOptions.merge(
                child_opts, ResourceOptions(parent=file_share_nexus)
            ),
        )

        # Define the container group with nexus and caddy
        if props.nexus_packages:
            container_group = containerinstance.ContainerGroup(
                f"{self._name}_container_group",
                container_group_name=f"{stack_name}-container-group-software-repositories",
                containers=[
                    containerinstance.ContainerArgs(
                        image="caddy:2.7.6",
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
                        image="sonatype/nexus3:3.67.1",
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
                        image="ghcr.io/alan-turing-institute/nexus-allowlist:v0.9.0",
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
                            # Use fallback updating method due to issue with changes to
                            # files on Azure storage mount not being recognised by entr
                            containerinstance.EnvironmentVariableArgs(
                                name="ENTR_FALLBACK",
                                value="1",
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
                dns_config=containerinstance.DnsConfigurationArgs(
                    name_servers=[props.dns_server_ip],
                ),
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
                resource_group_name=props.user_services_resource_group_name,
                restart_policy=containerinstance.ContainerGroupRestartPolicy.ALWAYS,
                sku=containerinstance.ContainerGroupSku.STANDARD,
                subnet_ids=[
                    containerinstance.ContainerGroupSubnetIdArgs(id=props.subnet_id)
                ],
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
                opts=ResourceOptions.merge(
                    child_opts,
                    ResourceOptions(
                        delete_before_replace=True, replace_on_changes=["containers"]
                    ),
                ),
                tags=child_tags,
            )

            # Register the container group in the SRE DNS zone
            LocalDnsRecordComponent(
                f"{self._name}_nexus_dns_record_set",
                LocalDnsRecordProps(
                    base_fqdn=props.sre_fqdn,
                    public_dns_resource_group_name=props.networking_resource_group_name,
                    private_dns_resource_group_name=props.dns_resource_group_name,
                    private_ip_address=get_ip_address_from_container_group(
                        container_group
                    ),
                    record_name="nexus",
                ),
                opts=ResourceOptions.merge(
                    child_opts, ResourceOptions(parent=container_group)
                ),
            )
