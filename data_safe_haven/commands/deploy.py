"""Command-line application for deploying a Data Safe Haven component, delegating the details to a subcommand"""
from typing import Annotated, Optional

import typer

from data_safe_haven.functions import (
    validate_aad_guid,
    validate_azure_vm_sku,
    validate_email_address,
    validate_ip_address,
    validate_timezone,
)
from data_safe_haven.utility import DatabaseSystem, SoftwarePackageCategory

from .deploy_shm import deploy_shm
from .deploy_sre import deploy_sre

deploy_command_group = typer.Typer()


@deploy_command_group.command()
def shm(
    aad_tenant_id: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            "--aad-tenant-id",
            "-a",
            help=(
                "The tenant ID for the AzureAD where users will be created,"
                " for example '10de18e7-b238-6f1e-a4ad-772708929203'."
            ),
            callback=validate_aad_guid,
        ),
    ] = None,
    admin_email_address: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            "--email",
            "-e",
            help="The email address where your system deployers and administrators can be contacted.",
            callback=validate_email_address,
        ),
    ] = None,
    admin_ip_addresses: Annotated[
        Optional[list[str]],  # noqa: UP007
        typer.Option(
            "--ip-address",
            "-i",
            help=(
                "An IP address or range used by your system deployers and administrators."
                " [*may be specified several times*]"
            ),
            callback=lambda ips: [validate_ip_address(ip) for ip in ips],
        ),
    ] = None,
    fqdn: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            "--fqdn",
            "-f",
            help="The domain that SHM users will belong to.",
        ),
    ] = None,
    timezone: Annotated[
        Optional[str],  # noqa: UP007
        typer.Option(
            "--timezone",
            "-t",
            help="The timezone that this Data Safe Haven deployment will use.",
            callback=validate_timezone,
        ),
    ] = None,
) -> None:
    """Deploy a Safe Haven Management component"""
    deploy_shm(
        aad_tenant_id=aad_tenant_id,
        admin_email_address=admin_email_address,
        admin_ip_addresses=admin_ip_addresses,
        fqdn=fqdn,
        timezone=timezone,
    )


@deploy_command_group.command()
def sre(
    name: Annotated[str, typer.Argument(help="Name of SRE to deploy")],
    allow_copy: Annotated[
        Optional[bool],  # noqa: UP007
        typer.Option(
            "--allow-copy",
            "-c",
            help="Whether to allow text to be copied out of the SRE.",
        ),
    ] = None,
    allow_paste: Annotated[
        Optional[bool],  # noqa: UP007
        typer.Option(
            "--allow-paste",
            "-p",
            help="Whether to allow text to be pasted into the SRE.",
        ),
    ] = None,
    data_provider_ip_addresses: Annotated[
        Optional[list[str]],  # noqa: UP007
        typer.Option(
            "--data-provider-ip-address",
            "-d",
            help="An IP address or range used by your data providers. [*may be specified several times*]",
            callback=lambda vms: [validate_ip_address(vm) for vm in vms],
        ),
    ] = None,
    databases: Annotated[
        Optional[list[DatabaseSystem]],  # noqa: UP007
        typer.Option(
            "--database",
            "-b",
            help="Make a database of this system available to users of this SRE.",
        ),
    ] = None,
    software_packages: Annotated[
        Optional[SoftwarePackageCategory],  # noqa: UP007
        typer.Option(
            "--software-packages",
            "-s",
            help="The category of package to allow users to install from enabled software repositories.",
        ),
    ] = None,
    user_ip_addresses: Annotated[
        Optional[list[str]],  # noqa: UP007
        typer.Option(
            "--user-ip-address",
            "-u",
            help="An IP address or range used by your users. [*may be specified several times*]",
            callback=lambda ips: [validate_ip_address(ip) for ip in ips],
        ),
    ] = None,
    workspace_skus: Annotated[
        Optional[list[str]],  # noqa: UP007
        typer.Option(
            "--workspace-sku",
            "-w",
            help=(
                "A virtual machine SKU to make available to your users as a workspace."
                " [*may be specified several times*]"
            ),
            callback=lambda ips: [validate_azure_vm_sku(ip) for ip in ips],
        ),
    ] = None,
) -> None:
    """Deploy a Secure Research Environment"""
    deploy_sre(
        name,
        allow_copy=allow_copy,
        allow_paste=allow_paste,
        data_provider_ip_addresses=data_provider_ip_addresses,
        databases=databases,
        software_packages=software_packages,
        user_ip_addresses=user_ip_addresses,
        workspace_skus=workspace_skus,
    )
