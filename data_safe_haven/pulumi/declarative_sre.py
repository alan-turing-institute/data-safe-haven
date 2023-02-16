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
                shm_networking_resource_group_name=self.cfg.shm.networking.resource_group_name,
                shm_zone_name=self.cfg.shm.fqdn,
                sre_index=self.cfg.sre[self.sre_name].index,
                shm_virtual_network_name=self.cfg.shm.networking.virtual_network_name,
            ),
        )
        networking.sre_fqdn.apply(lambda s: print(f"sre_fqdn {s}"))

        # Define state storage
        state = SREStateComponent(
            "sre_state",
            self.stack_name,
            self.sre_name,
            SREStateProps(
                admin_email_address=self.cfg.shm.admin_email_address,
                admin_group_id=self.cfg.azure.admin_group_id,
                dns_record=networking.shm_ns_record,
                location=self.cfg.azure.location,
                networking_resource_group=networking.resource_group,
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
                key_vault_certificate_id=state.certificate_secret_id,
                key_vault_identity=state.managed_identity,
                resource_group=networking.resource_group,
                subnet_application_gateway=networking.subnet_application_gateway,
                subnet_guacamole_containers=networking.subnet_guacamole_containers,
                sre_fqdn=networking.sre_fqdn,
            ),
        )

        # Define containerised remote desktop gateway
        remote_desktop = SRERemoteDesktopComponent(
            "sre_remote_desktop",
            self.stack_name,
            self.sre_name,
            SRERemoteDesktopProps(
                aad_application_name=f"sre-{self.sre_name}-azuread-guacamole",
                aad_application_fqdn=networking.sre_fqdn,
                aad_auth_token=self.secrets.require("token-azuread-graphapi"),
                aad_tenant_id=self.cfg.shm.aad_tenant_id,
                database_password=self.secrets.require("password-user-database-admin"),
                location=self.cfg.azure.location,
                subnet_guacamole_containers=networking.subnet_guacamole_containers,
                subnet_guacamole_database=networking.subnet_guacamole_database,
                storage_account_name=state.account_name,
                storage_account_resource_group=state.resource_group_name,
                virtual_network_resource_group=networking.resource_group,
                virtual_network=networking.virtual_network,
            ),
        )

        srd = SREResearchDesktopComponent(
            "sre_secure_research_desktop",
            self.stack_name,
            self.sre_name,
            SREResearchDesktopProps(
                admin_password=self.secrets.require(
                    "password-secure-research-desktop-admin"
                ),
                domain_sid=self.cfg.shm.domain_controllers.domain_sid,
                ldap_root_dn=self.cfg.shm.domain_controllers.ldap_root_dn,
                ldap_search_password=self.secrets.require(
                    "password-domain-ldap-searcher"
                ),
                ldap_server_ip=self.cfg.shm.domain_controllers.ldap_server_ip,
                location=self.cfg.azure.location,
                security_group_name=self.cfg.sre[self.sre_name].security_group_name,
                subnet_research_desktops=networking.subnet_research_desktops,
                virtual_network_resource_group=networking.resource_group,
                virtual_network=networking.virtual_network,
                vm_details=self.cfg.sre[self.sre_name].research_desktops,
            ),
        )

        # Export values for later use
        pulumi.export("remote_desktop", remote_desktop.exports)
        pulumi.export("srd", srd.exports)
