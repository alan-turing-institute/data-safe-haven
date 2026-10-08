"""Close temporary external access to sensitive-data ingress storage."""

from ipaddress import IPv4Network
from typing import Annotated

import typer

from data_safe_haven import console
from data_safe_haven.config import ContextManager, DSHPulumiConfig, SREConfig
from data_safe_haven.exceptions import DataSafeHavenError
from data_safe_haven.external import AzureSdk
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.infrastructure.programs.sre.data import (
    sensitive_data_storage_account_name,
)
from data_safe_haven.logging import get_logger

ingress_command_group = typer.Typer()


@ingress_command_group.command("close-firewall")
def close_firewall(
    name: Annotated[str, typer.Argument(help="Name of the SRE.")],
    ip: Annotated[
        str,
        typer.Option(
            "--ip",
            help="Exact IPv4 address or CIDR rule to remove from ingress storage.",
        ),
    ],
) -> None:
    """Revoke an external ingress IP rule without changing unrelated rules."""
    logger = get_logger()
    try:
        target = IPv4Network(ip, strict=False)
    except ValueError as exc:
        msg = "Expected an IPv4 address or CIDR range."
        raise typer.BadParameter(msg, param_hint="--ip") from exc

    try:
        context = ContextManager.from_file().assert_context()
        config = SREConfig.from_remote_by_name(context, name)
        # The administrator's own firewall entries must not be removed by
        # an ingress-cleanup command, even if a CIDR overlaps one.
        for admin_ip in config.sre.admin_ip_addresses:
            if IPv4Network(str(admin_ip), strict=False).subnet_of(target):
                logger.error(
                    "Refusing to remove a firewall rule covering a configured administrator IP."
                )
                raise typer.Exit(1)

        pulumi_config = DSHPulumiConfig.from_remote(context)
        if name not in pulumi_config.project_names:
            logger.error(f"No deployed SRE named '{name}' was found.")
            raise typer.Exit(1)

        stack = SREProjectManager(
            context=context, config=config, pulumi_config=pulumi_config
        )
        resource_group_name = str(stack.output("sre_resource_group"))
        sensitive_account = sensitive_data_storage_account_name(stack.stack_name)
        sdk = AzureSdk(subscription_name=context.subscription_name)
        sdk = AzureSdk(
            subscription_name=sdk.get_subscription_name(config.azure.subscription_id)
        )
        if sdk.remove_storage_account_ip_rule(
            resource_group_name, sensitive_account, str(target)
        ):
            console.print(f"Removed ingress firewall rule {target}.")
        else:
            console.print(f"Ingress firewall rule {target} was already absent.")
    except DataSafeHavenError as exc:
        logger.error(f"Could not close ingress firewall for SRE '{name}': {exc}")
        raise typer.Exit(1) from exc
