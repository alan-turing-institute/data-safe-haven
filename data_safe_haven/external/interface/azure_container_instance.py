import contextlib
import time

import websocket
from azure.core.polling import LROPoller
from azure.mgmt.containerinstance import ContainerInstanceManagementClient
from azure.mgmt.containerinstance.models import (
    ContainerExecRequest,
    ContainerExecRequestTerminalSize,
)

from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.external import AzureSdk
from data_safe_haven.logging import get_logger


class AzureContainerInstance:
    """Interface for Azure container instances."""

    def __init__(
        self,
        container_group_name: str,
        resource_group_name: str,
        subscription_name: str,
    ):
        self.azure_sdk = AzureSdk(subscription_name)
        self.logger = get_logger()
        self.resource_group_name = resource_group_name
        self.container_group_name = container_group_name

    @staticmethod
    def wait(poller: LROPoller[None]) -> None:
        while not poller.done():
            time.sleep(10)

    @property
    def current_ip_address(self) -> str:
        aci_client = ContainerInstanceManagementClient(
            self.azure_sdk.credential(), self.azure_sdk.subscription_id
        )
        ip_address = aci_client.container_groups.get(
            self.resource_group_name, self.container_group_name
        ).ip_address
        if ip_address and isinstance(ip_address.ip, str):
            return ip_address.ip
        msg = f"Could not determine IP address for container group {self.container_group_name}."
        raise DataSafeHavenAzureError(msg)

    def restart(self, target_ip_address: str | None = None) -> None:
        """Restart the container group"""
        # Connect to Azure clients
        try:
            aci_client = ContainerInstanceManagementClient(
                self.azure_sdk.credential(), self.azure_sdk.subscription_id
            )
            if not target_ip_address:
                target_ip_address = self.current_ip_address

            # Restart container group
            self.logger.debug(
                f"Restarting container group [green]{self.container_group_name}[/]"
                f" with IP address [green]{target_ip_address}[/]...",
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
            self.logger.info(
                f"Restarted container group [green]{self.container_group_name}[/]"
                f" with IP address [green]{self.current_ip_address}[/].",
            )
        except Exception as exc:
            msg = f"Could not restart container group {self.container_group_name}."
            raise DataSafeHavenAzureError(msg) from exc

    def run_executable(self, container_name: str, executable_path: str) -> list[str]:
        """
        Run a script or command on one of the containers.

        It is possible to provide arguments to the command if needed.
        The most likely use-case is running a script already present in the container.
        """
        # Connect to Azure clients
        aci_client = ContainerInstanceManagementClient(
            self.azure_sdk.credential(), self.azure_sdk.subscription_id
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
