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
from data_safe_haven.utility import SoftwarePackageCategory

from .deploy_shm import DeploySHMCommand
from .deploy_sre import DeploySRECommand

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
    DeploySHMCommand()(
        aad_tenant_id,
        admin_email_address,
        admin_ip_addresses,
        fqdn,
        timezone,
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
    research_desktops: Annotated[
        Optional[list[str]],  # noqa: UP007
        typer.Option(
            "--research-desktop",
            "-r",
            help=(
                "A virtual machine SKU to make available to your users as a research desktop."
                " [*may be specified several times*]"
            ),
            callback=lambda ips: [validate_azure_vm_sku(ip) for ip in ips],
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
) -> None:
    """Deploy a Secure Research Environment"""
    DeploySRECommand()(
        name,
        allow_copy,
        allow_paste,
        data_provider_ip_addresses,
        research_desktops,
        software_packages,
        user_ip_addresses,
    )
