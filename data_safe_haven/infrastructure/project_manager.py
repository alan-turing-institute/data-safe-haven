"""Deploy with Pulumi"""

import logging
import time
from collections.abc import MutableMapping
from contextlib import suppress
from importlib import metadata
from shutil import which
from typing import Any

from pulumi import automation
from pulumi.automation import ConfigValue

from data_safe_haven.config import Config, DSHPulumiConfig, DSHPulumiProject
from data_safe_haven.context import Context
from data_safe_haven.exceptions import (
    DataSafeHavenAzureError,
    DataSafeHavenConfigError,
    DataSafeHavenPulumiError,
)
from data_safe_haven.external import AzureApi, AzureCliSingleton
from data_safe_haven.functions import replace_separators
from data_safe_haven.utility import LoggingSingleton

from .programs import DeclarativeSHM, DeclarativeSRE


class PulumiAccount:
    """Manage and interact with Pulumi backend account"""

    def __init__(self, context: Context, config: Config):
        self.context = context
        self.cfg = config
        self.env_: dict[str, Any] | None = None
        path = which("pulumi")
        if path is None:
            msg = "Unable to find Pulumi CLI executable in your path.\nPlease ensure that Pulumi is installed"
            raise DataSafeHavenPulumiError(msg)

        # Ensure Azure CLI account is correct
        # This will be needed to populate env
        AzureCliSingleton().confirm()

    @property
    def env(self) -> dict[str, Any]:
        """Get necessary Pulumi environment variables"""
        if not self.env_:
            azure_api = AzureApi(self.context.subscription_name)
            backend_storage_account_keys = azure_api.get_storage_account_keys(
                self.context.resource_group_name,
                self.context.storage_account_name,
            )
            self.env_ = {
                "AZURE_STORAGE_ACCOUNT": self.context.storage_account_name,
                "AZURE_STORAGE_KEY": str(backend_storage_account_keys[0].value),
                "AZURE_KEYVAULT_AUTH_VIA_CLI": "true",
            }
        return self.env_


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
        config: Config,
        pulumi_config: DSHPulumiConfig,
        pulumi_project_name: str,
        program: DeclarativeSHM | DeclarativeSRE,
        *,
        create_project: bool,
    ) -> None:
        self.context = context
        self.cfg = config
        self.pulumi_config = pulumi_config
        self.pulumi_project_name = pulumi_project_name
        self.program = program
        self.create_project = create_project

        self.account = PulumiAccount(context, config)
        self.logger = LoggingSingleton()
        self._stack: automation.Stack | None = None
        self.stack_outputs_: automation.OutputMap | None = None
        self.options: dict[str, tuple[str, bool, bool]] = {}
        self.project_name = replace_separators(context.tags["project"].lower(), "-")
        self._pulumi_project: DSHPulumiProject | None = None
        self.stack_name = self.program.stack_name

        self.install_plugins()

    @property
    def pulumi_extra_args(self) -> dict[str, Any]:
        extra_args: dict[str, Any] = {}
        if self.logger.isEnabledFor(logging.DEBUG):
            extra_args["debug"] = True
            extra_args["log_to_std_err"] = True
            extra_args["log_verbosity"] = 9
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
                    msg = f"No SHM/SRE named {self.pulumi_project_name} is defined.\n{exc}"
                    raise DataSafeHavenConfigError(msg) from exc
        return self._pulumi_project

    @property
    def stack(self) -> automation.Stack:
        """Load the Pulumi stack, creating if needed."""
        if not self._stack:
            self.logger.info(f"Creating/loading stack [green]{self.stack_name}[/].")
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
                self.update_dsh_pulumi_config()
            except automation.CommandError as exc:
                msg = f"Could not load Pulumi stack {self.stack_name}.\n{exc}"
                raise DataSafeHavenPulumiError(msg) from exc
        return self._stack

    def add_option(self, name: str, value: str, *, replace: bool) -> None:
        """Add a public configuration option"""
        self.options[name] = (value, False, replace)

    def add_secret(self, name: str, value: str, *, replace: bool) -> None:
        """Add a secret configuration option if it does not exist"""
        self.options[name] = (value, True, replace)

    def apply_config_options(self) -> None:
        """Set Pulumi config options"""
        try:
            self.logger.info("Updating Pulumi configuration")
            for name, (value, is_secret, replace) in self.options.items():
                if replace:
                    self.set_config(name, value, secret=is_secret)
                else:
                    self.ensure_config(name, value, secret=is_secret)
            self.options = {}
        except Exception as exc:
            msg = f"Applying Pulumi configuration options failed.\n{exc}."
            raise DataSafeHavenPulumiError(msg) from exc

    def cancel(self) -> None:
        """Cancel ongoing Pulumi operation."""
        try:
            self.logger.warning(
                f"Cancelling ongoing Pulumi operation for stack [green]{self.stack.name}[/]."
            )
            self.stack.cancel()
        except automation.CommandError:
            self.logger.error(
                f"No ongoing Pulumi operation found for stack [green]{self.stack.name}[/]."
            )

    def copy_option(self, name: str, other_stack: "ProjectManager") -> None:
        """Copy a public configuration option from another Pulumi stack"""
        self.add_option(name, other_stack.secret(name), replace=True)

    def copy_secret(self, name: str, other_stack: "ProjectManager") -> None:
        """Copy a secret configuration option from another Pulumi stack"""
        self.add_secret(name, other_stack.secret(name), replace=True)

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
            msg = f"Pulumi deployment failed.\n{exc}"
            raise DataSafeHavenPulumiError(msg) from exc

    def destroy(self) -> None:
        """Destroy deployed infrastructure."""
        try:
            # Note that the first iteration can fail due to failure to delete container NICs
            # See https://github.com/MicrosoftDocs/azure-docs/issues/20737 for details
            while True:
                try:
                    result = self.stack.destroy(
                        color="always",
                        debug=self.logger.isEnabledFor(logging.DEBUG),
                        log_flow=True,
                        on_output=self.logger.info,
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
                        msg = f"Pulumi resource destruction failed.\n{exc}"
                        raise DataSafeHavenPulumiError(msg) from exc
            # Remove stack JSON
            try:
                self.logger.info(f"Removing Pulumi stack [green]{self.stack_name}[/].")
                if self._stack:
                    self._stack.workspace.remove_stack(self.stack_name)
            except automation.CommandError as exc:
                if "no stack named" not in str(exc):
                    msg = f"Pulumi stack could not be removed.\n{exc}"
                    raise DataSafeHavenPulumiError(msg) from exc
            # Remove stack JSON backup
            stack_backup_name = f"{self.stack_name}.json.bak"
            try:
                self.logger.info(
                    f"Removing Pulumi stack backup [green]{stack_backup_name}[/]."
                )
                azure_api = AzureApi(self.context.subscription_name)
                azure_api.remove_blob(
                    blob_name=f".pulumi/stacks/{self.project_name}/{stack_backup_name}",
                    resource_group_name=self.context.resource_group_name,
                    storage_account_name=self.context.storage_account_name,
                    storage_container_name=self.context.pulumi_storage_container_name,
                )
            except DataSafeHavenAzureError as exc:
                if "blob does not exist" in str(exc):
                    self.logger.warning(
                        f"Pulumi stack backup [green]{stack_backup_name}[/] could not be found."
                    )
                else:
                    msg = f"Pulumi stack backup could not be removed.\n{exc}"
                    raise DataSafeHavenPulumiError(msg) from exc
        except DataSafeHavenPulumiError as exc:
            msg = f"Pulumi destroy failed.\n{exc}"
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

    def install_plugins(self) -> None:
        """For inline programs, we must manage plugins ourselves."""
        try:
            self.logger.info("Installing required Pulumi plugins")
            self.stack.workspace.install_plugin(
                "azure-native", metadata.version("pulumi-azure-native")
            )
            self.stack.workspace.install_plugin(
                "random", metadata.version("pulumi-random")
            )
        except Exception as exc:
            msg = f"Installing Pulumi plugins failed.\n{exc}."
            raise DataSafeHavenPulumiError(msg) from exc

    def output(self, name: str) -> Any:
        """Get a named output value from a stack"""
        if not self.stack_outputs_:
            self.stack_outputs_ = self.stack.outputs()
        return self.stack_outputs_[name].value

    def preview(self) -> None:
        """Preview the Pulumi stack."""
        try:
            self.logger.info(
                f"Previewing changes for stack [green]{self.stack.name}[/]."
            )
            with suppress(automation.CommandError):
                # Note that we disable parallelisation which can cause deadlock
                self.stack.preview(
                    color="always",
                    diff=True,
                    log_flow=True,
                    on_output=self.logger.info,
                    parallel=1,
                    **self.pulumi_extra_args,
                )
        except Exception as exc:
            msg = f"Pulumi preview failed.\n{exc}."
            raise DataSafeHavenPulumiError(msg) from exc

    def refresh(self) -> None:
        """Refresh the Pulumi stack."""
        try:
            self.logger.info(f"Refreshing stack [green]{self.stack.name}[/].")
            # Note that we disable parallelisation which can cause deadlock
            self.stack.refresh(color="always", parallel=1)
        except automation.CommandError as exc:
            msg = f"Pulumi refresh failed.\n{exc}"
            raise DataSafeHavenPulumiError(msg) from exc

    def run_pulumi_command(self, command: str) -> None:
        # command = automation.PulumiCommand()
        # result = command.run(
        #     command.split(),
        #     self.stack.workspace.work_dir,
        #     self.env_vars
        # )
        self.stack._run_pulumi_cmd_sync(command.split())

    def secret(self, name: str) -> str:
        """Read a secret from the Pulumi stack."""
        try:
            return str(self.stack.get_config(name).value)
        except automation.CommandError as exc:
            msg = f"Secret '{name}' was not found."
            raise DataSafeHavenPulumiError(msg) from exc

    def set_config(self, name: str, value: str, *, secret: bool) -> None:
        """Set config values, overwriting any existing value."""
        self.stack.set_config(name, automation.ConfigValue(value=value, secret=secret))
        self.update_dsh_pulumi_project()

    def teardown(self) -> None:
        """Teardown the infrastructure deployed with Pulumi."""
        try:
            self.refresh()
            self.destroy()
            self.update_dsh_pulumi_project()
        except Exception as exc:
            msg = f"Tearing down Pulumi infrastructure failed.\n{exc}."
            raise DataSafeHavenPulumiError(msg) from exc

    def update(self) -> None:
        """Update deployed infrastructure."""
        try:
            self.logger.info(f"Applying changes to stack [green]{self.stack.name}[/].")
            result = self.stack.up(
                color="always",
                log_flow=True,
                on_output=self.logger.info,
                **self.pulumi_extra_args,
            )
            self.evaluate(result.summary.result)
            self.update_dsh_pulumi_project()
        except automation.CommandError as exc:
            msg = f"Pulumi update failed.\n{exc}"
            raise DataSafeHavenPulumiError(msg) from exc

    @property
    def stack_all_config(self) -> MutableMapping[str, ConfigValue]:
        stack_all_config: MutableMapping[str, ConfigValue] = self.stack.get_all_config()
        return stack_all_config

    def update_dsh_pulumi_project(self) -> None:
        """Update persistent data in the DSHPulumiProject object"""
        all_config_dict = {
            key: item.value for key, item in self.stack_all_config.items()
        }
        self.pulumi_project.stack_config = all_config_dict

    def update_dsh_pulumi_config(self) -> None:
        """Update persistent data in the DSHPulumiProject object"""
        stack_key = self.stack.workspace.stack_settings(
            stack_name=self.stack_name
        ).encrypted_key

        if self.pulumi_config.encrypted_key is None:
            self.pulumi_config.encrypted_key = stack_key
        elif self.pulumi_config.encrypted_key != stack_key:
            msg = "Stack encrypted key does not match project encrypted key"
            raise DataSafeHavenPulumiError(msg)


class SHMProjectManager(ProjectManager):
    """Interact with an SHM using Pulumi"""

    def __init__(
        self,
        context: Context,
        config: Config,
        pulumi_config: DSHPulumiConfig,
        *,
        create_project: bool = False,
    ) -> None:
        """Constructor"""
        super().__init__(
            context,
            config,
            pulumi_config,
            context.shm_name,
            DeclarativeSHM(context, config, context.shm_name),
            create_project=create_project,
        )


class SREProjectManager(ProjectManager):
    """Interact with an SRE using Pulumi"""

    def __init__(
        self,
        context: Context,
        config: Config,
        pulumi_config: DSHPulumiConfig,
        *,
        create_project: bool = False,
        sre_name: str,
        graph_api_token: str | None = None,
    ) -> None:
        """Constructor"""
        token = graph_api_token if graph_api_token else ""
        super().__init__(
            context,
            config,
            pulumi_config,
            sre_name,
            DeclarativeSRE(context, config, context.shm_name, sre_name, token),
            create_project=create_project,
        )
