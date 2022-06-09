"""Deploy with Pulumi"""
# Standard library imports
from contextlib import suppress
import pathlib
import subprocess
import time

# Third party imports
from pulumi import automation
import yaml

# Local imports
from .pulumi_program import PulumiProgram
from data_safe_haven.exceptions import DataSafeHavenPulumiException
from data_safe_haven.helpers import password
from data_safe_haven.mixins import LoggingMixin


class PulumiInterface(LoggingMixin):
    """Interact with infrastructure using Pulumi"""

    def __init__(self, config, project_path, *args, **kwargs):
        self.cfg = config
        self.stack_ = None
        self.work_dir = pathlib.Path(project_path / "pulumi").resolve()
        self.program = PulumiProgram(self.cfg)
        self.env_ = None
        super().__init__(*args, **kwargs)

    @property
    def local_stack_path(self):
        """Return the local stack path"""
        return self.work_dir / f"Pulumi.{self.cfg.environment.name}.yaml"

    @property
    def env(self):
        if not self.env_:
            self.env_ = {
                "AZURE_STORAGE_ACCOUNT": self.cfg.backend.storage_account_name,
                "AZURE_STORAGE_KEY": self.cfg.storage_account_key(),
                "AZURE_KEYVAULT_AUTH_VIA_CLI": "true",
            }
        return self.env_

    @property
    def stack(self):
        """Load the Pulumi stack, creating if needed."""
        if not self.stack_:
            self.info(
                f"Creating/loading stack <fg=green>{self.cfg.environment.name}</>."
            )
            self.stack_ = automation.create_or_select_stack(
                project_name="data_safe_haven",
                stack_name=self.cfg.environment.name,
                program=self.program.run,
                opts=automation.LocalWorkspaceOptions(
                    secrets_provider=self.cfg.pulumi.encryption_key,
                    work_dir=self.work_dir,
                    env_vars=self.env,
                ),
            )
        return self.stack_

    def deploy(self, aad_auth_app_secret):
        """Deploy the infrastructure with Pulumi."""
        self.initialise_workdir()
        self.login()
        self.install_plugins()
        self.set_config_options()
        self.ensure_config(
            "azuread-authentication-application-secret",
            aad_auth_app_secret,
            secret=True,
        )
        self.refresh()
        self.preview()
        self.update()

    def destroy(self):
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

    def ensure_config(self, name, value, secret=False):
        """Ensure that config values have been set"""
        try:
            self.stack.get_config(name)
        except automation.errors.CommandError as exc:
            self.stack.set_config(
                name, automation.ConfigValue(value=value, secret=secret)
            )

    def evaluate(self, result):
        """Evaluate a Pulumi operation."""
        if result == "succeeded":
            self.info("Pulumi operation <fg=green>succeeded</>.")
        else:
            self.error("Pulumi operation <fg=red>failed</>.")
            raise DataSafeHavenPulumiException("Pulumi operation failed.")

    def initialise_workdir(self):
        """Create project directory if it does not exist and update local stack."""
        self.info(f"Ensuring that {self.work_dir} exists...", no_newline=True)
        if not self.work_dir.exists():
            self.work_dir.mkdir()
        self.info(f"Ensured that {self.work_dir} exists.", overwrite=True)
        # If stack information is saved in the config file then apply it here
        if "stack" in self.cfg.pulumi.keys():
            self.info(
                f"Loading stack <fg=green>{self.cfg.environment.name}</> information from config"
            )
            stack_yaml = yaml.dump(self.cfg.pulumi.stack.toDict(), indent=2)
            with open(self.local_stack_path, "w") as f_stack:
                f_stack.writelines(stack_yaml)

    def install_plugins(self):
        """For inline programs, we must manage plugins ourselves."""
        self.stack.workspace.install_plugin("azure-native", "1.60.0")

    def login(self):
        """Login to Pulumi."""
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

    def output(self, name):
        return self.stack.outputs()[name].value

    def preview(self):
        """Preview the Pulumi stack."""
        with suppress(automation.errors.CommandError):
            self.info(f"Previewing changes for stack <fg=green>{self.stack.name}</>.")
            self.stack.preview(color="always", diff=True, on_output=self.info)

    def refresh(self):
        """Refresh the Pulumi stack."""
        try:
            self.info(f"Refreshing stack <fg=green>{self.stack.name}</>.")
            self.stack.refresh(color="always")
        except automation.errors.CommandError as exc:
            raise DataSafeHavenPulumiException("Pulumi refresh failed.") from exc

    def secret(self, name):
        """Read a secret from the Pulumi stack."""
        try:
            return self.stack.get_config(name).value
        except automation.errors.CommandError as exc:
            raise DataSafeHavenPulumiException(
                f"Secret '{name}' was not found."
            ) from exc

    def set_config_options(self):
        """Set Pulumi config options"""
        self.ensure_config("azure-native:location", self.cfg.azure.location)
        self.ensure_config(
            "azure-native:subscriptionId", self.cfg.azure.subscription_id
        )
        self.ensure_config(
            "authentication-openldap-admin-password",
            password(20),
            secret=True,
        )
        self.ensure_config(
            "authentication-openldap-search-password",
            password(20),
            secret=True,
        )
        self.ensure_config("guacamole-postgresql-password", password(20), secret=True)
        self.ensure_config(
            "secure-research-desktop-admin-password", password(20), secret=True
        )

    def teardown(self):
        """Teardown the infrastructure deployed with Pulumi."""
        self.initialise_workdir()
        self.login()
        self.install_plugins()
        self.refresh()
        self.destroy()

    def update(self):
        """Update deployed infrastructure."""
        try:
            result = self.stack.up(color="always", on_output=self.info)
            self.evaluate(result.summary.result)
        except automation.errors.CommandError as exc:
            raise DataSafeHavenPulumiException("Pulumi update failed.") from exc

    def update_config(self):
        """Add infrastructure settings to config"""
        self.cfg.add_data(
            {
                "pulumi": {
                    "outputs": {
                        "guacamole": {
                            "container_group_name": self.output(
                                "guacamole_container_group_name"
                            ),
                            "postgresql_server_name": self.output(
                                "guacamole_postgresql_server_name"
                            ),
                            "resource_group_name": self.output(
                                "guacamole_resource_group_name"
                            ),
                        },
                        "state": {
                            "resource_group_name": self.output(
                                "state_resource_group_name"
                            ),
                            "storage_account_name": self.output(
                                "state_storage_account_name"
                            ),
                        },
                    }
                }
            }
        )
