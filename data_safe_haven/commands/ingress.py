"""Command group for managing data ingress"""

import ipaddress
from datetime import UTC, datetime, timedelta
from typing import Annotated, Optional

import typer
from azure.storage.blob import ContainerSasPermissions

from data_safe_haven import console
from data_safe_haven.config import ContextManager, DSHPulumiConfig, SREConfig
from data_safe_haven.exceptions import DataSafeHavenConfigError, DataSafeHavenError
from data_safe_haven.external import AzureSdk
from data_safe_haven.functions import current_ip_address, ip_address_in_list
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.logging import get_logger
from data_safe_haven.validators import typer_ip_address

ingress_command_group = typer.Typer()

DATETIME_FORMATS = ["%Y-%m-%d", "%Y-%m-%dT%H:%M", "%Y-%m-%dT%H:%M:%S"]
# User delegation keys are valid for at most 7 days
MAX_SAS_VALIDITY = timedelta(days=7)


@ingress_command_group.command()
def create_sas(
    name: Annotated[
        str,
        typer.Argument(help="Name of SRE to create an ingress SAS token for."),
    ],
    ip: Annotated[
        str,
        typer.Option(
            callback=typer_ip_address,
            help="IP address or CIDR range that the data provider will upload from.",
        ),
    ],
    end: Annotated[
        datetime,
        typer.Option(
            formats=DATETIME_FORMATS,
            help="Time (UTC) at which the SAS token expires.",
        ),
    ],
    start: Annotated[
        Optional[datetime],  # noqa: UP045
        typer.Option(
            formats=DATETIME_FORMATS,
            help="Time (UTC) from which the SAS token is valid. Defaults to now.",
        ),
    ] = None,
) -> None:
    """Create a SAS token for uploading data to the ingress container of an SRE."""
    logger = get_logger()

    now = datetime.now(UTC)
    start_utc = start.replace(tzinfo=UTC) if start else now
    end_utc = end.replace(tzinfo=UTC)
    if end_utc <= start_utc:
        msg = "The end time must be after the start time."
        raise typer.BadParameter(msg, param_hint="'--end'")
    if end_utc <= now:
        msg = "The end time must be in the future."
        raise typer.BadParameter(msg, param_hint="'--end'")
    if end_utc > now + MAX_SAS_VALIDITY:
        msg = f"The end time must be at most {MAX_SAS_VALIDITY.days} days from now."
        raise typer.BadParameter(msg, param_hint="'--end'")

    try:
        context = ContextManager.from_file().assert_context()
        sre_config = SREConfig.from_remote_by_name(context, name)
        pulumi_config = DSHPulumiConfig.from_remote(context)

        if sre_config.name not in pulumi_config.project_names:
            msg = f"Could not load Pulumi settings for '{sre_config.name}'. Have you deployed the SRE?"
            logger.error(msg)
            raise DataSafeHavenConfigError(msg)

        # Check whether current IP address is authorised to take administrator actions
        if not ip_address_in_list(sre_config.sre.admin_ip_addresses):
            logger.warning(
                f"IP address '{current_ip_address()}' is not authorised to manage SRE '{sre_config.description}'."
            )
            msg = "Check that 'admin_ip_addresses' is set correctly in your SRE config file."
            raise DataSafeHavenConfigError(msg)

        sre_stack = SREProjectManager(
            context=context,
            config=sre_config,
            pulumi_config=pulumi_config,
        )
        resource_group_name = sre_stack.output("sre_resource_group")
        try:
            storage_account_name = sre_stack.output("data")[
                "storage_account_data_private_sensitive_name"
            ]
        except KeyError as exc:
            msg = f"Could not find the sensitive data storage account for '{sre_config.name}'. Redeploy the SRE with `dsh sre deploy`."
            logger.error(msg)
            raise DataSafeHavenConfigError(msg) from exc

        # The storage account is in the SRE subscription
        sre_subscription_name = AzureSdk(
            context.subscription_name
        ).get_subscription_name(sre_config.azure.subscription_id)
        azure_sdk = AzureSdk(sre_subscription_name)
        azure_sdk.ensure_storage_account_ip_rule(
            ip, resource_group_name, storage_account_name
        )
        sas_url = azure_sdk.generate_container_sas_url(
            "ingress",
            storage_account_name,
            expiry=end_utc,
            ip_address=ip,
            permissions=ContainerSasPermissions(write=True, list=True),
            start=start_utc,
        )
    except DataSafeHavenError as exc:
        logger.critical(
            f"Could not create an ingress SAS token for SRE '[green]{name}[/]'."
        )
        raise typer.Exit(code=1) from exc

    # Rules for IPs in the SRE config are managed by Pulumi
    ip_network = ipaddress.IPv4Network(ip)
    if not any(
        ip_network.subnet_of(ipaddress.IPv4Network(provider_ip))
        for provider_ip in sre_config.sre.data_provider_ip_addresses
    ):
        logger.warning(
            f"IP address '{ip}' was added to the storage account firewall outside Pulumi."
            " It will be removed the next time you run `dsh sre deploy`."
        )
    console.print(
        f"Ingress SAS URL for SRE '[green]{name}[/]', valid from"
        f" {start_utc.isoformat()} to {end_utc.isoformat()} for IP address '{ip}':"
    )
    console.print(sas_url, soft_wrap=True)
