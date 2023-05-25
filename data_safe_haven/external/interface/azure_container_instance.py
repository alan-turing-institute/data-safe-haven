"""Backend for a Data Safe Haven environment"""
# Standard library imports
import contextlib
import time
from typing import List, Optional

# Third party imports
import websocket
from azure.core.polling import LROPoller
from azure.mgmt.containerinstance import ContainerInstanceManagementClient
from azure.mgmt.containerinstance.models import (
    ContainerExecRequest,
    ContainerExecRequestTerminalSize,
)

# Local imports
from data_safe_haven.exceptions import DataSafeHavenAzureException
from data_safe_haven.mixins import AzureMixin, LoggingMixin


class AzureContainerInstance(AzureMixin, LoggingMixin):
    """Interface for Azure container instances."""

    def __init__(
        self,
        container_group_name: str,
        resource_group_name: str,
        subscription_name: str,
    ):
        super().__init__(subscription_name=subscription_name)
        self.resource_group_name = resource_group_name
        self.container_group_name = container_group_name

    @staticmethod
    def wait(poller: LROPoller[None]) -> None:
        while not poller.done():
            time.sleep(10)

    @property
    def current_ip_address(self) -> str:
        aci_client = ContainerInstanceManagementClient(
            self.credential, self.subscription_id
        )
        ip_address = aci_client.container_groups.get(
            self.resource_group_name, self.container_group_name
        ).ip_address
        if ip_address and isinstance(ip_address.ip, str):
            return ip_address.ip
        raise DataSafeHavenAzureException(
            f"Could not determine IP address for container group {self.container_group_name}."
        )

    def restart(self, target_ip_address: Optional[str] = None) -> None:
        """Restart the container group"""
        # Connect to Azure clients
        try:
            aci_client = ContainerInstanceManagementClient(
                self.credential, self.subscription_id
            )
            if not target_ip_address:
                target_ip_address = self.current_ip_address

            # Restart container group
            self.info(
                f"Restarting container group <fg=green>{self.container_group_name}</> with IP address <fg=green>{target_ip_address}</>...",
                no_newline=True,
            )
            while True:
                if (
                    aci_client.container_groups.get(
                        self.resource_group_name, self.container_group_name
                    ).provisioning_state
                    == "Succeeded"
                ):
                    self.wait(
                        aci_client.container_groups.begin_restart(
                            self.resource_group_name, self.container_group_name
                        )
                    )
                else:
                    self.wait(
                        aci_client.container_groups.begin_start(
                            self.resource_group_name, self.container_group_name
                        )
                    )
                if self.current_ip_address == target_ip_address:
                    break
            self.info(
                f"Restarted container group <fg=green>{self.container_group_name}</> with IP address <fg=green>{self.current_ip_address}</>.",
                overwrite=True,
            )
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Could not restart container group {self.container_group_name}.\n{str(exc)}"
            ) from exc

    def run_executable(self, container_name: str, executable_path: str) -> List[str]:
        """
        Run a script or command on one of the containers.

        The command cannot take any arguments and must be a single expression.
        The most likely use-case is running a script already present in the container.
        """
        # Connect to Azure clients
        aci_client = ContainerInstanceManagementClient(
            self.credential, self.subscription_id
        )

        # Run command
        cnxn = aci_client.containers.execute_command(
            self.resource_group_name,
            self.container_group_name,
            container_name,
            ContainerExecRequest(
                command=executable_path,
                terminal_size=ContainerExecRequestTerminalSize(cols=80, rows=500),
            ),
        )

        # Get command output via websocket
        socket = websocket.create_connection(cnxn.web_socket_uri)
        if cnxn.password:
            socket.send(cnxn.password)
        output = []
        with contextlib.suppress(websocket.WebSocketConnectionClosedException):
            while result := socket.recv():
                for line in [line.strip() for line in result.splitlines()]:
                    output.append(line)
            socket.close()
        return output
