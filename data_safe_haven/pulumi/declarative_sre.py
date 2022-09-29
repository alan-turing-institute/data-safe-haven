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
from .components.secure_research_desktop import (
    SecureResearchDesktopComponent,
    SecureResearchDesktopProps,
)
from .components.sre_key_vault import SREKeyVaultComponent, SREKeyVaultProps
from .components.sre_networking import SRENetworkingComponent, SRENetworkingProps
from .components.state_storage import StateStorageComponent, StateStorageProps
from data_safe_haven.helpers import alphanumeric, hash


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
            location=self.cfg.azure.location,
            resource_group_name=f"rg-{self.stack_name}-guacamole",
        )
        rg_networking = resources.ResourceGroup(
            "rg_networking",
            location=self.cfg.azure.location,
            resource_group_name=f"rg-{self.stack_name}-networking",
        )
        rg_secure_research_desktop = resources.ResourceGroup(
            "rg_secure_research_desktop",
            location=self.cfg.azure.location,
            resource_group_name=f"rg-{self.stack_name}-secure-research-desktop",
        )
        rg_storage = resources.ResourceGroup(
            "rg_storage",
            location=self.cfg.azure.location,
            resource_group_name=f"rg-{self.stack_name}-storage",
        )

        # Define networking
        networking = SRENetworkingComponent(
            self.stack_name,
            SRENetworkingProps(
                fqdn=self.cfg.sre[self.sre_name].fqdn,
                resource_group_name=rg_networking.name,
                shm_zone_resource_group_name=f"rg-shm-{self.cfg.shm.name}-networking",
                shm_zone_name=self.cfg.shm.fqdn,
                sre_index=self.cfg.sre[self.sre_name].index,
                subdomain=self.cfg.sre[self.sre_name].subdomain,
            ),
        )

        # Define storage accounts
        state_storage = StateStorageComponent(
            self.stack_name,
            StateStorageProps(
                resource_group_name=rg_storage.name,
                storage_name=alphanumeric(f"sre{self.sre_name}{hash(self.stack_name)}"),
            ),
        )

        # Define storage accounts
        key_vault = SREKeyVaultComponent(
            self.stack_name,
            SREKeyVaultProps(
                admin_group_id=self.cfg.azure.admin_group_id,
                fqdn=self.cfg.sre[self.sre_name].fqdn,
                key_vault_resource_group_name=rg_storage.name,
                location=self.cfg.azure.location,
                networking_resource_group_name=rg_networking.name,
                subscription_name=self.cfg.subscription_name,
                sre_name=self.sre_name,
                tenant_id=self.cfg.azure.tenant_id,
            ),
        )

        # Define containerised remote desktop gateway
        guacamole = GuacamoleComponent(
            self.stack_name,
            GuacamoleProps(
                aad_application_name=f"sre-{self.sre_name}-azuread-guacamole",
                aad_application_url=f"https://{self.cfg.sre[self.sre_name].fqdn}",
                aad_auth_token=self.secrets.require("token-azuread-graphapi"),
                aad_tenant_id=self.cfg.shm.aad_tenant_id,
                database_password=self.secrets.get("password-guacamole-database-admin"),
                ip_address_container=networking.guacamole_containers["ip_address"],
                ip_address_database=networking.guacamole_database["ip_address"],
                resource_group_name=rg_guacamole.name,
                subnet_container_name=networking.guacamole_containers["subnet_name"],
                subnet_database_name=networking.guacamole_database["subnet_name"],
                storage_account_name=state_storage.account_name,
                storage_account_resource_group=state_storage.resource_group_name,
                virtual_network_resource_group_name=networking.resource_group_name,
                virtual_network=networking.vnet,
            ),
        )

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
