"""Deploy with Pulumi"""
from pulumi import automation
from data_safe_haven.mixins import PulumiMixin, LoggingMixin


class PulumiDeploy(PulumiMixin, LoggingMixin):
    """Deploy with Pulumi"""

    def __init__(self, config, *args, **kwargs):
        self.cfg = config
        self.stack = None
        super().__init__(self.cfg, *args, **kwargs)

    def deploy(self):
        self.load_stack()
        self.update_pulumi_config()
        self.update()

    def load_stack(self):
        self.stack = automation.select_stack(
            stack_name=self.cfg.deployment.name,
            work_dir=self.pulumi_path,
            opts=automation.LocalWorkspaceOptions(
                secrets_provider=self.cfg.pulumi["encryption_key"],
                env_vars=self.env,
            ),
        )

    def update_pulumi_config(self):
        self.stack.set_config(
            "azure-native:location",
            automation.ConfigValue(value=self.cfg.azure.location),
        )
        self.stack.set_config(
            "azure-native:subscriptionId",
            automation.ConfigValue(value=self.cfg.azure.subscription_id),
        )
        self.stack.set_config(
            "deployment_name", automation.ConfigValue(value=self.cfg.deployment_name)
        )

    def update(self):
        # Refresh stack
        self.info(f"Refreshing stack <fg=green>{self.stack.name}</>.")
        self.stack.refresh(color="always")
        # Update deployed infrastructure
        result = self.stack.up(color="always", on_output=self.info)
        self.evaluate(result.summary.result, self.info)
