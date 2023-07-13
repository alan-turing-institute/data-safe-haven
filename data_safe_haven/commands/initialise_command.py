"""Command-line application for initialising a Data Safe Haven deployment"""
# Standard library imports
import pathlib
import sys
from typing import Optional

# Third party imports
import typer
from typing_extensions import Annotated

# Local imports
from data_safe_haven.backend import Backend
from data_safe_haven.config import DotFileSettings
from data_safe_haven.exceptions import DataSafeHavenException
from data_safe_haven.functions import validate_aad_guid
from .base_command import BaseCommand


class InitialiseCommand(BaseCommand):
    """Initialise a Data Safe Haven deployment"""

    def entrypoint(
        self,
        admin_group: Annotated[
            Optional[str],
            typer.Option(
                "--admin-group",
                "-a",
                help="The ID of an Azure group containing all administrators.",
                callback=validate_aad_guid,
            ),
        ] = None,
        location: Annotated[
            Optional[str],
            typer.Option(
                "--location",
                "-l",
                help="The Azure location to deploy resources into.",
            ),
        ] = None,
        name: Annotated[
            Optional[str],
            typer.Option(
                "--deployment-name",
                "-d",
                help="The name to give this Data Safe Haven deployment.",
                callback=validate_aad_guid,
            ),
        ] = None,
        subscription: Annotated[
            Optional[str],
            typer.Option(
                "--subscription",
                "-s",
                help="The name of an Azure subscription to deploy resources into.",
            ),
        ] = None,
    ) -> None:
        """Typer command line entrypoint"""
        try:
            # Confirm project path
            project_base_path = pathlib.Path.cwd().resolve()
            if not self.logger.confirm(
                f"Do you want to initialise a Data Safe Haven project at [green]{project_base_path}[/]?",
                True,
            ):
                sys.exit(0)

            # Load settings from dotfiles
            settings = DotFileSettings(
                admin_group_id=admin_group,
                location=location,
                name=name,
                subscription_name=subscription,
            )

            # Ensure that the Pulumi backend exists
            backend = Backend(settings)
            backend.create()

            # Load the generated configuration object and upload it to blob storage
            config = backend.config
            config.upload()

            # Ensure that the project directory exists
            if not project_base_path.exists():
                self.logger.info(
                    f"Creating project directory '[green]{project_base_path}[/]'."
                )
                project_base_path.mkdir(parents=True)
            settings_path = settings.write(project_base_path)
            self.logger.info(f"Saved project settings to '[green]{settings_path}[/]'.")
        except DataSafeHavenException as exc:
            raise DataSafeHavenException(
                f"Could not initialise Data Safe Haven.\n{str(exc)}"
            ) from exc
