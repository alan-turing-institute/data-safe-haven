"""Deploy with Pulumi"""
# Standard library imports
from contextlib import suppress
import pathlib
import subprocess
import time
from typing import Any, Dict, Optional

# Third party imports
from pulumi import automation
import yaml

# Local imports
from .declarative_shm import DeclarativeSHM
from .declarative_sre import DeclarativeSRE
from data_safe_haven.config import Config
from data_safe_haven.exceptions import DataSafeHavenPulumiException
from data_safe_haven.mixins import LoggingMixin


class PulumiInterface(LoggingMixin):
    """Interact with infrastructure using Pulumi"""

    def __init__(
        self,
        config: Config,
        deployment_type: str,
        sre_name: str = None,
        *args: Optional[Any],
        **kwargs: Optional[Any],
    ):
        super().__init__(*args, **kwargs)
        self.cfg = config
        self.env_ = None
        self.stack_ = None
        self.options = {}
        if deployment_type == "SHM":
            self.stack_name = f"shm-{config.shm.name}"
            self.program = DeclarativeSHM(config, self.stack_name)
            self.work_dir = pathlib.Path.cwd() / "pulumi" / self.stack_name
        elif deployment_type == "SRE":
            self.stack_name = f"shm-{config.shm.name}-sre-{sre_name}"
            self.program = DeclarativeSRE(config, self.stack_name, sre_name)
            self.work_dir = (
                pathlib.Path.cwd()
                / "pulumi"
                / f"shm-{config.shm.name}"
                / f"sre-{sre_name}"
            )
        else:
            raise DataSafeHavenPulumiException(
                f"Deployment type '{deployment_type}' was not recognised."
            )

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
                    work_dir=self.work_dir,
                    env_vars=self.env,
                ),
            )
        return self.stack_

    def add_option(self, name: str, value: str) -> None:
        """Add a public configuration option"""
        self.options[name] = (value, False)

    def add_secret(self, name: str, value: str) -> None:
        """Add a secret configuration option"""
        self.options[name] = (value, True)

    def apply_config_options(self) -> None:
        """Set Pulumi config options"""
        for name, (value, is_secret) in self.options.items():
            self.ensure_config(name, value, is_secret)
        self.options = {}

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
                f"Pulumi deployment failed.\n{str(exc)}."
            ) from exc

    def destroy(self) -> None:
        """Destroy deployed infrastructure."""
        try:
            # Note that the first iteration can fail due to failure to delete container NICs
            # See https://github.com/MicrosoftDocs/azure-docs/issues/20737 for details
            while True:
                try:
                    result = self.stack.destroy(color="always", on_output=self.info)
                    self.evaluate(result.summary.result)
                    break
                except automation.errors.CommandError as exc:
                    if any(
                        [
                            error in str(exc)
                            for error in (
                                "NetworkProfileAlreadyInUseWithContainerNics",
                                "InUseSubnetCannotBeDeleted",
                            )
                        ]
                    ):
                        time.sleep(10)
                    else:
                        raise
        except automation.errors.CommandError as exc:
            raise DataSafeHavenPulumiException("Pulumi destroy failed.") from exc

    def ensure_config(self, name: str, value: str, secret: bool = False) -> None:
        """Ensure that config values have been set"""
        try:
            self.stack.get_config(name)
        except automation.errors.CommandError:
            self.stack.set_config(
                name, automation.ConfigValue(value=value, secret=secret)
            )

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
                stack_yaml = yaml.dump(self.cfg.pulumi.stacks[self.stack_name].toDict(), indent=2)
                with open(self.local_stack_path, "w") as f_stack:
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
            self.stack.refresh(color="always")
        except automation.errors.CommandError as exc:
            raise DataSafeHavenPulumiException(
                f"Pulumi refresh failed.\n{str(exc)}"
            ) from exc

    def secret(self, name: str) -> str:
        """Read a secret from the Pulumi stack."""
        try:
            return self.stack.get_config(name).value
        except automation.errors.CommandError as exc:
            raise DataSafeHavenPulumiException(
                f"Secret '{name}' was not found."
            ) from exc

    def teardown(self) -> None:
        """Teardown the infrastructure deployed with Pulumi."""
        try:
            self.initialise_workdir()
            self.login()
            self.install_plugins()
            self.refresh()
            self.destroy()
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
            raise DataSafeHavenPulumiException("Pulumi update failed.") from exc

    # def update_config(self):
    #     """Add infrastructure settings to config"""
    #     self.cfg.add_data(
    #         {
    #             "pulumi": {
    #                 "outputs": {
    #                     "guacamole": {
    #                         "container_group_name": self.output(
    #                             "guacamole_container_group_name"
    #                         ),
    #                         "postgresql_server_name": self.output(
    #                             "guacamole_postgresql_server_name"
    #                         ),
    #                         "resource_group_name": self.output(
    #                             "guacamole_resource_group_name"
    #                         ),
    #                     },
    #                     "state": {
    #                         "resource_group_name": self.output(
    #                             "state_resource_group_name"
    #                         ),
    #                         "storage_account_name": self.output(
    #                             "state_storage_account_name"
    #                         ),
    #                     },
    #                 }
    #             }
    #         }
    #     )
