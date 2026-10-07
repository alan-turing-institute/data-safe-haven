"""Command group for managing package allowlists"""

from pathlib import Path
from typing import Annotated, Optional

import typer

from data_safe_haven import console
from data_safe_haven.allowlist import Allowlist
from data_safe_haven.config import ContextManager, DSHPulumiConfig, SREConfig
from data_safe_haven.exceptions import DataSafeHavenConfigError, DataSafeHavenError
from data_safe_haven.external import AzureSdk
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.logging import get_logger
from data_safe_haven.resources import resources_path
from data_safe_haven.types import AllowlistRepository, SoftwarePackageCategory
from data_safe_haven.utility import FileReader

allowlist_command_group = typer.Typer()


def is_allowlist_required(sre_config: SREConfig) -> tuple[bool, str]:
    """Validates if the SRE configuration requires an allowlist."""

    is_required: bool = True
    reason: str = "A package allowlist is required for this SRE."

    if sre_config.sre.software_packages == SoftwarePackageCategory.ANY:
        is_required = False
        reason = (
            "No package allowlist is required for this SRE. All packages are allowed."
        )

    elif sre_config.sre.software_packages == SoftwarePackageCategory.NONE:
        is_required = False
        reason = (
            "No package allowlist is required for this SRE. No packages are allowed."
        )

    return is_required, reason


@allowlist_command_group.command()
def show(
    name: Annotated[
        str,
        typer.Argument(help="Name of SRE to show allowlist for."),
    ],
    repository: Annotated[
        AllowlistRepository,
        typer.Argument(help="Name of the repository to show the allowlist for."),
    ],
    file: Annotated[
        Optional[str],  # noqa: UP045
        typer.Option(help="File path to write the allowlist to."),
    ] = None,
) -> None:
    """Print the current package allowlist"""
    logger = get_logger()

    try:
        context = ContextManager.from_file().assert_context()
    except DataSafeHavenConfigError as exc:
        logger.critical(
            "No context is selected. Use `dsh context add` to create a context "
            "or `dsh context switch` to select one."
        )
        raise typer.Exit(1) from exc

    sre_config = SREConfig.from_remote_by_name(context, name)
    allowlist_required, reason = is_allowlist_required(sre_config)
    if not allowlist_required:
        logger.info(reason)
        raise typer.Exit()

    # Load Pulumi config
    pulumi_config = DSHPulumiConfig.from_remote(context)

    if sre_config.name not in pulumi_config.project_names:
        msg = f"Could not load Pulumi settings for '{sre_config.name}'. Have you deployed the SRE?"
        logger.error(msg)
        raise typer.Exit(1)

    sre_stack = SREProjectManager(
        context=context,
        config=sre_config,
        pulumi_config=pulumi_config,
    )

    azure_sdk = AzureSdk(subscription_name=context.subscription_name)
    context.subscription_name = azure_sdk.get_subscription_name(
        sre_config.azure.subscription_id
    )

    try:
        allowlist = Allowlist.from_remote(
            context=context, repository=repository, sre_stack=sre_stack
        )
    except DataSafeHavenError as exc:
        logger.critical(
            "No allowlist is configured. Use `dsh allowlist upload` to create one."
        )
        raise typer.Exit(1) from exc

    if file:
        with open(file, "w") as f:
            f.write(allowlist.allowlist)
    else:
        console.print(allowlist.allowlist)


@allowlist_command_group.command()
def template(
    repository: Annotated[
        AllowlistRepository,
        typer.Argument(help="Name of the repository to show the allowlist for."),
    ],
    file: Annotated[
        Optional[Path],  # noqa: UP045
        typer.Option(help="File path to write allowlist template to."),
    ] = None,
) -> None:
    """Print a template for the package allowlist"""

    template_reader = FileReader(
        resources_path
        / "software_repositories"
        / "allowlists"
        / f"{repository.value}.allowlist"
    )
    example_allowlist = template_reader.file_contents()
    if file:
        with open(file, "w") as f:
            f.write(example_allowlist)
        raise typer.Exit()
    else:
        console.print(example_allowlist)


@allowlist_command_group.command()
def upload(
    name: Annotated[
        str,
        typer.Argument(help="Name of SRE to upload the allowlist for."),
    ],
    file: Annotated[
        Path,
        typer.Argument(help="Path to the allowlist file to upload."),
    ],
    repository: Annotated[
        AllowlistRepository,
        typer.Argument(help="Repository type of the allowlist."),
    ],
    force: Annotated[  # noqa: FBT002
        bool,
        typer.Option(help="Skip check for existing remote allowlist."),
    ] = False,
) -> None:
    """Upload a package allowlist"""
    context = ContextManager.from_file().assert_context()
    logger = get_logger()

    if file.is_file():
        with open(file) as f:
            allowlist = f.read()
    else:
        logger.critical(f"Allowlist file '{file}' not found.")
        raise typer.Exit(1)
    sre_config = SREConfig.from_remote_by_name(context, name)

    allowlist_required, reason = is_allowlist_required(sre_config)
    if not allowlist_required:
        logger.info(reason)
        raise typer.Exit()

    # Load Pulumi config
    pulumi_config = DSHPulumiConfig.from_remote(context)

    if sre_config.name not in pulumi_config.project_names:
        msg = f"Could not load Pulumi settings for '{sre_config.name}'. Have you deployed the SRE?"
        logger.error(msg)
        raise typer.Exit(1)

    sre_stack = SREProjectManager(
        context=context,
        config=sre_config,
        pulumi_config=pulumi_config,
    )

    local_allowlist = Allowlist(
        repository=repository, sre_stack=sre_stack, allowlist=allowlist
    )

    azure_sdk = AzureSdk(subscription_name=context.subscription_name)
    context.subscription_name = azure_sdk.get_subscription_name(
        sre_config.azure.subscription_id
    )

    if not force and Allowlist.remote_exists(
        context=context,
        repository=repository,
        sre_stack=sre_stack,
    ):
        remote_allowlist = Allowlist.from_remote(
            context=context,
            repository=repository,
            sre_stack=sre_stack,
        )
        if allow_diff := local_allowlist.diff(remote_allowlist):
            for line in list(filter(None, "\n".join(allow_diff).splitlines())):
                logger.info(line)
            if not console.confirm(
                f"An allowlist already exists for {repository.name}. Do you want to overwrite it?",
                default_to_yes=True,
            ):
                raise typer.Exit()
        else:
            console.print("No changes, won't upload allowlist.")
            raise typer.Exit()
    try:
        logger.info(f"Uploading allowlist for {repository.name} to {sre_config.name}")
        local_allowlist.upload(context=context)
    except DataSafeHavenError as exc:
        logger.error(f"Failed to upload allowlist: {exc}")
        raise typer.Exit(1) from exc
