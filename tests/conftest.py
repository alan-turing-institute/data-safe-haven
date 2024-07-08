from pathlib import Path
from shutil import which
from subprocess import run

import yaml
from azure.core.credentials import AccessToken, TokenCredential
from azure.mgmt.resource.subscriptions.models import Subscription
from pulumi.automation import ProjectSettings
from pytest import fixture

import data_safe_haven.commands.sre as sre_mod
import data_safe_haven.config.context_manager as context_mod
import data_safe_haven.logging.logger
from data_safe_haven.config import (
    Context,
    ContextManager,
    DSHPulumiConfig,
    DSHPulumiProject,
    SHMConfig,
    SREConfig,
)
from data_safe_haven.config.config_sections import (
    ConfigSectionAzure,
    ConfigSectionSHM,
    ConfigSectionSRE,
    ConfigSubsectionRemoteDesktopOpts,
)
from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.external import AzureSdk, PulumiAccount
from data_safe_haven.external.api.credentials import AzureSdkCredential
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.infrastructure.project_manager import ProjectManager
from data_safe_haven.logging import init_logging


@fixture
def azure_config():
    return ConfigSectionAzure(
        location="uksouth",
        subscription_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
    )


@fixture
def context(context_dict):
    return Context(**context_dict)


@fixture
def context_dict():
    return {
        "admin_group_name": "Acme Admins",
        "description": "Acme Deployment",
        "name": "acmedeployment",
        "subscription_name": "Data Safe Haven Acme",
    }


@fixture
def context_no_secrets(monkeypatch, context_dict) -> Context:
    monkeypatch.setattr(Context, "pulumi_secrets_provider_url", None)
    return Context(**context_dict)


@fixture
def context_manager(context_yaml) -> ContextManager:
    return ContextManager.from_yaml(context_yaml)


@fixture
def context_tmpdir(context_dict, tmpdir, monkeypatch) -> tuple[Context, Path]:
    monkeypatch.setattr(context_mod, "config_dir", lambda: Path(tmpdir))
    return (Context(**context_dict), tmpdir)


@fixture
def context_yaml():
    content = """---
    selected: acmedeployment
    contexts:
        acmedeployment:
            admin_group_name: Acme Admins
            description: Acme Deployment
            name: acmedeployment
            subscription_name: Data Safe Haven Acme
        gems:
            admin_group_name: Gems Admins
            description: Gems
            name: gems
            subscription_name: Data Safe Haven Gems
    """
    return yaml.dump(yaml.safe_load(content))


@fixture
def local_project_settings(context_no_secrets, mocker):  # noqa: ARG001
    """Overwrite adjust project settings to work locally, no secrets"""
    mocker.patch.object(
        ProjectManager,
        "project_settings",
        ProjectSettings(
            name="data-safe-haven",
            runtime="python",
        ),
    )


@fixture(autouse=True, scope="session")
def local_pulumi_login():
    pulumi_path = which("pulumi")
    run([pulumi_path, "login", "--local"], check=False)
    yield
    run([pulumi_path, "logout"], check=False)


@fixture(autouse=True, scope="session")
def log_directory(session_mocker, tmp_path_factory):
    session_mocker.patch.object(
        data_safe_haven.logging.logger, "logfile_name", return_value="test.log"
    )
    log_dir = tmp_path_factory.mktemp("logs")
    session_mocker.patch.object(
        data_safe_haven.logging.logger, "log_dir", return_value=log_dir
    )
    init_logging()
    return log_dir


@fixture
def mock_azureapi_get_subscription(mocker):
    subscription = Subscription()
    subscription.display_name = "Data Safe Haven Acme"
    subscription.subscription_id = "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd"
    subscription.tenant_id = "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd"
    mocker.patch.object(
        AzureSdk,
        "get_subscription",
        return_value=subscription,
    )


@fixture
def mock_azureapicredential_get_credential(mocker):
    class MockCredential(TokenCredential):
        def get_token(*args, **kwargs):  # noqa: ARG002
            return AccessToken("dummy-token", 0)

    mocker.patch.object(
        AzureSdkCredential,
        "get_credential",
        return_value=MockCredential(),
    )


@fixture
def mock_azureapicredential_get_credential_failure(mocker):
    def fail_get_credential():
        print("mock get_credential")  # noqa: T201
        msg = "mock get_credential error"
        raise DataSafeHavenAzureError(msg)

    mocker.patch.object(
        AzureSdkCredential,
        "get_credential",
        side_effect=fail_get_credential,
    )


@fixture
def mock_install_plugins(mocker):
    mocker.patch.object(ProjectManager, "install_plugins", return_value=None)


@fixture
def mock_key_vault_key(monkeypatch):
    class MockKeyVaultKey:
        def __init__(self, key_name, key_vault_name):
            self.key_name = key_name
            self.key_vault_name = key_vault_name
            self.id = "mock_key/version"

    def mock_get_keyvault_key(self, key_name, key_vault_name):  # noqa: ARG001
        return MockKeyVaultKey(key_name, key_vault_name)

    monkeypatch.setattr(AzureSdk, "get_keyvault_key", mock_get_keyvault_key)


@fixture
def offline_pulumi_account(monkeypatch):
    """Overwrite PulumiAccount so that it runs locally"""
    monkeypatch.setattr(
        PulumiAccount, "env", {"PULUMI_CONFIG_PASSPHRASE": "passphrase"}
    )


@fixture
def pulumi_config(
    pulumi_project: DSHPulumiProject, pulumi_project_other: DSHPulumiProject
) -> DSHPulumiConfig:
    return DSHPulumiConfig(
        encrypted_key="CALbHybtRdxKjSnr9UYY",
        projects={
            "acmedeployment": pulumi_project,
            "other_project": pulumi_project_other,
        },
    )


@fixture
def pulumi_config_empty() -> DSHPulumiConfig:
    return DSHPulumiConfig(
        encrypted_key=None,
        projects={},
    )


@fixture
def pulumi_config_no_key(
    pulumi_project: DSHPulumiProject,
    pulumi_project_other: DSHPulumiProject,
    pulumi_project_sandbox: DSHPulumiProject,
) -> DSHPulumiConfig:
    return DSHPulumiConfig(
        encrypted_key=None,
        projects={
            "acmedeployment": pulumi_project,
            "other_project": pulumi_project_other,
            "sandbox": pulumi_project_sandbox,
        },
    )


@fixture
def pulumi_project(pulumi_project_stack_config) -> DSHPulumiProject:
    return DSHPulumiProject(
        stack_config=pulumi_project_stack_config,
    )


@fixture
def pulumi_project_other() -> DSHPulumiProject:
    return DSHPulumiProject(
        stack_config={
            "azure-native:location": "uksouth",
            "azure-native:subscriptionId": "def",
            "data-safe-haven:variable": "-3",
        },
    )


@fixture
def pulumi_project_sandbox() -> DSHPulumiProject:
    return DSHPulumiProject(
        stack_config={
            "azure-native:location": "uksouth",
            "azure-native:subscriptionId": "ghi",
            "data-safe-haven:variable": "8",
        },
    )


@fixture
def pulumi_project_stack_config():
    return {
        "azure-native:location": "uksouth",
        "azure-native:subscriptionId": "abc",
        "data-safe-haven:variable": "5",
    }


@fixture
def pulumi_config_yaml() -> str:
    content = """---
    encrypted_key: CALbHybtRdxKjSnr9UYY
    projects:
        acmedeployment:
            stack_config:
                azure-native:location: uksouth
                azure-native:subscriptionId: abc
                data-safe-haven:variable: 5
        other_project:
            stack_config:
                azure-native:location: uksouth
                azure-native:subscriptionId: def
                data-safe-haven:variable: -3
    """
    return yaml.dump(yaml.safe_load(content))


@fixture
def remote_desktop_config() -> ConfigSubsectionRemoteDesktopOpts:
    return ConfigSubsectionRemoteDesktopOpts()


@fixture
def shm_config(
    azure_config: ConfigSectionAzure, shm_config_section: ConfigSectionSHM
) -> SHMConfig:
    return SHMConfig(
        azure=azure_config,
        shm=shm_config_section,
    )


@fixture
def shm_config_alternate(
    azure_config: ConfigSectionAzure, shm_config_section: ConfigSectionSHM
) -> SHMConfig:
    shm_config_section.fqdn = "shm-alternate.acme.com"
    return SHMConfig(
        azure=azure_config,
        shm=shm_config_section,
    )


@fixture
def shm_config_file(shm_config_yaml: str, tmp_path: Path) -> Path:
    config_file_path = tmp_path / "shm.yaml"
    with open(config_file_path, "w") as f:
        f.write(shm_config_yaml)
    return config_file_path


@fixture
def shm_config_section(shm_config_section_dict):
    return ConfigSectionSHM(**shm_config_section_dict)


@fixture
def shm_config_section_dict():
    return {
        "admin_group_id": "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        "entra_tenant_id": "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        "fqdn": "shm.acme.com",
    }


@fixture
def shm_config_yaml():
    content = """---
    azure:
        location: uksouth
        subscription_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
        tenant_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
    shm:
        admin_group_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
        entra_tenant_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
        fqdn: shm.acme.com
    """
    return yaml.dump(yaml.safe_load(content))


@fixture
def sre_config_file(sre_config_yaml, tmp_path):
    config_file_path = tmp_path / "config.yaml"
    with open(config_file_path, "w") as f:
        f.write(sre_config_yaml)
    return config_file_path


@fixture
def sre_config(
    azure_config: ConfigSectionAzure,
    sre_config_section: ConfigSectionSRE,
) -> SREConfig:
    return SREConfig(
        azure=azure_config,
        description="Sandbox Project",
        name="sandbox",
        sre=sre_config_section,
    )


@fixture
def sre_config_alternate(
    azure_config: ConfigSectionAzure,
    sre_config_section: ConfigSectionSRE,
) -> SREConfig:
    sre_config_section.admin_ip_addresses = ["2.3.4.5"]
    return SREConfig(
        azure=azure_config,
        description="Alternative Project",
        name="alternative",
        sre=sre_config_section,
    )


@fixture
def sre_config_section() -> ConfigSectionSRE:
    return ConfigSectionSRE(
        admin_email_address="admin@example.com",
        admin_ip_addresses=["1.2.3.4"],
        timezone="Europe/London",
    )


@fixture
def sre_config_yaml():
    content = """---
    azure:
        location: uksouth
        subscription_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
        tenant_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
    description: Sandbox Project
    name: sandbox
    sre:
        admin_email_address: admin@example.com
        admin_ip_addresses:
        - 1.2.3.4/32
        data_provider_ip_addresses: []
        databases: []
        remote_desktop:
            allow_copy: false
            allow_paste: false
        research_user_ip_addresses: []
        software_packages: none
        timezone: Europe/London
        workspace_skus: []
    """
    return yaml.dump(yaml.safe_load(content))


@fixture
def sre_project_manager(
    context_no_secrets,
    sre_config,
    pulumi_config_no_key,
    local_project_settings,  # noqa: ARG001
    mock_azureapi_get_subscription,  # noqa: ARG001
    mock_azureapicredential_get_credential,  # noqa: ARG001
    offline_pulumi_account,  # noqa: ARG001
):
    return SREProjectManager(
        context=context_no_secrets,
        config=sre_config,
        pulumi_config=pulumi_config_no_key,
    )
