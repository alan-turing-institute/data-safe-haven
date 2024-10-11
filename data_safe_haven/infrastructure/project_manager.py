"""Manage Pulumi projects"""

import logging
import time
from contextlib import suppress
from importlib import metadata
from typing import Any

from pulumi import automation

from data_safe_haven.config import (
    Context,
    DSHPulumiConfig,
    DSHPulumiProject,
    SREConfig,
)
from data_safe_haven.exceptions import (
    DataSafeHavenAzureError,
    DataSafeHavenConfigError,
    DataSafeHavenError,
    DataSafeHavenPulumiError,
)
from data_safe_haven.external import AzureSdk, PulumiAccount
from data_safe_haven.functions import get_key_vault_name, replace_separators
from data_safe_haven.logging import get_console_handler, get_logger

from .programs import DeclarativeSRE


class ProjectManager:
    """
    Interact with DSH infrastructure using Pulumi

    Constructing a ProjectManager creates a Pulumi project, with a single stack. The
    Pulumi project's program corresponds to either an SHM or SRE. Methods provider a
    high level, DSH focused interface to call Pulumi operations on the project,
    including `pulumi up` and `pulumi destroy`.
    """

    def __init__(
        self,
        context: Context,
        pulumi_config: DSHPulumiConfig,
        pulumi_project_name: str,
        program: DeclarativeSRE,
        *,
        create_project: bool,
    ) -> None:
        self._options: dict[str, tuple[str, bool, bool]] = {}
        self._pulumi_project: DSHPulumiProject | None = None
        self._stack: automation.Stack | None = None
        self._stack_outputs: automation.OutputMap | None = None
        self.account = PulumiAccount(
            resource_group_name=context.resource_group_name,
            storage_account_name=context.storage_account_name,
            subscription_name=context.subscription_name,
        )
        self.context = context
        self.create_project = create_project
        self.logger = get_logger()
        self.program = program
        self.project_name = replace_separators(context.tags["project"].lower(), "-")
        self.pulumi_config = pulumi_config
        self.pulumi_project_name = pulumi_project_name
        self.stack_name = self.program.stack_name

    @property
    def pulumi_extra_args(self) -> dict[str, Any]:
        extra_args: dict[str, Any] = {}
        # Produce verbose Pulumi output if running in verbose mode
        if get_console_handler().level <= logging.DEBUG:
            extra_args["debug"] = True
            extra_args["log_to_std_err"] = True
            extra_args["log_verbosity"] = 9
        else:
            extra_args["debug"] = None
            extra_args["log_to_std_err"] = None
            extra_args["log_verbosity"] = None

        extra_args["color"] = "always"
        extra_args["log_flow"] = True
        extra_args["on_output"] = self.logger.info
        return extra_args

    @property
    def project_settings(self) -> automation.ProjectSettings:
        return automation.ProjectSettings(
            name="data-safe-haven",
            runtime="python",
            backend=automation.ProjectBackend(url=self.context.pulumi_backend_url),
        )

    @property
    def stack_settings(self) -> automation.StackSettings:
        return automation.StackSettings(
            config=self.pulumi_project.stack_config,
            encrypted_key=self.pulumi_config.encrypted_key,
            secrets_provider=self.context.pulumi_secrets_provider_url,
        )

    @property
    def pulumi_project(self) -> DSHPulumiProject:
        if not self._pulumi_project:
            # Create DSH Pulumi Project if it does not exist, otherwise use existing
            if self.create_project:
                self._pulumi_project = self.pulumi_config.create_or_select_project(
                    self.pulumi_project_name
                )
            else:
                try:
                    self._pulumi_project = self.pulumi_config[self.pulumi_project_name]
                except (KeyError, TypeError) as exc:
                    msg = f"No SRE named {self.pulumi_project_name} is defined."
                    raise DataSafeHavenConfigError(msg) from exc
        return self._pulumi_project

    @property
    def stack(self) -> automation.Stack:
        """Load the Pulumi stack, creating if needed."""
        if not self._stack:
            self.logger.debug(f"Creating/loading stack [green]{self.stack_name}[/].")
            try:
                self._stack = automation.create_or_select_stack(
                    opts=automation.LocalWorkspaceOptions(
                        env_vars=self.account.env,
                        project_settings=self.project_settings,
                        secrets_provider=self.context.pulumi_secrets_provider_url,
                        stack_settings={self.stack_name: self.stack_settings},
                    ),
                    program=self.program,
                    project_name=self.project_name,
                    stack_name=self.stack_name,
                )
                self.logger.info(f"Loaded stack [green]{self.stack_name}[/].")
                # Ensure encrypted key is stored in the Pulumi configuration
                self.update_dsh_pulumi_encrypted_key(self._stack.workspace)
                # Ensure workspace plugins are installed
                self.install_plugins(self._stack.workspace)
            except automation.CommandError as exc:
                self.log_exception(exc)
                msg = f"Could not load Pulumi stack {self.stack_name}."
                raise DataSafeHavenPulumiError(msg) from exc
        return self._stack

    def add_option(self, name: str, value: str, *, replace: bool) -> None:
        """Add a public configuration option"""
        self._options[name] = (value, False, replace)

    def add_secret(self, name: str, value: str, *, replace: bool) -> None:
        """Add a secret configuration option"""
        self._options[name] = (value, True, replace)

    def apply_config_options(self) -> None:
        """Set Pulumi config options"""
        try:
            self.logger.debug("Updating Pulumi configuration")
            for name, (value, is_secret, replace) in self._options.items():
                if replace:
                    self.set_config(name, value, secret=is_secret)
                else:
                    self.ensure_config(name, value, secret=is_secret)
            self._options = {}
        except Exception as exc:
            msg = "Applying Pulumi configuration options failed.."
            raise DataSafeHavenPulumiError(msg) from exc

    def cancel(self) -> None:
        """Cancel ongoing Pulumi operation."""
        try:
            self.logger.warning(
                f"Cancelling ongoing Pulumi operation for stack [green]{self.stack.name}[/]."
            )
            self.stack.cancel()
            self.logger.warning(
                f"Removing any ambiguous Pulumi resources from stack [green]{self.stack.name}[/]."
            )
            self.run_pulumi_command("refresh --clear-pending-creates --yes")
            self.logger.warning(
                "If you see '[bold]cannot create already existing resource[/]' errors, please manually delete these resources from Azure."
            )
        except automation.CommandError:
            self.logger.error(
                f"No ongoing Pulumi operation found for stack [green]{self.stack.name}[/]."
            )

    def cleanup(self) -> None:
        """Cleanup deployed infrastructure."""
        try:
            azure_sdk = AzureSdk(self.context.subscription_name)
            # Remove stack JSON
            try:
                self.logger.debug(f"Removing Pulumi stack [green]{self.stack_name}[/].")
                if self._stack:
                    self._stack.workspace.remove_stack(self.stack_name)
                    self.logger.info(
                        f"Removed Pulumi stack [green]{self.stack_name}[/]."
                    )
            except automation.CommandError as exc:
                self.log_exception(exc)
                if "no stack named" not in str(exc):
                    msg = "Pulumi stack could not be removed."
                    raise DataSafeHavenPulumiError(msg) from exc
            # Remove stack JSON backup
            try:
                stack_backup_name = f"{self.stack_name}.json.bak"
                self.logger.debug(
                    f"Removing Pulumi stack backup [green]{stack_backup_name}[/]."
                )
                if azure_sdk.blob_exists(
                    blob_name=f".pulumi/stacks/{self.project_name}/{stack_backup_name}",
                    resource_group_name=self.context.resource_group_name,
                    storage_account_name=self.context.storage_account_name,
                    storage_container_name=self.context.pulumi_storage_container_name,
                ):
                    azure_sdk.remove_blob(
                        blob_name=f".pulumi/stacks/{self.project_name}/{stack_backup_name}",
                        resource_group_name=self.context.resource_group_name,
                        storage_account_name=self.context.storage_account_name,
                        storage_container_name=self.context.pulumi_storage_container_name,
                    )
                    self.logger.info(
                        f"Removed Pulumi stack backup [green]{stack_backup_name}[/]."
                    )
            except DataSafeHavenAzureError as exc:
                if "blob does not exist" in str(exc):
                    self.logger.warning(
                        f"Pulumi stack backup [green]{stack_backup_name}[/] could not be removed."
                    )
                else:
                    msg = "Pulumi stack backup could not be removed."
                    raise DataSafeHavenPulumiError(msg) from exc
            # Purge the key vault, which otherwise blocks re-use of this SRE name
            key_vault_name = get_key_vault_name(self.stack_name)
            self.logger.debug(
                f"Attempting to purge Azure Key Vault [green]{key_vault_name}[/]."
            )
            if azure_sdk.purge_keyvault(
                key_vault_name, self.program.config.azure.location
            ):
                self.logger.info(f"Purged Azure Key Vault [green]{key_vault_name}[/].")
        except DataSafeHavenError as exc:
            msg = "Pulumi destroy failed."
            raise DataSafeHavenPulumiError(msg) from exc

    def deploy(self, *, force: bool = False) -> None:
        """Deploy the infrastructure with Pulumi."""
        try:
            self.apply_config_options()
            if force:
                self.cancel()
            self.refresh()
            self.preview()
            self.update()
        except Exception as exc:
            msg = "Pulumi deployment failed."
            raise DataSafeHavenPulumiError(msg) from exc

    def destroy(self) -> None:
        """Destroy deployed infrastructure."""
        try:
            # Note that the first iteration can fail due to failure to delete container NICs
            # See https://github.com/MicrosoftDocs/azure-docs/issues/20737 for details
            while True:
                try:
                    result = self.stack.destroy(
                        **self.pulumi_extra_args,
                    )
                    self.evaluate(result.summary.result)
                    break
                except automation.CommandError as exc:
                    if any(
                        error in str(exc)
                        for error in (
                            "Linked Service is used by a solution",
                            "NetworkProfileAlreadyInUseWithContainerNics",
                            "InUseSubnetCannotBeDeleted",
                        )
                    ):
                        time.sleep(10)
                    else:
                        self.log_exception(exc)
                        msg = "Pulumi resource destruction failed."
                        raise DataSafeHavenPulumiError(msg) from exc
        except DataSafeHavenError as exc:
            msg = "Pulumi destroy failed."
            raise DataSafeHavenPulumiError(msg) from exc

    def ensure_config(self, name: str, value: str, *, secret: bool) -> None:
        """Ensure that config values have been set, setting them if they do not exist"""
        try:
            self.stack.get_config(name)
        except automation.CommandError:
            self.set_config(name, value, secret=secret)

    def evaluate(self, result: str) -> None:
        """Evaluate a Pulumi operation."""
        if result == "succeeded":
            self.logger.info("Pulumi operation [green]succeeded[/].")
        else:
            self.logger.error("Pulumi operation [red]failed[/].")
            msg = "Pulumi operation failed."
            raise DataSafeHavenPulumiError(msg)

    def install_plugins(self, workspace: automation.Workspace) -> None:
        """For inline programs, we must manage plugins ourselves."""
        try:
            self.logger.debug("Installing required Pulumi plugins")
            workspace.install_plugin(
                "azure-native", metadata.version("pulumi-azure-native")
            )
            workspace.install_plugin("random", metadata.version("pulumi-random"))
        except Exception as exc:
            msg = "Installing Pulumi plugins failed.."
            raise DataSafeHavenPulumiError(msg) from exc

    def log_exception(self, exc: automation.CommandError) -> None:
        for error_line in str(exc).split("\n"):
            if any(word in error_line for word in ["error:", "stderr:"]):
                self.logger.critical(f"Pulumi error: {error_line}")

    def output(self, name: str) -> Any:
        """Get a named output value from a stack"""
        if not self._stack_outputs:
            self._stack_outputs = self.stack.outputs()
        return self._stack_outputs[name].value

    def preview(self) -> None:
        """Preview the Pulumi stack."""
        try:
            self.logger.info(
                f"Previewing changes for stack [green]{self.stack.name}[/]."
            )
            with suppress(automation.CommandError):
                # Note that we disable parallelisation which can cause deadlock
                self.stack.preview(
                    diff=True,
                    parallel=1,
                    **self.pulumi_extra_args,
                )
        except Exception as exc:
            msg = "Pulumi preview failed.."
            raise DataSafeHavenPulumiError(msg) from exc

    def refresh(self) -> None:
        """Refresh the Pulumi stack."""
        try:
            self.logger.info(f"Refreshing stack [green]{self.stack.name}[/].")
            # Note that we disable parallelisation which can cause deadlock
            self.stack.refresh(parallel=1, **self.pulumi_extra_args)
        except automation.CommandError as exc:
            self.log_exception(exc)
            msg = "Pulumi refresh failed."
            raise DataSafeHavenPulumiError(msg) from exc

    def run_pulumi_command(self, command: str) -> str:
        """Run a Pulumi non-interactive CLI command using this project and stack."""
        try:
            result = self.stack._run_pulumi_cmd_sync(command.split())
            return str(result.stdout)
        except automation.CommandError as exc:
            self.log_exception(exc)
            msg = f"Failed to run command '{command}'."
            raise DataSafeHavenPulumiError(msg) from exc

    def secret(self, name: str) -> str:
        """Read a secret from the Pulumi stack."""
        try:
            return str(self.stack.get_config(name).value)
        except automation.CommandError as exc:
            self.log_exception(exc)
            msg = f"Secret '{name}' was not found."
            raise DataSafeHavenPulumiError(msg) from exc

    def set_config(self, name: str, value: str, *, secret: bool) -> None:
        """Set config values, overwriting any existing value."""
        self.stack.set_config(name, automation.ConfigValue(value=value, secret=secret))
        self.update_dsh_pulumi_project()

    def teardown(self, *, force: bool = False) -> None:
        """Teardown the infrastructure deployed with Pulumi."""
        try:
            if force:
                self.cancel()
            self.refresh()
            self.destroy()
            self.cleanup()
        except Exception as exc:
            msg = "Tearing down Pulumi infrastructure failed.."
            raise DataSafeHavenPulumiError(msg) from exc

    def update(self) -> None:
        """Update deployed infrastructure."""
        try:
            self.logger.info(f"Applying changes to stack [green]{self.stack.name}[/].")
            result = self.stack.up(
                **self.pulumi_extra_args,
            )
            self.evaluate(result.summary.result)
            self.update_dsh_pulumi_project()
        except automation.CommandError as exc:
            self.log_exception(exc)
            msg = "Pulumi update failed."
            raise DataSafeHavenPulumiError(msg) from exc

    def update_dsh_pulumi_project(self) -> None:
        """Update persistent data in the DSHPulumiProject object"""
        all_config_dict = {
            key: item.value for key, item in self.stack.get_all_config().items()
        }
        self.pulumi_project.stack_config = all_config_dict

    def update_dsh_pulumi_encrypted_key(self, workspace: automation.Workspace) -> None:
        """Update encrypted key in the DSHPulumiProject object"""
        stack_key = workspace.stack_settings(stack_name=self.stack_name).encrypted_key

        if not self.pulumi_config.encrypted_key:
            self.pulumi_config.encrypted_key = stack_key
        elif self.pulumi_config.encrypted_key != stack_key:
            msg = "Stack encrypted key does not match project encrypted key"
            raise DataSafeHavenPulumiError(msg)


class SREProjectManager(ProjectManager):
    """Interact with an SRE using Pulumi"""

    def __init__(
        self,
        context: Context,
        config: SREConfig,
        pulumi_config: DSHPulumiConfig,
        *,
        create_project: bool = False,
        graph_api_token: str | None = None,
    ) -> None:
        """Constructor"""
        token = graph_api_token or ""
        super().__init__(
            context,
            pulumi_config,
            config.name,
            DeclarativeSRE(context, config, token),
            create_project=create_project,
        )
