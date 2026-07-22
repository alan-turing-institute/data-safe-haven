"""Handle any exceptional upgrade processes"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from azure.core.exceptions import (
    HttpResponseError,
    ResourceNotFoundError,
)
from packaging.version import Version

from data_safe_haven import console, version
from data_safe_haven.external import AzureSdk

if TYPE_CHECKING:
    from data_safe_haven.infrastructure import ProjectManager
from data_safe_haven.logging import get_logger


class UpgradeFailedError(Exception):
    pass


class UpgradeAbortedError(Exception):
    def __init__(self, message: str | None = None) -> None:
        if not message:
            message = "Deployment aborted."
        super().__init__(message)


class Upgrade:
    """Handle any exceptional upgrade processes"""

    proceed: bool | None = None

    def __init__(
        self, project_manager: ProjectManager, *args: Any, **kwargs: Any
    ) -> None:
        super().__init__(*args, **kwargs)
        self.logger = get_logger()
        self.project_manager = project_manager

    def can_proceed(self) -> bool:
        """Check whether or not a deployment can proceed based on its
        suitability for upgrade:
        1. If it's a downgrade, block the deployment.
        2. If it's a deploy to the same version, continue directly with
           the deployment.
        3. If it's an upgrade, warn and check with the user before
           proceeding.
        """
        self.fresh_deployment = False
        self.proceed = False
        self.dsh_version = Version(version.__version__)
        try:
            resource_group = self.project_manager.output("sre_resource_group")
        except KeyError:
            # The resource group doesn't exist, so this is a brand new deployment
            self.sre_version = Version("0.0.0")
            self.fresh_deployment = True
            self.proceed = True

        if not self.fresh_deployment:
            azure_sdk = AzureSdk(self.project_manager.context.subscription_name)
            self.sre_version = Version(azure_sdk.get_version(resource_group))

            if self.dsh_version == self.sre_version:
                self.proceed = True
            elif self.dsh_version < self.sre_version:
                self.logger.info(
                    f"You're using DSH version {self.dsh_version} but your SRE was deployed with a more recent version, {self.sre_version}. Deployment will be aborted."
                )
                self.proceed = False
            elif self.dsh_version > self.sre_version:
                self.logger.info(
                    f"You're using DSH version {self.dsh_version} but your SRE was deployed with version {self.sre_version}. Deployment will therefore trigger an upgrade."
                )
                if (self.sre_version < Version("5.8.0")) and (
                    self.dsh_version >= Version("5.8.0")
                ):
                    self.logger.info(
                        f"Upgrading to version {self.dsh_version} requires reprovisioning of several components. All of the data on the following will be lost during the upgrade:"
                    )
                    self.logger.info("1. Gitea database")
                    self.logger.info("2. Gitea mirror database")
                    self.logger.info("3. Hedgedoc database")
                    self.logger.info("4. Workspace datadrives")
                    self.logger.info(
                        "If you have non-duplicate data stored on any of these you should back them up before proceeding."
                    )
                self.proceed = console.confirm(
                    "Are you sure you wish to proceed with the upgrade?",
                    default_to_yes=False,
                )

        return self.proceed

    def prepare(self) -> bool:
        """Perform any steps needed to prepare a deployment for an upgrade
        by Pulumi to a new version.
        """
        changes = False

        if not self.proceed:
            raise UpgradeFailedError

        if self.fresh_deployment:
            changes = False
        elif self.dsh_version > self.sre_version:
            if (self.sre_version < Version("5.8.0")) and (
                self.dsh_version >= Version("5.8.0")
            ):
                changes = self.upgrade_to_5_8_0()

        return changes

    def upgrade_to_5_8_0(self) -> bool:
        """Upgrade from a version below 5.8.0 to a version at or above 5.8.0."""
        self.logger.info("Preparing SRE for upgrade to version 5.8.0")

        resource_group = self.project_manager.output("sre_resource_group")
        azure_sdk = AzureSdk(self.project_manager.context.subscription_name)

        database_server_names = [
            "db-server-gitea",
            "db-server-gitea-mirror",
            "db-server-hedgedoc",
        ]

        resources = []
        for database_server_name in database_server_names:
            endpoint = (
                f"{self.project_manager.stack_name}-{database_server_name}-endpoint"
            )
            self.logger.info(f"Searching for: {endpoint}")
            try:
                resource = azure_sdk.get_private_endpoint(resource_group, endpoint)
                resources.append(resource.id)
                self.logger.info(f"Discovered endpoint: {resource.id}")
            except ResourceNotFoundError:
                self.logger.info(f"Skipping non-existent endpoint: {endpoint}")
            except HttpResponseError as exc:
                self.logger.info(f"Skipping endpoint: {endpoint}: {exc}")

        vnet = f"{self.project_manager.stack_name}-vnet"
        subnet = "UserServicesContainersSupportSubnet"
        self.logger.info(f"Searching for subnet: {subnet}")
        try:
            resource = azure_sdk.get_subnet(resource_group, vnet, subnet)
            resources.append(resource.id)
            self.logger.info(f"Discovered subnet: {resource.id}")
        except ResourceNotFoundError:
            self.logger.info(f"Skipping non-existent subnet: {subnet}")
        except HttpResponseError as exc:
            self.logger.info(f"Skipping subnet: {subnet}: {exc}")

        # Delete the resources
        if len(resources) > 0:
            azure_sdk.delete_resources(resources)

        self.logger.info("Preparation complete, continuing with deployment.")
        return len(resources) > 0
