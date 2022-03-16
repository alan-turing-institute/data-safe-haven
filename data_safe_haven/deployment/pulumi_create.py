"""Deploy with Pulumi"""
# Standard library imports
from contextlib import suppress
import pathlib
import secrets
import subprocess
import string

# Third party imports
from pulumi import automation
import yaml

# Local imports
from .pulumi_program import PulumiProgram
from data_safe_haven.exceptions import DataSafeHavenPulumiException
from data_safe_haven.mixins import LoggingMixin


class PulumiCreate(LoggingMixin):
    """Deploy infrastructure with Pulumi"""

    def __init__(self, config, project_path, *args, **kwargs):
        self.cfg = config
        self.stack = None
        self.work_dir = pathlib.Path(project_path / "pulumi").resolve()
        self.program = PulumiProgram(self.cfg)
        self.env = {
            "AZURE_STORAGE_ACCOUNT": config.backend.storage_account_name,
            "AZURE_STORAGE_KEY": config.storage_account_key(),
            "AZURE_KEYVAULT_AUTH_VIA_CLI": "true",
        }
        super().__init__(*args, **kwargs)

    @property
    def local_stack_path(self):
        return self.work_dir / f"Pulumi.{self.cfg.environment.name}.yaml"

    def evaluate(self, result):
        if result == "succeeded":
            self.info("Pulumi operation <fg=green>succeeded</>.")
        else:
            self.error("Pulumi operation <fg=red>failed</>.")
            raise DataSafeHavenPulumiException("Pulumi operation failed.")

    def load_stack(self):
        """Load the pulumi stack"""
        self.info(f"Creating/loading stack <fg=green>{self.cfg.environment.name}</>.")
        self.stack = automation.create_or_select_stack(
            project_name="data_safe_haven",
            stack_name=self.cfg.environment.name,
            program=self.program.run,
            opts=automation.LocalWorkspaceOptions(
                secrets_provider=self.cfg.pulumi.encryption_key,
                work_dir=self.work_dir,
                env_vars=self.env,
            ),
        )

    def install_plugins(self):
        """For inline programs, we must manage plugins ourselves."""
        self.stack.workspace.install_plugin("azure-native", "1.60.0")

    def configure_stack(self):
        """Set Azure config options"""
        self.ensure_config("azure-native:location", self.cfg.azure.location)
        self.ensure_config("azure-native:subscriptionId", self.cfg.azure.subscription_id)
        self.ensure_config("guacamole-postgresql-password", self.generate_password(20), secret=True)

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

    def generate_password(self, length):
        alphabet = string.ascii_letters + string.digits
        return "".join(secrets.choice(alphabet) for _ in range(length))

    def initialise_workdir(self):
        """Create project directory if it does not exist and update local stack."""
        self.info(f"Ensuring that {self.work_dir} exists.")
        if not self.work_dir.exists():
            self.work_dir.mkdir()
            self.debug(f"Created {self.work_dir}.")
        # If stack information is saved in the config file then apply it here
        if "stack" in self.cfg.pulumi.keys():
            self.info(f"Loading stack <fg=green>{self.cfg.environment.name}</> information from config")
            stack_yaml = yaml.dump(self.cfg.pulumi.stack.toDict(), indent=2)
            with open(self.local_stack_path, "w") as f_stack:
                f_stack.writelines(stack_yaml)

    def apply(self):
        """Deploy the infrastructure with Pulumi."""
        self.initialise_workdir()
        self.login()
        self.load_stack()
        self.install_plugins()
        self.configure_stack()
        self.refresh()
        self.preview()
        self.update()

    def login(self):
        """Login to Pulumi."""
        env_vars = " ".join([f"{k}={v}" for k, v in self.env.items()])
        command = f"pulumi login azblob://{self.cfg.pulumi.storage_container_name}"
        with subprocess.Popen(f"{env_vars} {command}", shell=True, cwd=self.work_dir, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding="UTF-8") as process:
            self.info(process.stdout.readline().strip())

    def ensure_config(self, name, value, secret=False):
        """Ensure that config values have been set"""
        try:
            self.stack.get_config(name)
        except automation.errors.CommandError as exc:
            self.stack.set_config(name, automation.ConfigValue(value=value, secret=secret))

    def write_kubeconfig(self, output_dir):
        """Write kubeconfig to the project directory"""
        # Ensure that the output directory exists
        output_path = pathlib.Path(output_dir).resolve()
        if not output_path.exists():
            output_path.mkdir()

        # Write output to the kubeconfig file
        with open(
            output_path / f"kubeconfig-{self.cfg.environment.name}.yaml", "w"
        ) as f_kubeconfig:
            kubeconfig = self.stack.outputs()["kubeconfig"].value
            f_kubeconfig.writelines(kubeconfig.split("\\n"))
