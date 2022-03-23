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
from .components.authentication import AuthenticationComponent, AuthenticationProps
from .components.state_storage import StateStorageComponent, StateStorageProps


class PulumiProgram:
    """Deploy with Pulumi"""

    def __init__(self, config):
        self.cfg = config

    def run(self):
        # Load pulumi configuration secrets
        self.secrets = pulumi.Config()

        # Define resource groups
        rg_authentication = resources.ResourceGroup(
            "rg_authentication",
            resource_group_name=f"rg-{self.cfg.environment_name}-authentication",
        )
        rg_guacamole = resources.ResourceGroup(
            "rg_guacamole",
            resource_group_name=f"rg-{self.cfg.environment_name}-guacamole",
        )
        rg_networking = resources.ResourceGroup(
            "rg_networking",
            resource_group_name=f"rg-{self.cfg.environment_name}-networking",
        )
        rg_state = resources.ResourceGroup(
            "rg_state",
            resource_group_name=f"rg-{self.cfg.environment_name}-state",
        )

        # Define networking
        networking = NetworkComponent(
            self.cfg.environment_name,
            NetworkProps(
                ip_range_vnet=("10.0.0.0", "10.0.255.255"),
                ip_range_application_gateway=("10.0.0.0", "10.0.0.255"),
                ip_range_authelia=("10.0.1.0", "10.0.1.127"),
                ip_range_openldap=("10.0.1.128", "10.0.1.255"),
                ip_range_guacamole_postgresql=("10.0.2.0", "10.0.2.127"),
                ip_range_guacamole_containers=("10.0.2.128", "10.0.2.255"),
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

        # Define containerised authentication servers
        authentication = AuthenticationComponent(
            self.cfg.environment_name,
            AuthenticationProps(
                ip_address_container=networking.ip_address_openldap,
                ldap_root_dn=self.cfg.ldap_root_dn,
                ldap_admin_password=self.secrets.get(
                    "authentication-openldap-admin-password"
                ),
                resource_group_name=rg_authentication.name,
                storage_account_name=state_storage.account_name,
                storage_account_resource_group=state_storage.resource_group_name,
                virtual_network_name=networking.vnet_name,
                virtual_network_resource_group=rg_networking.name,
            ),
        )

        # Define containerised remote desktop gateway
        guacamole = GuacamoleComponent(
            self.cfg.environment_name,
            GuacamoleProps(
                ip_address_container=networking.ip_address_guacamole_container,
                ip_address_postgresql=networking.ip_address_guacamole_postgresql,
                ldap_group_base_dn=self.cfg.ldap_group_base_dn,
                ldap_search_user_id=self.cfg.ldap_search_user_id,
                ldap_search_user_password=self.secrets.get(
                    "authentication-openldap-search-password"
                ),
                ldap_server_ip=networking.ip_address_openldap,
                ldap_user_base_dn=self.cfg.ldap_user_base_dn,
                postgresql_password=self.secrets.get("guacamole-postgresql-password"),
                resource_group_name=rg_guacamole.name,
                storage_account_name=state_storage.account_name,
                storage_account_resource_group=state_storage.resource_group_name,
                virtual_network_name=networking.vnet_name,
                virtual_network_resource_group=rg_networking.name,
            ),
        )

        # Define frontend application gateway
        application_gateway = ApplicationGatewayComponent(
            self.cfg.environment_name,
            ApplicationGatewayProps(
                hostname_authentication=f"{authentication.subdomain}.{self.cfg.environment.url}",
                hostname_guacamole=self.cfg.environment.url,
                ip_address_authentication=authentication.private_ip_address,
                ip_address_guacamole=guacamole.private_ip_address,
                key_vault_certificate_id=self.cfg.deployment.certificate_id,
                key_vault_identity=f"/subscriptions/{self.cfg.azure.subscription_id}/resourceGroups/{self.cfg.backend.resource_group_name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{self.cfg.backend.identity_name}",
                resource_group_name=rg_networking.name,
                vnet_name=networking.vnet_name,
            ),
        )

        # Define DNS
        dns = DnsComponent(
            self.cfg.environment_name,
            DnsProps(
                dns_name=self.cfg.environment.url,
                public_ip=application_gateway.public_ip_address,
                resource_group_name=rg_networking.name,
                subdomains=[authentication.subdomain],
            ),
        )

        # Export values for later use
        pulumi.export("auth_container_group_name", authentication.container_group_name)
        pulumi.export("auth_resource_group_name", authentication.resource_group_name)
        pulumi.export(
            "auth_share_openldap_ldifs", authentication.file_share_openldap_ldifs_name
        )
        pulumi.export(
            "auth_share_openldap_scripts",
            authentication.file_share_openldap_scripts_name,
        )
        pulumi.export(
            "auth_ldap_search_user_password",
            self.secrets.get("authentication-openldap-search-password"),
        )
        pulumi.export("guacamole_container_group_name", guacamole.container_group_name)
        pulumi.export(
            "guacamole_postgresql_password",
            self.secrets.get("guacamole-postgresql-password"),
        )
        pulumi.export(
            "guacamole_postgresql_server_name", guacamole.postgresql_server_name
        )
        pulumi.export("guacamole_resource_group_name", guacamole.resource_group_name)
        pulumi.export("guacamole_share_caddy", guacamole.file_share_caddy_name)
        pulumi.export("storage_account_key", state_storage.access_key)
        pulumi.export("storage_account_name", state_storage.account_name)
