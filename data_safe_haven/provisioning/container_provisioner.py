"""Backend for a Data Safe Haven environment"""
# Standard library imports
import time

# Third party imports
from azure.mgmt.containerinstance import ContainerInstanceManagementClient

# Local imports
from data_safe_haven.mixins import AzureMixin, LoggingMixin


class ContainerProvisioner(AzureMixin, LoggingMixin):
    """Provisioner for Azure containers."""

    def __init__(self, config, resource_group_name, container_group_name):
        super().__init__(subscription_name=config.azure.subscription_name)
        self.resource_group_name = resource_group_name
        self.container_group_name = container_group_name

    @staticmethod
    def wait(poller):
        while not poller.done():
            time.sleep(10)

    def restart(self):
        # Connect to Azure clients
        aci_client = ContainerInstanceManagementClient(
            self.credential, self.subscription_id
        )

        # Restart container group
        self.info(
            f"Restarting container group <fg=green>{self.container_group_name}</>...",
            no_newline=True,
        )
        self.wait(
            aci_client.container_groups.begin_restart(
                self.resource_group_name, self.container_group_name
            )
        )
        self.info(
            f"Restarted container group <fg=green>{self.container_group_name}</>.",
            overwrite=True,
        )
