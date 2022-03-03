"""Ensure that Pulumi and associated stack are initialised"""
import chevron
import shutil
from pulumi import automation
from data_safe_haven.mixins import LoggingMixin, PulumiMixin


class PulumiStack(PulumiMixin, LoggingMixin):
    """Ensure that Pulumi and associated stack are initialised"""

    def __init__(self, config, template_path, *args, **kwargs):
        self.cfg = config
        self.template_path = template_path
        super().__init__(self.cfg, *args, **kwargs)

    def initialise(self):
        self.initialise_workdir()
        self.ensure_stack()

    @property
    def config_path(self):
        return self.pulumi_path / f"Pulumi.{self.cfg.deployment.name}.yaml"

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

    def ensure_stack(self):
        stack = automation.create_or_select_stack(
            stack_name=self.cfg.deployment.name,
            work_dir=self.pulumi_path,
            opts=automation.LocalWorkspaceOptions(
                secrets_provider=self.cfg.pulumi["encryption_key"],
                env_vars=self.env,
            ),
        )
        self.evaluate(stack.info().result, self.info)
