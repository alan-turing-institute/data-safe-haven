"""Pulumi component for SHM domain controllers"""
from collections.abc import Mapping, Sequence

from pulumi import ComponentResource, Input, Output, ResourceOptions
from pulumi_azure_native import network, resources

from data_safe_haven.infrastructure.common import get_name_from_subnet
from data_safe_haven.infrastructure.components import (
    AutomationDscNode,
    AutomationDscNodeProps,
    RemoteScript,
    RemoteScriptProps,
    VMComponent,
    WindowsVMComponentProps,
    WrappedAutomationAccount,
    WrappedLogAnalyticsWorkspace,
)
from data_safe_haven.resources import resources_path
from data_safe_haven.utility import FileReader


class SHMDomainControllersProps:
    """Properties for SHMDomainControllersComponent"""

    def __init__(
        self,
        automation_account: Input[WrappedAutomationAccount],
        automation_account_modules: Input[Sequence[str]],
        automation_account_private_dns: Input[network.PrivateDnsZoneGroup],
        domain_fqdn: Input[str],
        domain_netbios_name: Input[str],
        location: Input[str],
        log_analytics_workspace: Input[WrappedLogAnalyticsWorkspace],
        password_domain_admin: Input[str],
        password_domain_azuread_connect: Input[str],
        password_domain_computer_manager: Input[str],
        password_domain_searcher: Input[str],
        private_ip_address: Input[str],
        subnet_identity_servers: Input[network.GetSubnetResult],
        subscription_name: Input[str],
        virtual_network_name: Input[str],
        virtual_network_resource_group_name: Input[str],
    ) -> None:
        self.automation_account = automation_account
        self.automation_account_modules = automation_account_modules
        self.automation_account_private_dns = automation_account_private_dns
        self.domain_fqdn = domain_fqdn
        self.domain_root_dn = Output.from_input(domain_fqdn).apply(
            lambda dn: f"DC={dn.replace('.', ',DC=')}"
        )
        self.domain_netbios_name = Output.from_input(domain_netbios_name).apply(
            lambda n: n[:15]
        )  # maximum of 15 characters
        self.location = location
        self.log_analytics_workspace = log_analytics_workspace
        self.password_domain_admin = password_domain_admin
        self.password_domain_azuread_connect = password_domain_azuread_connect
        self.password_domain_computer_manager = password_domain_computer_manager
        self.password_domain_searcher = password_domain_searcher
        self.private_ip_address = private_ip_address
        self.subnet_name = Output.from_input(subnet_identity_servers).apply(
            get_name_from_subnet
        )
        self.subscription_name = subscription_name
        # Note that usernames have a maximum of 20 characters
        self.username_domain_admin = "dshdomainadmin"
        self.username_domain_azuread_connect = "dshazureadsync"
        self.username_domain_computer_manager = "dshcomputermanager"
        self.username_domain_searcher = "dshldapsearcher"
        self.virtual_network_name = virtual_network_name
        self.virtual_network_resource_group_name = virtual_network_resource_group_name


class SHMDomainControllersComponent(ComponentResource):
    """Deploy SHM secrets with Pulumi"""

    def __init__(
        self,
        name: str,
        stack_name: str,
        props: SHMDomainControllersProps,
        opts: ResourceOptions | None = None,
        tags: Input[Mapping[str, Input[str]]] | None = None,
    ) -> None:
        super().__init__("dsh:shm:DomainControllersComponent", name, {}, opts)
        child_opts = ResourceOptions.merge(opts, ResourceOptions(parent=self))
        child_tags = tags if tags else {}

        # Deploy resource group
        resource_group = resources.ResourceGroup(
            f"{self._name}_resource_group",
            location=props.location,
            resource_group_name=f"{stack_name}-rg-identity",
            opts=child_opts,
            tags=child_tags,
        )

        # Create the Domain Controller
        # We use the domain admin credentials here as the VM admin is promoted to a
        # domain admin when setting up the domain
        primary_domain_controller = VMComponent(
            f"{self._name}_primary_domain_controller",
            WindowsVMComponentProps(
                admin_password=props.password_domain_admin,
                admin_username=props.username_domain_admin,
                ip_address_public=False,
                ip_address_private=props.private_ip_address,
                location=props.location,
                log_analytics_workspace=props.log_analytics_workspace,
                resource_group_name=resource_group.name,
                subnet_name=props.subnet_name,
                virtual_network_name=props.virtual_network_name,
                virtual_network_resource_group_name=props.virtual_network_resource_group_name,
                vm_name=f"{stack_name[:11]}-dc1",
                vm_size="Standard_DS2_v2",
            ),
            opts=child_opts,
            tags=child_tags,
        )
        # Register the primary domain controller for automated DSC
        dsc_configuration_name = "PrimaryDomainController"
        dsc_reader = FileReader(
            resources_path
            / "desired_state_configuration"
            / f"{dsc_configuration_name}.ps1"
        )
        primary_domain_controller_dsc_node = AutomationDscNode(
            f"{self._name}_primary_domain_controller_dsc_node",
            AutomationDscNodeProps(
                automation_account=props.automation_account,
                configuration_name=dsc_configuration_name,
                dsc_description="DSC for Data Safe Haven primary domain controller",
                dsc_file=dsc_reader,
                dsc_parameters=Output.all(
                    AzureADConnectPassword=props.password_domain_azuread_connect,
                    AzureADConnectUsername=props.username_domain_azuread_connect,
                    DomainAdministratorPassword=props.password_domain_admin,
                    DomainAdministratorUsername=props.username_domain_admin,
                    DomainComputerManagerPassword=props.password_domain_computer_manager,
                    DomainComputerManagerUsername=props.username_domain_computer_manager,
                    DomainName=props.domain_fqdn,
                    DomainNetBios=props.domain_netbios_name,
                    DomainRootDn=props.domain_root_dn,
                    LDAPSearcherPassword=props.password_domain_searcher,
                    LDAPSearcherUsername=props.username_domain_searcher,
                ),
                dsc_required_modules=props.automation_account_modules,
                location=props.location,
                subscription_name=props.subscription_name,
                vm_name=primary_domain_controller.vm_name,
                vm_resource_group_name=resource_group.name,
            ),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    depends_on=[
                        props.automation_account,
                        props.automation_account_private_dns,
                        primary_domain_controller,
                    ],
                    parent=primary_domain_controller,
                ),
            ),
            tags=child_tags,
        )
        # Extract the domain SID
        domain_sid_script = FileReader(
            resources_path / "active_directory" / "get_ad_sid.ps1"
        )
        domain_sid = RemoteScript(
            f"{self._name}_get_ad_sid",
            RemoteScriptProps(
                force_refresh=True,
                script_contents=domain_sid_script.file_contents(),
                script_hash=domain_sid_script.sha256(),
                script_parameters={},
                subscription_name=props.subscription_name,
                vm_name=primary_domain_controller.vm_name,
                vm_resource_group_name=resource_group.name,
            ),
            opts=ResourceOptions.merge(
                child_opts,
                ResourceOptions(
                    depends_on=[
                        primary_domain_controller,
                        primary_domain_controller_dsc_node,
                    ],
                    parent=primary_domain_controller_dsc_node,
                ),
            ),
        )

        # Register outputs
        self.resource_group_name = resource_group.name

        # Register exports
        self.exports = {
            "domain_sid": domain_sid.script_output,
            "ldap_root_dn": props.domain_root_dn,
            "ldap_search_username": props.username_domain_searcher,
            "ldap_server_ip": primary_domain_controller.ip_address_private,
            "netbios_name": props.domain_netbios_name,
            "resource_group_name": resource_group.name,
            "vm_name": primary_domain_controller.vm_name,
        }
