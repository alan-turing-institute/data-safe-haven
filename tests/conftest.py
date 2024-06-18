from pathlib import Path
from shutil import which
from subprocess import run

from pulumi.automation import ProjectSettings
from pytest import fixture

import data_safe_haven.context.context_settings as context_mod
from data_safe_haven.config import (
    Config,
    DSHPulumiConfig,
    DSHPulumiProject,
)
from data_safe_haven.config.config import (
    ConfigSectionAzure,
    ConfigSectionSHM,
    ConfigSectionSRE,
    ConfigSubsectionRemoteDesktopOpts,
)
from data_safe_haven.context import Context
from data_safe_haven.external import AzureApi
from data_safe_haven.infrastructure import SHMProjectManager
from data_safe_haven.infrastructure.project_manager import (
    AzureCliSingleton,
    ProjectManager,
    PulumiAccount,
)


@fixture(autouse=True, scope="session")
def local_pulumi_login():
    pulumi_path = which("pulumi")
    run([pulumi_path, "login", "--local"], check=False)
    yield
    run([pulumi_path, "logout"], check=False)


@fixture(autouse=True)
def log_directory(monkeypatch, tmp_path):
    monkeypatch.setenv("DSH_LOG_DIRECTORY", tmp_path)
    return tmp_path


@fixture
def context_dict():
    return {
        "admin_group_id": "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        "location": "uksouth",
        "name": "Acme Deployment",
        "subscription_name": "Data Safe Haven Acme",
    }


@fixture
def context(context_dict):
    return Context(**context_dict)


@fixture
def context_no_secrets(monkeypatch, context_dict):
    monkeypatch.setattr(Context, "pulumi_secrets_provider_url", None)
    return Context(**context_dict)


@fixture
def context_tmpdir(context_dict, tmpdir, monkeypatch):
    monkeypatch.setattr(context_mod, "config_dir", lambda: Path(tmpdir))
    return Context(**context_dict), tmpdir


@fixture
def config_yaml():
    return """azure:
  subscription_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
  tenant_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
shm:
  admin_email_address: admin@example.com
  admin_ip_addresses:
  - 0.0.0.0/32
  entra_tenant_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
  fqdn: shm.acme.com
  timezone: UTC
sres:
  sre1:
    data_provider_ip_addresses: []
    databases: []
    remote_desktop:
      allow_copy: false
      allow_paste: false
    research_user_ip_addresses: []
    software_packages: none
    workspace_skus: []
  sre2:
    data_provider_ip_addresses: []
    databases: []
    remote_desktop:
      allow_copy: true
      allow_paste: true
    research_user_ip_addresses: []
    software_packages: none
    workspace_skus: []
"""


@fixture
def config_file(config_yaml, tmp_path):
    config_file_path = tmp_path / "config.yaml"
    with open(config_file_path, "w") as f:
        f.write(config_yaml)
    return config_file_path


@fixture
def azure_config():
    return ConfigSectionAzure(
        subscription_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
    )


@fixture
def shm_config():
    return ConfigSectionSHM(
        admin_email_address="admin@example.com",
        admin_ip_addresses=["0.0.0.0"],  # noqa: S104
        entra_tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        fqdn="shm.acme.com",
        timezone="UTC",
    )


@fixture
def remote_desktop_config():
    return ConfigSubsectionRemoteDesktopOpts()


@fixture
def config_no_sres(azure_config, shm_config):
    return Config(
        azure=azure_config,
        shm=shm_config,
    )


@fixture
def config_sres(azure_config, shm_config):
    sre_config_1 = ConfigSectionSRE()
    sre_config_2 = ConfigSectionSRE(
        remote_desktop=ConfigSubsectionRemoteDesktopOpts(
            allow_copy=True, allow_paste=True
        )
    )
    return Config(
        azure=azure_config,
        shm=shm_config,
        sres={
            "sre1": sre_config_1,
            "sre2": sre_config_2,
        },
    )


@fixture
def stack_config():
    return {
        "azure-native:location": "uksouth",
        "azure-native:subscriptionId": "abc",
        "data-safe-haven:variable": "5",
    }


@fixture
def pulumi_project(stack_config):
    return DSHPulumiProject(
        stack_config=stack_config,
    )


@fixture
def pulumi_project2():
    return DSHPulumiProject(
        stack_config={
            "azure-native:location": "uksouth",
            "azure-native:subscriptionId": "def",
            "data-safe-haven:variable": -3,
        },
    )


@fixture
def pulumi_config(pulumi_project, pulumi_project2):
    return DSHPulumiConfig(
        encrypted_key="CALbHybtRdxKjSnr9UYY",
        projects={"acmedeployment": pulumi_project, "other_project": pulumi_project2},
    )


@fixture
def pulumi_config_no_key(pulumi_project, pulumi_project2):
    return DSHPulumiConfig(
        encrypted_key=None,
        projects={"acmedeployment": pulumi_project, "other_project": pulumi_project2},
    )


@fixture
def pulumi_config_empty():
    return DSHPulumiConfig(
        encrypted_key=None,
        projects={},
    )


@fixture
def pulumi_config_yaml():
    return """encrypted_key: CALbHybtRdxKjSnr9UYY
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


@fixture
def mock_key_vault_key(monkeypatch):
    class MockKeyVaultKey:
        def __init__(self, key_name, key_vault_name):
            self.key_name = key_name
            self.key_vault_name = key_vault_name
            self.id = "mock_key/version"

    def mock_get_keyvault_key(self, key_name, key_vault_name):  # noqa: ARG001
        return MockKeyVaultKey(key_name, key_vault_name)

    monkeypatch.setattr(AzureApi, "get_keyvault_key", mock_get_keyvault_key)


@fixture
def mock_azure_cli_confirm(monkeypatch):
    """Always pass AzureCliSingleton.confirm without attempting login"""
    monkeypatch.setattr(AzureCliSingleton, "confirm", lambda self: None)  # noqa: ARG005


@fixture
def mock_install_plugins(monkeypatch):
    """Skip installing Pulumi plugins"""
    monkeypatch.setattr(
        ProjectManager, "install_plugins", lambda self: None  # noqa: ARG005
    )


@fixture
def offline_pulumi_account(monkeypatch, mock_azure_cli_confirm):  # noqa: ARG001
    """Overwrite PulumiAccount so that it runs locally"""
    monkeypatch.setattr(
        PulumiAccount, "env", {"PULUMI_CONFIG_PASSPHRASE": "passphrase"}
    )


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


@fixture
def shm_stack_manager(
    context_no_secrets,
    config_sres,
    pulumi_config_no_key,
    mock_azure_cli_confirm,  # noqa: ARG001
    mock_install_plugins,  # noqa: ARG001
    mock_key_vault_key,  # noqa: ARG001
    offline_pulumi_account,  # noqa: ARG001
    local_project_settings,  # noqa: ARG001
):
    return SHMProjectManager(
        context=context_no_secrets,
        config=config_sres,
        pulumi_config=pulumi_config_no_key,
    )
