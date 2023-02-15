"""Pulumi declarative program"""
# Standard library imports
import pathlib

# Third party imports
import pulumi

# Local imports
from data_safe_haven.config import Config
from .components.sre_application_gateway import (
    SREApplicationGatewayComponent,
    SREApplicationGatewayProps,
)
from .components.sre_networking import SRENetworkingComponent, SRENetworkingProps
from .components.sre_remote_desktop import (
    SRERemoteDesktopComponent,
    SRERemoteDesktopProps,
)
from .components.sre_research_desktop import (
    SREResearchDesktopComponent,
    SREResearchDesktopProps,
)
from .components.sre_state import SREStateComponent, SREStateProps


class DeclarativeSRE:
    """Deploy with Pulumi"""

    def __init__(self, config: Config, shm_name: str, sre_name: str):
        self.cfg = config
        self.shm_name = shm_name
        self.sre_name = sre_name
        self.stack_name = f"shm-{shm_name}-sre-{sre_name}"

    def work_dir(self, base_path: pathlib.Path):
        return base_path / f"shm-{self.shm_name}" / f"sre-{self.sre_name}"

    def run(self):
        # Load pulumi configuration secrets
        self.secrets = pulumi.Config()

        # Define networking
        networking = SRENetworkingComponent(
            "sre_networking",
            self.stack_name,
            self.sre_name,
            SRENetworkingProps(
                location=self.cfg.azure.location,
                shm_fqdn=self.cfg.shm.fqdn,
                shm_networking_resource_group_name=f"rg-shm-{self.shm_name}-networking",
                shm_zone_name=self.cfg.shm.fqdn,
                sre_index=self.cfg.sre[self.sre_name].index,
                shm_virtual_network_name=self.cfg.shm.networking.virtual_network_name,
            ),
        )

        # Define state storage
        state = SREStateComponent(
            "sre_state",
            self.stack_name,
            self.sre_name,
            SREStateProps(
                admin_email_address=self.cfg.shm.admin_email_address,
                admin_group_id=self.cfg.azure.admin_group_id,
                location=self.cfg.azure.location,
                networking_resource_group_name=networking.resource_group_name,
                sre_fqdn=networking.sre_fqdn,
                subscription_name=self.cfg.subscription_name,
                tenant_id=self.cfg.azure.tenant_id,
            ),
        )

        # Define frontend application gateway
        application_gateway = SREApplicationGatewayComponent(
            "sre_application_gateway",
            self.stack_name,
            self.sre_name,
            SREApplicationGatewayProps(
                ip_address_public_id=networking.public_ip_id,
                ip_addresses_guacamole=networking.guacamole_containers["ip_addresses"],
                key_vault_certificate_id=state.certificate_secret_id,
                key_vault_identity=state.managed_identity.id,
                resource_group_name=networking.resource_group_name,
                subnet_name=networking.application_gateway["subnet_name"],
                sre_fqdn=state.sre_fqdn,
                virtual_network_name=networking.virtual_network.name,
            ),
        )

        # Define containerised remote desktop gateway
        remote_desktop = SRERemoteDesktopComponent(
            "sre_remote_desktop",
            self.stack_name,
            self.sre_name,
            SRERemoteDesktopProps(
                aad_application_name=f"sre-{self.sre_name}-azuread-guacamole",
                aad_application_fqdn=state.sre_fqdn,
                aad_auth_token=self.secrets.require("token-azuread-graphapi"),
                aad_tenant_id=self.cfg.shm.aad_tenant_id,
                database_password=self.secrets.require("password-user-database-admin"),
                ip_address_container=networking.guacamole_containers["ip_addresses"][0],
                ip_address_database=networking.guacamole_database["ip_address"],
                location=self.cfg.azure.location,
                subnet_container_name=networking.guacamole_containers["subnet_name"],
                subnet_database_name=networking.guacamole_database["subnet_name"],
                storage_account_name=state.account_name,
                storage_account_resource_group=state.resource_group_name,
                virtual_network_resource_group_name=networking.resource_group_name,
                virtual_network=networking.virtual_network,
            ),
        )

        # Define containerised secure desktops
        srd = SREResearchDesktopComponent(
            "sre_secure_research_desktop",
            self.stack_name,
            self.sre_name,
            SREResearchDesktopProps(
                admin_password=self.secrets.require(
                    "password-secure-research-desktop-admin"
                ),
                domain_sid=self.cfg.shm.domain_controllers.domain_sid,
                ip_addresses=networking.secure_research_desktop["ip_addresses"],
                ldap_root_dn=self.cfg.shm.domain_controllers.ldap_root_dn,
                ldap_search_password=self.secrets.require(
                    "password-domain-ldap-searcher"
                ),
                ldap_server_ip=self.cfg.shm.domain_controllers.ldap_server_ip,
                location=self.cfg.azure.location,
                security_group_name=self.cfg.sre[self.sre_name].security_group_name,
                subnet_name=networking.secure_research_desktop["subnet_name"],
                virtual_network_resource_group_name=networking.resource_group_name,
                virtual_network=networking.virtual_network,
                vm_skus=[
                    (name, details["sku"])
                    for name, details in self.cfg.sre[
                        self.sre_name
                    ].research_desktops.items()
                ],
            ),
        )

        # Export values for later use
        pulumi.export("remote_desktop", remote_desktop.exports)
        pulumi.export("srd", srd.exports)
