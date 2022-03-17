"""Pulumi declarative program"""
# Third party imports
import pulumi
from pulumi_azure_native import resources

# Local imports
from .components.application_gateway import (
    ApplicationGatewayComponent,
    ApplicationGatewayProps,
)
from .components.dns import DnsComponent, DnsProps
from .components.guacamole import GuacamoleComponent, GuacamoleProps
from .components.network import NetworkComponent, NetworkProps
from .components.state_storage import StateStorageComponent, StateStorageProps


class PulumiProgram:
    """Deploy with Pulumi"""

    def __init__(self, config):
        self.cfg = config

    def run(self):
        # Load pulumi configuration secrets
        self.secrets = pulumi.Config()

        # Define resource groups
        rg_state = resources.ResourceGroup(
            "rg_state",
            resource_group_name=f"rg-{self.cfg.environment_name}-state",
        )
        rg_guacamole = resources.ResourceGroup(
            "rg_guacamole",
            resource_group_name=f"rg-{self.cfg.environment_name}-guacamole",
        )
        rg_networking = resources.ResourceGroup(
            "rg_networking",
            resource_group_name=f"rg-{self.cfg.environment_name}-networking",
        )

        # Define networking
        networking = NetworkComponent(
            self.cfg.environment_name,
            NetworkProps(
                address_range_vnet=("10.0.0.0", "10.0.255.255"),
                address_range_application_gateway=("10.0.0.0", "10.0.0.255"),
                address_range_authentication=("10.0.1.0", "10.0.1.255"),
                address_range_guacamole_db=("10.0.2.0", "10.0.2.127"),
                address_range_guacamole_containers=("10.0.2.128", "10.0.2.255"),
                resource_group_name=rg_networking.name,
            ),
        )

        # Define storage accounts
        state_storage = StateStorageComponent(
            self.cfg.environment_name,
            StateStorageProps(
                resource_group_name=rg_state.name,
            ),
        )

        # Define containerised remote desktop gateway
        guacamole = GuacamoleComponent(
            self.cfg.environment_name,
            GuacamoleProps(
                ip_address_container=networking.ip4["guacamole_container"],
                ip_address_postgresql=networking.ip4["guacamole_postgresql"],
                postgresql_password=self.secrets.get("guacamole-postgresql-password"),
                resource_group_name=rg_guacamole.name,
                storage_account_name=state_storage.account_name,
                storage_account_resource_group=state_storage.resource_group_name,
                virtual_network_name=networking.vnet.name,
                virtual_network_resource_group=rg_networking.name,
            ),
        )

        # Define frontend application gateway
        application_gateway = ApplicationGatewayComponent(
            self.cfg.environment_name,
            ApplicationGatewayProps(
                key_vault_certificate_id=self.cfg.deployment.certificate_id,
                key_vault_identity=f"/subscriptions/{self.cfg.azure.subscription_id}/resourceGroups/{self.cfg.backend.resource_group_name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{self.cfg.backend.identity_name}",
                resource_group_name=rg_networking.name,
                target_ip_address=guacamole.container_group.ip_address.ip,
                vnet_name=networking.vnet.name,
            ),
        )

        # Define DNS
        dns = DnsComponent(
            self.cfg.environment_name,
            DnsProps(
                dns_name=self.cfg.environment.url,
                public_ip=application_gateway.public_ip.ip_address,
                resource_group_name=rg_networking.name,
            ),
        )

        # Export values for later use
        pulumi.export("storage_account_name", state_storage.account_name)
        pulumi.export("storage_account_key", state_storage.access_key)
        pulumi.export("share_guacamole_caddy", guacamole.file_share_caddy.name)
