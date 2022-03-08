"""Deploy with Pulumi"""
# Standard library imports
import pathlib
from contextlib import suppress

# Third party imports
from pulumi import automation

# Local imports
from .pulumi_program import PulumiProgram
from data_safe_haven.exceptions import DataSafeHavenPulumiException
from data_safe_haven.mixins import LoggingMixin


class PulumiCreate(LoggingMixin):
    """Deploy infrastructure with Pulumi"""

    def __init__(self, config, *args, **kwargs):
        self.cfg = config
        self.stack = None
        self.work_dir = pathlib.Path(self.cfg.project_directory.pulumi).resolve()
        self.program = PulumiProgram(self.cfg)
        self.env = {
            "AZURE_STORAGE_ACCOUNT": config.metadata.storage_account_name,
            "AZURE_STORAGE_KEY": config.storage_account_key(),
            "AZURE_KEYVAULT_AUTH_VIA_CLI": "true",
        }
        super().__init__(*args, **kwargs)

    def evaluate(self, result):
        if result == "succeeded":
            self.info("Pulumi operation <fg=green>succeeded</>.")
        else:
            self.error("Pulumi operation <fg=red>failed</>.")
            raise DataSafeHavenPulumiException("Pulumi operation failed.")

    def load_stack(self):
        self.info(f"Creating/loading stack <fg=green>{self.cfg.deployment.name}</>.")
        self.stack = automation.create_or_select_stack(
            project_name="data_safe_haven",
            stack_name=self.cfg.deployment.name,
            program=self.program.run,
            opts=automation.LocalWorkspaceOptions(
                secrets_provider=self.cfg.pulumi["encryption_key"],
                work_dir=self.work_dir,
                env_vars=self.env,
            ),
        )

    def install_plugins(self):
        """For inline programs, we must manage plugins ourselves."""
        self.stack.workspace.install_plugin("azure-native", "1.60.0")

    def configure_stack(self):
        """Set Azure config options"""
        self.stack.set_config(
            "azure-native:location",
            automation.ConfigValue(value=self.cfg.azure.location),
        )
        self.stack.set_config(
            "azure-native:subscriptionId",
            automation.ConfigValue(value=self.cfg.azure.subscription_id),
        )

    def refresh(self):
        """Refresh stack."""
        try:
            self.info(f"Refreshing stack <fg=green>{self.stack.name}</>.")
            self.stack.refresh(color="always")
        except automation.errors.CommandError as exc:
            raise DataSafeHavenPulumiException("Pulumi refresh failed.") from exc

    def preview(self):
        """Preview stack."""
        with suppress(automation.errors.CommandError):
            self.info(f"Previewing changes for stack <fg=green>{self.stack.name}</>.")
            self.stack.preview(color="always", diff=True, on_output=self.info)

    def update(self):
        """Update deployed infrastructure."""
        try:
            result = self.stack.up(color="always", on_output=self.info)
            self.evaluate(result.summary.result)
        except automation.errors.CommandError as exc:
            raise DataSafeHavenPulumiException("Pulumi update failed.") from exc

    def initialise_workdir(self):
        """Create project directory if it does not exist."""
        self.debug(f"Ensuring that {self.work_dir} exists.")
        if not self.work_dir.exists():
            self.work_dir.mkdir()
            self.debug(f"Created {self.work_dir}.")

    def apply(self):
        """Deploy the infrastructure with Pulumi."""
        self.initialise_workdir()
        self.load_stack()
        self.install_plugins()
        self.configure_stack()
        self.refresh()
        self.preview()
        self.update()

    def write_kubeconfig(self, output_dir):
        """Write kubeconfig to the project directory"""
        # Ensure that the output directory exists
        output_path = pathlib.Path(output_dir).resolve()
        if not output_path.exists():
            output_path.mkdir()

        # Write output to the kubeconfig file
        with open(output_path / f"kubeconfig-{self.cfg.deployment.name}.yaml", "w") as f_kubeconfig:
            kubeconfig = self.stack.outputs()["kubeconfig"].value
            f_kubeconfig.writelines(kubeconfig.split("\\n"))
