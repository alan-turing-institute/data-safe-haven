import chevron
import json
import subprocess
import shutil
from data_safe_haven.mixins import LoggingMixin
from data_safe_haven.exceptions import DataSafeHavenPulumiException


class PulumiStack(LoggingMixin):
    """Set up pulumi stack"""

    def __init__(self, config, project_path, template_path):
        super().__init__()
        self.cfg = config
        self.pulumi_path = project_path / "pulumi"
        self.template_path = template_path
        self.env = {
            "AZURE_STORAGE_ACCOUNT": self.cfg.metadata.storage_account_name,
            "AZURE_STORAGE_KEY": self.cfg.storage_account_key(),
            "AZURE_KEYVAULT_AUTH_VIA_CLI": "'true'",
        }
        self.encryption_key = self.cfg.pulumi["encryption_key"]

    @property
    def stack_file_path(self):
        return self.pulumi_path / f"Pulumi.{self.cfg.deployment.name}.yaml"

    def initialise(self):
        self.initialise_workdir()
        self.login()
        self.ensure_stack()

    def initialise_workdir(self):
        if not self.pulumi_path.exists():
            self.pulumi_path.mkdir()
        with open(self.template_path / "Pulumi.mustache.yaml", "r") as f_template:
            with open(self.pulumi_path / "Pulumi.yaml", "w") as f_output:
                f_output.writelines(
                    chevron.render(f_template, {"name": self.cfg.deployment.name})
                )
        for filepath in list(self.template_path.glob("*.py")):
            shutil.copy2(filepath, self.pulumi_path)

    def run(self, command, stream_logs=True):
        """Run an external command in a subprocess"""
        # Note that specifying environment variables with 'env=self.env' does not work correctly with pulumi
        str_env = " ".join([f"{k}={v}" for k, v in self.env.items()])
        kwargs = {
            "shell": True,
            "cwd": self.pulumi_path,
            "stdout": subprocess.PIPE,
            "stderr": subprocess.STDOUT,
            "encoding": "utf-8",
        }
        full_command = f"{str_env} {command}"
        if not stream_logs:
            return subprocess.run(full_command, **kwargs)
        with subprocess.Popen(full_command, **kwargs) as process:
            self.info(process.stdout.readline().strip())

    def login(self):
        self.run(f"pulumi login azblob://{self.cfg.pulumi.storage_container_name}")

    def ensure_stack(self):
        output = self.run(f"pulumi stack ls --json", stream_logs=False)
        if any(
            [
                stack["name"] == self.cfg.deployment.name
                for stack in json.loads(output.stdout)
            ]
        ):
            if self.stack_file_path.is_file():
                self.info(f"Identified local stack '{self.cfg.deployment.name}'.")
            else:
                raise DataSafeHavenPulumiException(
                    f"Stack '{self.cfg.deployment.name}' already exists."
                )
        else:
            self.run(
                f"pulumi stack init --secrets-provider={self.encryption_key} {self.cfg.deployment.name}"
            )
        self.run(
            f"pulumi stack select --secrets-provider={self.encryption_key} {self.cfg.deployment.name}",
            stream_logs=False,
        )
