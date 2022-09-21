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
from .components.sre_networking import SRENetworkingComponent, SRENetworkingProps
from .components.secure_research_desktop import (
    SecureResearchDesktopComponent,
    SecureResearchDesktopProps,
)
from .components.state_storage import StateStorageComponent, StateStorageProps


class DeclarativeSRE:
    """Deploy with Pulumi"""

    def __init__(self, config, stack_name, sre_name):
        self.cfg = config
        self.stack_name = stack_name
        self.sre_name = sre_name

    def run(self):
        # Load pulumi configuration secrets
        self.secrets = pulumi.Config()

        # Define resource groups
        rg_guacamole = resources.ResourceGroup(
            "rg_guacamole",
            resource_group_name=f"rg-{self.stack_name}-guacamole",
        )
        rg_networking = resources.ResourceGroup(
            "rg_networking",
            resource_group_name=f"rg-{self.stack_name}-networking",
        )
        rg_secure_research_desktop = resources.ResourceGroup(
            "rg_secure_research_desktop",
            resource_group_name=f"rg-{self.stack_name}-secure-research-desktop",
        )
        rg_state = resources.ResourceGroup(
            "rg_state",
            resource_group_name=f"rg-{self.stack_name}-state",
        )

        # Define networking
        networking = SRENetworkingComponent(
            self.stack_name,
            SRENetworkingProps(
                resource_group_name=rg_networking.name,
                sre_index=self.cfg.sre[self.sre_name].index,
            ),
        )

        # # Define storage accounts
        # state_storage = StateStorageComponent(
        #     self.stack_name,
        #     StateStorageProps(
        #         resource_group_name=rg_state.name,
        #     ),
        # )

        # # Define containerised remote desktop gateway
        # guacamole = GuacamoleComponent(
        #     self.stack_name,
        #     GuacamoleProps(
        #         aad_application_id=self.cfg.deployment.aad_app_id_guacamole,
        #         aad_application_url=f"https://{self.cfg.environment.url}",
        #         aad_tenant_id=self.cfg.azure.aad_tenant_id,
        #         ip_address_container=networking.ip_address_guacamole_container,
        #         ip_address_postgresql=networking.ip_address_guacamole_postgresql,
        #         postgresql_password=self.secrets.get("guacamole-postgresql-password"),
        #         resource_group_name=rg_guacamole.name,
        #         storage_account_name=state_storage.account_name,
        #         storage_account_resource_group=state_storage.resource_group_name,
        #         virtual_network_resource_group_name=networking.resource_group_name,
        #         virtual_network=networking.vnet,
        #     ),
        # )

        # # Define containerised secure desktops
        # srd = SecureResearchDesktopComponent(
        #     self.stack_name,
        #     SecureResearchDesktopProps(
        #         aad_auth_app_id=self.cfg.deployment.aad_app_id_authentication,
        #         aad_auth_app_secret=self.secrets.get(
        #             "azuread-authentication-application-secret"
        #         ),
        #         aad_domain_name=self.cfg.azure.domain_suffix,
        #         aad_group_research_users=self.cfg.azure.aad_group_research_users,
        #         aad_tenant_id=self.cfg.azure.aad_tenant_id,
        #         admin_password=self.secrets.get(
        #             "secure-research-desktop-admin-password"
        #         ),
        #         ip_addresses=networking.ip_addresses_srd,
        #         resource_group_name=rg_secure_research_desktop.name,
        #         virtual_network_resource_group_name=networking.resource_group_name,
        #         virtual_network=networking.vnet,
        #         vm_sizes=self.cfg.environment.vm_sizes,
        #     ),
        # )

        # # Define frontend application gateway
        # application_gateway = ApplicationGatewayComponent(
        #     self.stack_name,
        #     ApplicationGatewayProps(
        #         hostname_guacamole=self.cfg.environment.url,
        #         ip_address_guacamole=guacamole.container_group_ip,
        #         key_vault_certificate_id=self.cfg.deployment.certificate_id,
        #         key_vault_identity=f"/subscriptions/{self.cfg.azure.subscription_id}/resourceGroups/{self.cfg.backend.resource_group_name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{self.cfg.backend.identity_name}",
        #         resource_group_name=rg_networking.name,
        #         virtual_network=networking.vnet,
        #     ),
        # )

        # # Define DNS
        # dns = DnsComponent(
        #     self.stack_name,
        #     DnsProps(
        #         dns_name=self.cfg.environment.url,
        #         public_ip=application_gateway.public_ip_address,
        #         resource_group_name=rg_networking.name,
        #         subdomains=[],
        #     ),
        # )

        # # Export values for later use
        # pulumi.export("guacamole_container_group_name", guacamole.container_group_name)
        # pulumi.export(
        #     "guacamole_postgresql_server_name", guacamole.postgresql_server_name
        # )
        # pulumi.export("guacamole_resource_group_name", guacamole.resource_group_name)
        # pulumi.export("state_resource_group_name", state_storage.resource_group_name)
        # pulumi.export("state_storage_account_name", state_storage.account_name)
        # pulumi.export("vm_details", srd.vm_details)
