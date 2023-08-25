"""Deploy with Pulumi"""
import os
import pathlib
import shutil
import subprocess
import time
from contextlib import suppress
from importlib import metadata
from typing import Any

from pulumi import automation

from data_safe_haven.config import Config
from data_safe_haven.exceptions import DataSafeHavenPulumiError
from data_safe_haven.external import AzureApi, AzureCli
from data_safe_haven.infrastructure.stacks import DeclarativeSHM, DeclarativeSRE
from data_safe_haven.utility import LoggingSingleton


class PulumiStack:
    """Interact with infrastructure using Pulumi"""

    def __init__(
        self,
        config: Config,
        program: DeclarativeSHM | DeclarativeSRE,
    ) -> None:
        self.cfg: Config = config
        self.env_: dict[str, Any] | None = None
        self.logger = LoggingSingleton()
        self.stack_: automation.Stack | None = None
        self.stack_outputs_: automation.OutputMap | None = None
        self.options: dict[str, tuple[str, bool, bool]] = {}
        self.program = program
        self.stack_name = self.program.stack_name
        self.work_dir = config.work_directory / "pulumi" / self.program.short_name
        self.work_dir.mkdir(parents=True, exist_ok=True)
        self.login()  # Log in to the Pulumi backend

    @property
    def local_stack_path(self) -> pathlib.Path:
        """Return the local stack path"""
        return self.work_dir / f"Pulumi.{self.stack_name}.yaml"

    @property
    def env(self) -> dict[str, Any]:
        """Get necessary Pulumi environment variables"""
        if not self.env_:
            azure_api = AzureApi(self.cfg.subscription_name)
            backend_storage_account_keys = azure_api.get_storage_account_keys(
                self.cfg.backend.resource_group_name,
                self.cfg.backend.storage_account_name,
            )
            self.env_ = {
                "AZURE_STORAGE_ACCOUNT": self.cfg.backend.storage_account_name,
                "AZURE_STORAGE_KEY": str(backend_storage_account_keys[0].value),
                "AZURE_KEYVAULT_AUTH_VIA_CLI": "true",
            }
        return self.env_

    @property
    def stack(self) -> automation.Stack:
        """Load the Pulumi stack, creating if needed."""
        if not self.stack_:
            self.logger.info(f"Creating/loading stack [green]{self.stack_name}[/].")
            try:
                self.stack_ = automation.create_or_select_stack(
                    project_name="data_safe_haven",
                    stack_name=self.stack_name,
                    program=self.program.run,
                    opts=automation.LocalWorkspaceOptions(
                        secrets_provider=f"azurekeyvault://{self.cfg.backend.key_vault_name}.vault.azure.net/keys/{self.cfg.pulumi.encryption_key_name}/{self.cfg.pulumi.encryption_key_id}",
                        work_dir=str(self.work_dir),
                        env_vars=self.env,
                    ),
                )
                self.logger.info(f"Loaded stack [green]{self.stack_name}[/].")
            except automation.CommandError as exc:
                msg = f"Could not load Pulumi stack {self.stack_name}.\n{exc}"
                raise DataSafeHavenPulumiError(msg) from exc
        return self.stack_

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

    def copy_option(self, name: str, other_stack: "PulumiStack") -> None:
        """Copy a public configuration option from another Pulumi stack"""
        self.add_option(name, other_stack.secret(name), replace=True)

    def copy_secret(self, name: str, other_stack: "PulumiStack") -> None:
        """Copy a secret configuration option from another Pulumi stack"""
        self.add_secret(name, other_stack.secret(name), replace=True)

    def deploy(self) -> None:
        """Deploy the infrastructure with Pulumi."""
        try:
            self.initialise_workdir()
            self.install_plugins()
            self.apply_config_options()
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
                        color="always", on_output=self.logger.info, parallel=1
                    )
                    self.evaluate(result.summary.result)
                    break
                except automation.CommandError as exc:
                    if any(
                        error in str(exc)
                        for error in (
                            "NetworkProfileAlreadyInUseWithContainerNics",
                            "InUseSubnetCannotBeDeleted",
                        )
                    ):
                        time.sleep(10)
                    else:
                        raise
            if self.stack_:
                self.stack_.workspace.remove_stack(self.stack_name)
        except automation.CommandError as exc:
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

    def initialise_workdir(self) -> None:
        """Create project directory if it does not exist and update local stack."""
        try:
            self.logger.info("Initialising Pulumi work directory")
            self.logger.debug(f"Ensuring that [green]{self.work_dir}[/] exists...")
            if not self.work_dir.exists():
                self.work_dir.mkdir(parents=True)
            self.logger.info(f"Ensured that [green]{self.work_dir}[/] exists.")
            # If stack information is saved in the config file then apply it here
            if self.stack_name in self.cfg.pulumi.stacks.keys():
                self.logger.info(
                    f"Updating stack [green]{self.stack_name}[/] information from config"
                )
                self.cfg.write_stack(self.stack_name, self.local_stack_path)
        except Exception as exc:
            msg = f"Initialising Pulumi working directory failed.\n{exc}."
            raise DataSafeHavenPulumiError(msg) from exc

    def install_plugins(self) -> None:
        """For inline programs, we must manage plugins ourselves."""
        try:
            self.logger.info("Installing required Pulumi plugins")
            self.stack.workspace.install_plugin(
                "azure-native", metadata.version("pulumi-azure-native")
            )
        except Exception as exc:
            msg = f"Installing Pulumi plugins failed.\n{exc}."
            raise DataSafeHavenPulumiError(msg) from exc

    def login(self) -> None:
        """Login to Pulumi."""
        try:
            # Ensure we are authenticated with the Azure CLI
            # Without this, we cannot read the encryption key from the keyvault
            AzureCli().login()
            # Check whether we're already logged in
            # Note that we cannot retrieve self.stack without being logged in
            self.logger.debug("Logging into Pulumi")
            with suppress(DataSafeHavenPulumiError):
                result = self.stack.workspace.who_am_i()
                if result.user:
                    self.logger.info(f"Logged into Pulumi as [green]{result.user}[/]")
                    return
            # Otherwise log in to Pulumi
            try:
                process = subprocess.run(
                    [
                        "pulumi",
                        "login",
                        f"azblob://{self.cfg.pulumi.storage_container_name}",
                    ],
                    capture_output=True,
                    check=True,
                    cwd=self.work_dir,
                    encoding="UTF-8",
                    env={**os.environ, **self.env},
                )
                self.logger.info(process.stdout)
            except (subprocess.CalledProcessError, FileNotFoundError) as exc:
                msg = f"Logging into Pulumi failed.\n{exc}."
                raise DataSafeHavenPulumiError(msg) from exc
        except Exception as exc:
            msg = f"Logging into Pulumi failed.\n{exc}."
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
                self.stack.preview(
                    color="always", diff=True, on_output=self.logger.info
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

    def remove_workdir(self) -> None:
        """Remove project directory if it exists."""
        try:
            self.logger.info(f"Removing [green]{self.work_dir}[/]...")
            if self.work_dir.exists():
                shutil.rmtree(self.work_dir)
            self.logger.info(f"Removed [green]{self.work_dir}[/].")
        except Exception as exc:
            msg = f"Removing Pulumi working directory failed.\n{exc}."
            raise DataSafeHavenPulumiError(msg) from exc

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

    def teardown(self) -> None:
        """Teardown the infrastructure deployed with Pulumi."""
        try:
            self.initialise_workdir()
            self.install_plugins()
            self.refresh()
            self.destroy()
            self.remove_workdir()
        except Exception as exc:
            msg = f"Tearing down Pulumi infrastructure failed.\n{exc}."
            raise DataSafeHavenPulumiError(msg) from exc

    def update(self) -> None:
        """Update deployed infrastructure."""
        try:
            self.logger.info(f"Applying changes to stack [green]{self.stack.name}[/].")
            result = self.stack.up(color="always", on_output=self.logger.info)
            self.evaluate(result.summary.result)
        except automation.CommandError as exc:
            msg = f"Pulumi update failed.\n{exc}"
            raise DataSafeHavenPulumiError(msg) from exc


class PulumiSHMStack(PulumiStack):
    """Interact with an SHM using Pulumi"""

    def __init__(
        self,
        config: Config,
    ) -> None:
        """Constructor"""
        super().__init__(config, DeclarativeSHM(config, config.shm.name))


class PulumiSREStack(PulumiStack):
    """Interact with an SRE using Pulumi"""

    def __init__(
        self,
        config: Config,
        sre_name: str,
    ) -> None:
        """Constructor"""
        super().__init__(config, DeclarativeSRE(config, config.shm.name, sre_name))
