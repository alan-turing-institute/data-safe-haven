"""Deploy with Pulumi"""
# Standard library imports
import pathlib
import shutil
import subprocess
import time
from contextlib import suppress
from typing import Any, Dict, Optional, Tuple

# Third party imports
import yaml
from pulumi import automation

# Local imports
from data_safe_haven.config import Config
from data_safe_haven.exceptions import DataSafeHavenPulumiException
from data_safe_haven.mixins import LoggingMixin
from .declarative_shm import DeclarativeSHM
from .declarative_sre import DeclarativeSRE


class PulumiStack(LoggingMixin):
    """Interact with infrastructure using Pulumi"""

    options: Dict[str, Tuple[str, bool, bool]]
    program: DeclarativeSHM | DeclarativeSRE

    def __init__(
        self,
        config: Config,
        deployment_type: str,
        *args: Optional[Any],
        sre_name: Optional[str] = None,
        **kwargs: Optional[Any],
    ):
        super().__init__(*args, **kwargs)
        self.cfg: Config = config
        self.env_: Optional[Dict[str, Any]] = None
        self.stack_: Optional[automation.Stack] = None
        self.options = {}
        if deployment_type == "SHM":
            self.program = DeclarativeSHM(config, config.shm.name)
        elif deployment_type == "SRE":
            if not sre_name:
                raise DataSafeHavenPulumiException("No sre_name was provided.")
            self.program = DeclarativeSRE(config, config.shm.name, sre_name)
        else:
            raise DataSafeHavenPulumiException(
                f"Deployment type '{deployment_type}' was not recognised."
            )
        self.stack_name = self.program.stack_name
        self.work_dir = self.program.work_dir(pathlib.Path.cwd() / "pulumi")

    @property
    def local_stack_path(self) -> pathlib.Path:
        """Return the local stack path"""
        return self.work_dir / f"Pulumi.{self.stack_name}.yaml"

    @property
    def env(self) -> Dict[str, Any]:
        if not self.env_:
            backend_storage_account_key = self.cfg.storage_account_key(
                self.cfg.backend.resource_group_name,
                self.cfg.backend.storage_account_name,
            )
            self.env_ = {
                "AZURE_STORAGE_ACCOUNT": self.cfg.backend.storage_account_name,
                "AZURE_STORAGE_KEY": backend_storage_account_key,
                "AZURE_KEYVAULT_AUTH_VIA_CLI": "true",
            }
        return self.env_

    @property
    def stack(self) -> automation.Stack:
        """Load the Pulumi stack, creating if needed."""
        if not self.stack_:
            self.info(f"Creating/loading stack <fg=green>{self.stack_name}</>.")
            self.stack_ = automation.create_or_select_stack(
                project_name="data_safe_haven",
                stack_name=self.stack_name,
                program=self.program.run,
                opts=automation.LocalWorkspaceOptions(
                    secrets_provider=self.cfg.backend.pulumi_secrets_provider,
                    work_dir=str(self.work_dir),
                    env_vars=self.env,
                ),
            )
        return self.stack_

    def add_option(self, name: str, value: str, replace: bool = False) -> None:
        """Add a public configuration option"""
        self.options[name] = (value, False, replace)

    def add_secret(self, name: str, value: str, replace: bool = False) -> None:
        """Add a secret configuration option if it does not exist"""
        self.options[name] = (value, True, replace)

    def apply_config_options(self) -> None:
        """Set Pulumi config options"""
        for name, (value, is_secret, replace) in self.options.items():
            if replace:
                self.set_config(name, value, is_secret)
            else:
                self.ensure_config(name, value, is_secret)
        self.options = {}

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
            self.login()
            self.install_plugins()
            self.apply_config_options()
            self.refresh()
            self.preview()
            self.update()
        except Exception as exc:
            raise DataSafeHavenPulumiException(
                f"Pulumi deployment failed.\n{str(exc)}"
            ) from exc

    def destroy(self) -> None:
        """Destroy deployed infrastructure."""
        try:
            # Note that the first iteration can fail due to failure to delete container NICs
            # See https://github.com/MicrosoftDocs/azure-docs/issues/20737 for details
            while True:
                try:
                    result = self.stack.destroy(
                        color="always", on_output=self.info, parallel=1
                    )
                    self.evaluate(result.summary.result)
                    break
                except automation.errors.CommandError as exc:
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
        except automation.errors.CommandError as exc:
            raise DataSafeHavenPulumiException("Pulumi destroy failed.") from exc

    def ensure_config(self, name: str, value: str, secret: bool = False) -> None:
        """Ensure that config values have been set, setting them if they do not exist"""
        try:
            self.stack.get_config(name)
        except automation.errors.CommandError:
            self.set_config(name, value, secret)

    def evaluate(self, result: str) -> None:
        """Evaluate a Pulumi operation."""
        if result == "succeeded":
            self.info("Pulumi operation <fg=green>succeeded</>.")
        else:
            self.error("Pulumi operation <fg=red>failed</>.")
            raise DataSafeHavenPulumiException("Pulumi operation failed.")

    def initialise_workdir(self) -> None:
        """Create project directory if it does not exist and update local stack."""
        try:
            self.info(
                f"Ensuring that <fg=green>{self.work_dir}</> exists...", no_newline=True
            )
            if not self.work_dir.exists():
                self.work_dir.mkdir(parents=True)
            self.info(
                f"Ensured that <fg=green>{self.work_dir}</> exists.", overwrite=True
            )
            # If stack information is saved in the config file then apply it here
            if self.stack_name in self.cfg.pulumi.stacks.keys():
                self.info(
                    f"Loading stack <fg=green>{self.stack_name}</> information from config"
                )
                stack_yaml = yaml.dump(
                    self.cfg.pulumi.stacks[self.stack_name].toDict(), indent=2
                )
                with open(self.local_stack_path, "w", encoding="utf-8") as f_stack:
                    f_stack.writelines(stack_yaml)
        except Exception as exc:
            raise DataSafeHavenPulumiException(
                f"Initialising Pulumi working directory failed.\n{str(exc)}."
            ) from exc

    def install_plugins(self) -> None:
        """For inline programs, we must manage plugins ourselves."""
        self.stack.workspace.install_plugin("azure-native", "1.60.0")

    def login(self) -> None:
        """Login to Pulumi."""
        try:
            env_vars = " ".join([f"{k}={v}" for k, v in self.env.items()])
            command = f"pulumi login azblob://{self.cfg.pulumi.storage_container_name}"
            with subprocess.Popen(
                f"{env_vars} {command}",
                shell=True,
                cwd=self.work_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                encoding="UTF-8",
            ) as process:
                if process.stdout:
                    self.info(process.stdout.readline().strip())
        except Exception as exc:
            raise DataSafeHavenPulumiException(
                f"Logging into Pulumi failed.\n{str(exc)}."
            ) from exc

    def output(self, name: str) -> Any:
        return self.stack.outputs()[name].value

    def preview(self) -> None:
        """Preview the Pulumi stack."""
        try:
            with suppress(automation.errors.CommandError):
                self.info(
                    f"Previewing changes for stack <fg=green>{self.stack.name}</>."
                )
                self.stack.preview(color="always", diff=True, on_output=self.info)
        except Exception as exc:
            raise DataSafeHavenPulumiException(
                f"Pulumi preview failed.\n{str(exc)}."
            ) from exc

    def refresh(self) -> None:
        """Refresh the Pulumi stack."""
        try:
            self.info(f"Refreshing stack <fg=green>{self.stack.name}</>.")
            # Note that we disable parallelisation which can cause deadlock
            self.stack.refresh(color="always", parallel=1)
        except automation.errors.CommandError as exc:
            raise DataSafeHavenPulumiException(
                f"Pulumi refresh failed.\n{str(exc)}"
            ) from exc

    def remove_workdir(self) -> None:
        """Remove project directory if it exists."""
        try:
            self.info(f"Removing <fg=green>{self.work_dir}</>...", no_newline=True)
            if self.work_dir.exists():
                shutil.rmtree(self.work_dir)
            self.info(f"Removed <fg=green>{self.work_dir}</>.", overwrite=True)
        except Exception as exc:
            raise DataSafeHavenPulumiException(
                f"Removing Pulumi working directory failed.\n{str(exc)}."
            ) from exc

    def secret(self, name: str) -> str:
        """Read a secret from the Pulumi stack."""
        try:
            return self.stack.get_config(name).value
        except automation.errors.CommandError as exc:
            raise DataSafeHavenPulumiException(
                f"Secret '{name}' was not found."
            ) from exc

    def set_config(self, name: str, value: str, secret: bool = False) -> None:
        """Set config values, overwriting any existing value."""
        self.stack.set_config(name, automation.ConfigValue(value=value, secret=secret))

    def teardown(self) -> None:
        """Teardown the infrastructure deployed with Pulumi."""
        try:
            self.initialise_workdir()
            self.login()
            self.install_plugins()
            self.refresh()
            self.destroy()
            self.remove_workdir()
        except Exception as exc:
            raise DataSafeHavenPulumiException(
                f"Tearing down Pulumi infrastructure failed.\n{str(exc)}."
            ) from exc

    def update(self) -> None:
        """Update deployed infrastructure."""
        try:
            result = self.stack.up(color="always", on_output=self.info)
            self.evaluate(result.summary.result)
        except automation.errors.CommandError as exc:
            raise DataSafeHavenPulumiException(
                f"Pulumi update failed.\n{str(exc)}"
            ) from exc
