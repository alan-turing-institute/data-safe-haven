"""Command for creating SAS tokens for SRE storage containers"""

import ipaddress
from datetime import UTC, datetime, timedelta
from typing import Annotated, Optional

import typer
from azure.storage.blob import ContainerSasPermissions
from packaging.version import Version

from data_safe_haven import console
from data_safe_haven.config import ContextManager, DSHPulumiConfig, SREConfig
from data_safe_haven.exceptions import DataSafeHavenConfigError, DataSafeHavenError
from data_safe_haven.external import AzureSdk
from data_safe_haven.functions import current_ip_address, ip_address_in_list
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.logging import get_logger
from data_safe_haven.types import StorageContainer
from data_safe_haven.validators import typer_ip_address

DATETIME_FORMATS = ["%Y-%m-%d", "%Y-%m-%dT%H:%M", "%Y-%m-%dT%H:%M:%S"]
# User delegation keys are valid for at most 7 days
MAX_SAS_VALIDITY = timedelta(days=7)
# SREs deployed with this version or earlier lack the storage account output
LATEST_UNSUPPORTED_SRE_VERSION = Version("5.8.0")


def create_sas(
    name: Annotated[
        str,
        typer.Argument(help="Name of SRE to create a SAS token for."),
    ],
    container: Annotated[
        StorageContainer,
        typer.Option(help="Storage container to create a SAS token for."),
    ],
    ip: Annotated[
        str,
        typer.Option(
            callback=typer_ip_address,
            help="IP address or CIDR range that will access the container.",
        ),
    ],
    start: Annotated[
        Optional[datetime],  # noqa: UP045
        typer.Option(
            formats=DATETIME_FORMATS,
            help="Time (UTC) from which the SAS token is valid. Defaults to now.",
        ),
    ] = None,
    end: Annotated[
        Optional[datetime],  # noqa: UP045
        typer.Option(
            formats=DATETIME_FORMATS,
            help="Time (UTC) at which the SAS token expires. Cannot be used with --hours.",
        ),
    ] = None,
    hours: Annotated[
        Optional[int],  # noqa: UP045
        typer.Option(
            min=1,
            help="Number of hours from the start time until the SAS token expires. Cannot be used with --end.",
        ),
    ] = None,
) -> None:
    """Create a SAS token for a storage container of an SRE."""
    logger = get_logger()

    now = datetime.now(UTC)
    start_utc = start.replace(tzinfo=UTC) if start else now
    if end and hours:
        msg = "Use either --end or --hours, not both."
        raise typer.BadParameter(msg, param_hint="'--end' / '--hours'")
    if end:
        end_utc = end.replace(tzinfo=UTC)
    elif hours:
        end_utc = start_utc + timedelta(hours=hours)
    else:
        msg = "Either --end or --hours is required."
        raise typer.BadParameter(msg, param_hint="'--end' / '--hours'")
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

        # The storage account is in the SRE subscription
        sre_subscription_name = AzureSdk(
            context.subscription_name
        ).get_subscription_name(sre_config.azure.subscription_id)
        azure_sdk = AzureSdk(sre_subscription_name)
        try:
            storage_account_name = sre_stack.output("data")[
                "storage_account_data_private_sensitive_name"
            ]
        except KeyError as exc:
            sre_version = azure_sdk.get_version(resource_group_name)
            if Version(sre_version) <= LATEST_UNSUPPORTED_SRE_VERSION:
                msg = f"SRE '{sre_config.name}' was deployed with Data Safe Haven version {sre_version}, but `dsh create-sas` only supports SREs deployed with a version later than {LATEST_UNSUPPORTED_SRE_VERSION}. Upgrade Data Safe Haven and redeploy the SRE with `dsh sre deploy`."
            else:
                msg = f"Could not find the sensitive data storage account for '{sre_config.name}'. Redeploy the SRE with `dsh sre deploy`."
            logger.error(msg)
            raise DataSafeHavenConfigError(msg) from exc

        azure_sdk.ensure_storage_account_ip_rule(
            ip, resource_group_name, storage_account_name
        )
        sas_url = azure_sdk.generate_container_sas_url(
            container,
            storage_account_name,
            expiry=end_utc,
            ip_address=ip,
            permissions=ContainerSasPermissions(write=True, list=True),
            start=start_utc,
        )
    except DataSafeHavenError as exc:
        logger.critical(
            f"Could not create a SAS token for container '{container}' of SRE '[green]{name}[/]'."
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
        f"SAS URL for container '{container}' of SRE '[green]{name}[/]', valid from"
        f" {start_utc.isoformat()} to {end_utc.isoformat()} for IP address '{ip}':"
    )
    console.print(sas_url, soft_wrap=True)
