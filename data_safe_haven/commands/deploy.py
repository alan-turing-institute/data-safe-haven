"""Command-line application for deploying a Data Safe Haven component, delegating the details to a subcommand"""

from typing import Annotated, Optional

import typer

from data_safe_haven.config import Config, DSHPulumiConfig
from data_safe_haven.context import ContextSettings
from data_safe_haven.exceptions import DataSafeHavenError
from data_safe_haven.external import GraphApi
from data_safe_haven.functions import sanitise_sre_name
from data_safe_haven.infrastructure import SHMProjectManager, SREProjectManager
from data_safe_haven.provisioning import SREProvisioningManager
from data_safe_haven.utility import LoggingSingleton

deploy_command_group = typer.Typer()


@deploy_command_group.command()
def shm(
    force: Annotated[
        Optional[bool],  # noqa: UP007
        typer.Option(
            "--force",
            "-f",
            help="Force this operation, cancelling any others that are in progress.",
        ),
    ] = None,
) -> None:
    """Deploy a Safe Haven Management component"""
    context = ContextSettings.from_file().assert_context()
    config = Config.from_remote(context)
    pulumi_config = DSHPulumiConfig.from_remote_or_create(context, projects={})
    pulumi_project = pulumi_config.create_or_select_project(context.shm_name)

    try:
        # Add the SHM domain to AzureAD as a custom domain
        graph_api = GraphApi(
            tenant_id=config.shm.aad_tenant_id,
            default_scopes=[
                "Application.ReadWrite.All",
                "Domain.ReadWrite.All",
                "Group.ReadWrite.All",
            ],
        )
        verification_record = graph_api.add_custom_domain(config.shm.fqdn)

        # Initialise Pulumi stack
        stack = SHMProjectManager(context, config, pulumi_project)
        # Set Azure options
        stack.add_option("azure-native:location", context.location, replace=False)
        stack.add_option(
            "azure-native:subscriptionId",
            config.azure.subscription_id,
            replace=False,
        )
        stack.add_option("azure-native:tenantId", config.azure.tenant_id, replace=False)
        # Add necessary secrets
        stack.add_secret(
            "verification-azuread-custom-domain", verification_record, replace=False
        )

        # Deploy Azure infrastructure with Pulumi
        if force is None:
            stack.deploy()
        else:
            stack.deploy(force=force)

        # Add the SHM domain as a custom domain in AzureAD
        graph_api.verify_custom_domain(
            config.shm.fqdn,
            stack.output("networking")["fqdn_nameservers"],
        )
    except DataSafeHavenError as exc:
        # Note, would like to exit with a non-zero code here.
        # However, typer.Exit does not print the exception tree which is very unhelpful
        # for figuring out what went wrong.
        # print("Could not deploy Data Safe Haven Management environment.")
        # raise typer.Exit(code=1) from exc
        msg = f"Could not deploy Data Safe Haven Management environment.\n{exc}"
        raise DataSafeHavenError(msg) from exc
    finally:
        # Upload Pulumi config to blob storage
        pulumi_config.upload(context)


@deploy_command_group.command()
def sre(
    name: Annotated[str, typer.Argument(help="Name of SRE to deploy")],
    force: Annotated[
        Optional[bool],  # noqa: UP007
        typer.Option(
            "--force",
            "-f",
            help="Force this operation, cancelling any others that are in progress.",
        ),
    ] = None,
) -> None:
    """Deploy a Secure Research Environment"""
    logger = LoggingSingleton()
    context = ContextSettings.from_file().assert_context()
    config = Config.from_remote(context)
    pulumi_config = DSHPulumiConfig.from_remote(context)
    shm_pulumi_project = pulumi_config.create_or_select_project(context.shm_name)
    sre_name = sanitise_sre_name(name)
    sre_pulumi_project = pulumi_config.create_or_select_project(sre_name)

    try:
        # Exit if SRE name is not recognised
        if sre_name not in config.sre_names:
            logger.fatal(f"Could not find configuration details for SRE '{sre_name}'.")
            raise typer.Exit(1)

        # Load GraphAPI as this may require user-interaction that is not possible as
        # part of a Pulumi declarative command
        graph_api = GraphApi(
            tenant_id=config.shm.aad_tenant_id,
            default_scopes=[
                "Application.ReadWrite.All",
                "AppRoleAssignment.ReadWrite.All",
                "Directory.ReadWrite.All",
                "Group.ReadWrite.All",
            ],
        )

        # Initialise Pulumi stack
        shm_stack = SHMProjectManager(context, config, shm_pulumi_project)
        stack = SREProjectManager(
            context,
            config,
            sre_pulumi_project,
            sre_name,
            graph_api_token=graph_api.token,
        )
        # Set Azure options
        stack.add_option("azure-native:location", context.location, replace=False)
        stack.add_option(
            "azure-native:subscriptionId",
            config.azure.subscription_id,
            replace=False,
        )
        stack.add_option("azure-native:tenantId", config.azure.tenant_id, replace=False)
        # Load SHM stack outputs
        stack.add_option(
            "shm-firewall-private-ip-address",
            shm_stack.output("firewall")["private_ip_address"],
            replace=True,
        )
        stack.add_option(
            "shm-monitoring-automation_account_name",
            shm_stack.output("monitoring")["automation_account_name"],
            replace=True,
        )
        stack.add_option(
            "shm-monitoring-log_analytics_workspace_id",
            shm_stack.output("monitoring")["log_analytics_workspace_id"],
            replace=True,
        )
        stack.add_secret(
            "shm-monitoring-log_analytics_workspace_key",
            shm_stack.output("monitoring")["log_analytics_workspace_key"],
            replace=True,
        )
        stack.add_option(
            "shm-monitoring-resource_group_name",
            shm_stack.output("monitoring")["resource_group_name"],
            replace=True,
        )
        stack.add_option(
            "shm-networking-private_dns_zone_base_id",
            shm_stack.output("networking")["private_dns_zone_base_id"],
            replace=True,
        )
        stack.add_option(
            "shm-networking-resource_group_name",
            shm_stack.output("networking")["resource_group_name"],
            replace=True,
        )
        stack.add_option(
            "shm-networking-subnet_subnet_monitoring_prefix",
            shm_stack.output("networking")["subnet_monitoring_prefix"],
            replace=True,
        )
        stack.add_option(
            "shm-networking-virtual_network_name",
            shm_stack.output("networking")["virtual_network_name"],
            replace=True,
        )

        # Deploy Azure infrastructure with Pulumi
        if force is None:
            stack.deploy()
        else:
            stack.deploy(force=force)

        # Provision SRE with anything that could not be done in Pulumi
        manager = SREProvisioningManager(
            graph_api_token=graph_api.token,
            location=context.location,
            sre_name=sre_name,
            sre_stack=stack,
            subscription_name=context.subscription_name,
            timezone=config.shm.timezone,
        )
        manager.run()
    except DataSafeHavenError as exc:
        msg = f"Could not deploy Secure Research Environment {sre_name}.\n{exc}"
        raise DataSafeHavenError(msg) from exc
    finally:
        # Upload Pulumi config to blob storage
        pulumi_config.upload(context)
