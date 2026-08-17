from pathlib import Path
from shutil import which
from subprocess import run

import yaml
from azure.core.credentials import AccessToken, TokenCredential
from azure.mgmt.resource.resources.models import GenericResource
from azure.mgmt.resource.resources.operations import ResourcesOperations
from azure.mgmt.subscription.models import Subscription
from pulumi.automation import ProjectSettings
from pytest import FixtureRequest, MonkeyPatch, fixture
from pytest_mock import MockerFixture, MockType

import data_safe_haven.config.context_manager as context_mod
import data_safe_haven.logging.logger
from data_safe_haven import console
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
    ConfigSectionDockerHub,
    ConfigSectionSHM,
    ConfigSectionSRE,
    ConfigSubsectionRemoteDesktopOpts,
    ConfigSubsectionStorageQuotaGB,
)
from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.external import AzureSdk, PulumiAccount
from data_safe_haven.external.api.credentials import (
    AzureSdkCredential,
    GraphApiCredential,
)
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.infrastructure.project_manager import ProjectManager
from data_safe_haven.logging import init_logging
from data_safe_haven.upgrade import Upgrade


def pytest_configure(config) -> None:
    """Define constants for use across multiple tests"""
    config.guid_admin = "00edec65-b071-4d26-8779-a9fe791c6e14"
    config.guid_application = "aa78dceb-4116-4713-8554-cf2b3027e119"
    config.guid_entra = "48b2425b-5f2c-4cbd-9458-0441daa8994c"
    config.guid_subscription = "35ebced1-4e7a-4c1f-b634-c0886937085d"
    config.guid_tenant = "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd"
    config.guid_user = "80b4ccfd-73ef-41b7-bb22-8ec268ec040b"


@fixture
def config_section_azure(request: FixtureRequest) -> ConfigSectionAzure:
    return ConfigSectionAzure(
        location="uksouth",
        subscription_id=request.config.guid_subscription,
        tenant_id=request.config.guid_tenant,
    )


@fixture
def config_section_shm(config_section_shm_dict: dict[str, str]) -> ConfigSectionSHM:
    return ConfigSectionSHM(**config_section_shm_dict)


@fixture
def config_section_shm_dict(request: FixtureRequest) -> dict[str, str]:
    return {
        "admin_group_id": request.config.guid_admin,
        "entra_tenant_id": request.config.guid_entra,
        "fqdn": "shm.acme.com",
    }


@fixture
def config_section_dockerhub() -> ConfigSectionDockerHub:
    return ConfigSectionDockerHub(
        access_token="dummytoken",
        username="exampleuser",
    )


@fixture
def config_section_sre(
    config_subsection_remote_desktop: ConfigSubsectionRemoteDesktopOpts,
    config_subsection_storage_quota_gb: ConfigSubsectionStorageQuotaGB,
) -> ConfigSectionSRE:
    return ConfigSectionSRE(
        admin_email_address="admin@example.com",
        admin_ip_addresses=["1.2.3.4"],
        remote_desktop=config_subsection_remote_desktop,
        software_packages="pre-approved",
        storage_quota_gb=config_subsection_storage_quota_gb,
        timezone="Europe/London",
    )


@fixture
def config_section_sre_allow_internet(
    config_subsection_remote_desktop: ConfigSubsectionRemoteDesktopOpts,
    config_subsection_storage_quota_gb: ConfigSubsectionStorageQuotaGB,
) -> ConfigSectionSRE:
    return ConfigSectionSRE(
        admin_email_address="admin@example.com",
        admin_ip_addresses=["1.2.3.4"],
        allow_workspace_internet=True,
        remote_desktop=config_subsection_remote_desktop,
        software_packages="pre-approved",
        storage_quota_gb=config_subsection_storage_quota_gb,
        timezone="Europe/London",
    )


@fixture
def config_section_sre_any_packages(
    config_subsection_remote_desktop: ConfigSubsectionRemoteDesktopOpts,
    config_subsection_storage_quota_gb: ConfigSubsectionStorageQuotaGB,
) -> ConfigSectionSRE:
    return ConfigSectionSRE(
        admin_email_address="admin@example.com",
        admin_ip_addresses=["1.2.3.4"],
        remote_desktop=config_subsection_remote_desktop,
        software_packages="any",
        storage_quota_gb=config_subsection_storage_quota_gb,
        timezone="Europe/London",
    )


@fixture
def config_subsection_remote_desktop() -> ConfigSubsectionRemoteDesktopOpts:
    return ConfigSubsectionRemoteDesktopOpts(allow_copy=False, allow_paste=False)


@fixture
def config_subsection_storage_quota_gb() -> ConfigSubsectionStorageQuotaGB:
    return ConfigSubsectionStorageQuotaGB(home=100, shared=100)


@fixture
def context(context_dict: dict[str, str]) -> Context:
    return Context(**context_dict)


@fixture
def context_dict() -> dict[str, str]:
    return {
        "admin_group_name": "Acme Admins",
        "description": "Acme Deployment",
        "name": "acmedeployment",
        "subscription_name": "Data Safe Haven Acme",
    }


@fixture
def context_no_secrets(
    monkeypatch: MonkeyPatch, context_dict: dict[str, str]
) -> Context:
    monkeypatch.setattr(Context, "pulumi_secrets_provider_url", None)
    return Context(**context_dict)


@fixture
def context_manager(context_yaml: str) -> ContextManager:
    return ContextManager.from_yaml(context_yaml)


@fixture
def context_tmpdir(
    context_dict: dict[str, str], tmpdir, monkeypatch: MonkeyPatch
) -> tuple[Context, Path]:
    monkeypatch.setattr(context_mod, "config_dir", lambda: Path(tmpdir))
    return (Context(**context_dict), tmpdir)


@fixture
def context_yaml() -> str:
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
def local_project_settings(
    context_no_secrets: Context, mocker: MockerFixture  # noqa: ARG001
) -> None:
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
def mock_azuresdk_blob_exists(mocker: MockerFixture) -> None:
    mocker.patch.object(
        AzureSdk,
        "blob_exists",
        return_value=True,
    )


@fixture
def mock_azuresdk_get_subscription(
    mocker: MockerFixture, request: FixtureRequest
) -> None:
    subscription = Subscription()
    subscription.display_name = "Data Safe Haven Acme"
    subscription.subscription_id = request.config.guid_subscription
    mocker.patch.object(
        AzureSdk,
        "get_subscription",
        return_value=subscription,
    )


@fixture
def mock_azuresdk_get_subscription_name(mocker: MockerFixture) -> None:
    mocker.patch.object(
        AzureSdk,
        "get_subscription_name",
        return_value="Data Safe Haven Acme",
    )


@fixture
def mock_graphapi_get_credential(mocker: MockerFixture) -> None:
    class MockCredential(TokenCredential):
        def get_token(*args, **kwargs):  # noqa: ARG002
            return AccessToken("dummy-token", 0)

    mocker.patch.object(
        GraphApiCredential,
        "get_credential",
        return_value=MockCredential(),
    )


@fixture
def mock_azuresdk_get_credential(
    mocker: MockerFixture, request: FixtureRequest
) -> None:
    class MockCredential(TokenCredential):
        def get_token(*args, **kwargs) -> AccessToken:  # noqa: ARG002
            return AccessToken("dummy-token", 0)

        @property
        def tenant_id(self) -> str | None:
            return request.config.guid_tenant

    mocker.patch.object(
        AzureSdkCredential,
        "get_credential",
        return_value=MockCredential(),
    )

    AzureSdkCredential.tenant_id = mocker.PropertyMock(
        return_value=request.config.guid_tenant
    )


@fixture
def mock_azuresdk_get_credential_failure(mocker: MockerFixture) -> None:
    def fail_get_credential() -> DataSafeHavenAzureError:
        print("mock get_credential")  # noqa: T201
        msg = "mock get_credential error"
        raise DataSafeHavenAzureError(msg)

    mocker.patch.object(
        AzureSdkCredential,
        "get_credential",
        side_effect=fail_get_credential,
    )


@fixture
def mock_azuresdk_purge_keyvault(mocker: MockerFixture) -> None:
    mocker.patch.object(
        AzureSdk,
        "purge_keyvault",
        return_value=True,
    )


@fixture
def mock_azuresdk_remove_blob(mocker: MockerFixture) -> None:
    mocker.patch.object(
        AzureSdk,
        "remove_blob",
        return_value=None,
    )


@fixture
def mock_confirm_no(mocker: MockerFixture) -> MockType:
    return mocker.patch.object(
        console,
        "confirm",
        return_value=False,
    )


@fixture
def mock_confirm_yes(mocker: MockerFixture) -> MockType:
    return mocker.patch.object(
        console,
        "confirm",
        return_value=True,
    )


@fixture
def mock_install_plugins(mocker: MockerFixture) -> None:
    mocker.patch.object(ProjectManager, "install_plugins", return_value=None)


@fixture
def mock_key_vault_key(monkeypatch: MonkeyPatch) -> None:
    class MockKeyVaultKey:
        def __init__(self, key_name, key_vault_name) -> None:
            self.key_name = key_name
            self.key_vault_name = key_vault_name
            self.id = "mock_key/version"

        def mock_get_keyvault_key(self, key_name, key_vault_name):
            return MockKeyVaultKey(key_name, key_vault_name)

    monkeypatch.setattr(
        AzureSdk, "get_keyvault_key", MockKeyVaultKey.mock_get_keyvault_key
    )


@fixture
def mock_storage_exists(mocker: MockerFixture) -> MockType:
    return mocker.patch.object(
        AzureSdk,
        "storage_exists",
        return_value=True,
    )


@fixture
def offline_pulumi_account(monkeypatch: MonkeyPatch) -> None:
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
def pulumi_project(pulumi_project_stack_config: dict[str, str]) -> DSHPulumiProject:
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
def pulumi_project_stack_config() -> dict[str, str]:
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
def shm_config(
    config_section_azure: ConfigSectionAzure, config_section_shm: ConfigSectionSHM
) -> SHMConfig:
    return SHMConfig(
        azure=config_section_azure,
        shm=config_section_shm,
    )


@fixture
def shm_config_alternate(
    config_section_azure: ConfigSectionAzure, config_section_shm: ConfigSectionSHM
) -> SHMConfig:
    config_section_shm.fqdn = "shm-alternate.acme.com"
    return SHMConfig(
        azure=config_section_azure,
        shm=config_section_shm,
    )


@fixture
def shm_config_file(shm_config_yaml: str, tmp_path: Path) -> Path:
    config_file_path = tmp_path / "shm.yaml"
    with open(config_file_path, "w") as f:
        f.write(shm_config_yaml)
    return config_file_path


@fixture
def shm_config_yaml(request: FixtureRequest) -> str:
    content = (
        """---
    azure:
        location: uksouth
        subscription_id: guid_subscription
        tenant_id: guid_tenant
    shm:
        admin_group_id: guid_admin
        entra_tenant_id: guid_entra
        fqdn: shm.acme.com
    """.replace("guid_admin", request.config.guid_admin)
        .replace("guid_entra", request.config.guid_entra)
        .replace("guid_subscription", request.config.guid_subscription)
        .replace("guid_tenant", request.config.guid_tenant)
    )
    return yaml.dump(yaml.safe_load(content))


@fixture
def sre_config_file(sre_config_yaml: str, tmp_path: Path) -> Path:
    config_file_path = tmp_path / "config.yaml"
    with open(config_file_path, "w") as f:
        f.write(sre_config_yaml)
    return config_file_path


@fixture
def sre_config(
    config_section_azure: ConfigSectionAzure,
    config_section_dockerhub: ConfigSectionDockerHub,
    config_section_sre: ConfigSectionSRE,
) -> SREConfig:
    return SREConfig(
        azure=config_section_azure,
        description="Sandbox Project",
        dockerhub=config_section_dockerhub,
        name="sandbox",
        sre=config_section_sre,
    )


@fixture
def sre_config_any_packages(
    config_section_azure: ConfigSectionAzure,
    config_section_dockerhub: ConfigSectionDockerHub,
    config_section_sre_any_packages: ConfigSectionSRE,
) -> SREConfig:
    return SREConfig(
        azure=config_section_azure,
        description="Sandbox Project",
        dockerhub=config_section_dockerhub,
        name="sandbox",
        sre=config_section_sre_any_packages,
    )


@fixture
def sre_config_internet_allowed_preapproved_packages(
    config_section_azure: ConfigSectionAzure,
    config_section_dockerhub: ConfigSectionDockerHub,
    config_section_sre: ConfigSectionSRE,
) -> SREConfig:
    return SREConfig(
        allow_workspace_internet=True,
        azure=config_section_azure,
        description="Sandbox Project",
        dockerhub=config_section_dockerhub,
        name="sandbox",
        sre=config_section_sre,
    )


@fixture
def sre_config_internet_allowed_any_packages(
    config_section_azure: ConfigSectionAzure,
    config_section_dockerhub: ConfigSectionDockerHub,
    config_section_sre_any_packages: ConfigSectionSRE,
) -> SREConfig:
    return SREConfig(
        allow_workspace_internet=True,
        azure=config_section_azure,
        description="Sandbox Project",
        dockerhub=config_section_dockerhub,
        name="sandbox",
        sre=config_section_sre_any_packages,
    )


@fixture
def sre_config_alternate(
    config_section_azure: ConfigSectionAzure,
    config_section_dockerhub: ConfigSectionDockerHub,
    config_section_sre: ConfigSectionSRE,
) -> SREConfig:
    config_section_sre.admin_ip_addresses = ["2.3.4.5"]
    return SREConfig(
        azure=config_section_azure,
        description="Alternative Project",
        dockerhub=config_section_dockerhub,
        name="alternative",
        sre=config_section_sre,
    )


@fixture
def sre_config_yaml(request: FixtureRequest) -> str:
    content = """---
    azure:
        location: uksouth
        subscription_id: guid_subscription
        tenant_id: guid_tenant
    description: Sandbox Project
    dockerhub:
        access_token: dummytoken
        username: exampleuser
    name: sandbox
    sre:
        admin_email_address: admin@example.com
        admin_ip_addresses:
        - 1.2.3.4/32
        allow_workspace_internet: false
        data_provider_ip_addresses: []
        databases: []
        remote_desktop:
            allow_copy: false
            allow_paste: false
        research_user_ip_addresses: []
        software_packages: pre-approved
        storage_quota_gb:
            home: 100
            shared: 100
            data_disk: 0
            os_disk: 64
        timezone: Europe/London
        workspace_skus: []
    user_services:
        nexus:
            persistent_quota_gb: 10
        dns_sidecar:
            cron_expression: "*/30 * * * *"
            replica_timeout: 600
            retry_limit: 0
            workload_maximum_count: 2
            workload_minimum_count: 1
        gitea_mirror:
            repositories: []
    """.replace("guid_subscription", request.config.guid_subscription).replace(
        "guid_tenant", request.config.guid_tenant
    )
    return yaml.dump(yaml.safe_load(content))


@fixture
def sre_config_yaml_missing_field(sre_config_yaml: str) -> str:
    content = sre_config_yaml.replace("admin_email_address: admin@example.com", "")
    return yaml.dump(yaml.safe_load(content))


@fixture
def sre_project_manager(
    context_no_secrets: Context,
    sre_config: SREConfig,
    pulumi_config_no_key: DSHPulumiConfig,
    local_project_settings: None,  # noqa: ARG001
    mock_azuresdk_get_subscription: None,  # noqa: ARG001
    mock_azuresdk_get_credential: None,  # noqa: ARG001
    offline_pulumi_account: None,  # noqa: ARG001
) -> SREProjectManager:
    return SREProjectManager(
        context=context_no_secrets,
        config=sre_config,
        pulumi_config=pulumi_config_no_key,
    )


@fixture
def sre_project_manager_fresh(
    mocker: MockerFixture,
    context_no_secrets: Context,
    sre_config: SREConfig,
    pulumi_config_no_key: DSHPulumiConfig,
    local_project_settings: None,  # noqa: ARG001
    mock_azuresdk_get_subscription: None,  # noqa: ARG001
    mock_azuresdk_get_credential: None,  # noqa: ARG001
    offline_pulumi_account: None,  # noqa: ARG001
) -> SREProjectManager:
    manager = SREProjectManager(
        context=context_no_secrets,
        config=sre_config,
        pulumi_config=pulumi_config_no_key,
    )

    mocker.patch.object(manager, "output", return_value=None)

    return manager


@fixture
def mock_sre_project_manager_output(mocker: MockerFixture) -> None:
    mocker.patch.object(SREProjectManager, "output", return_value="test_sre")


@fixture
def mock_azuresdk_resource_manager_client(mocker: MockerFixture) -> None:
    def side_effect_get_by_id(azure_id: str, _sdk_version: str) -> GenericResource:
        resource = GenericResource()
        resource.id = azure_id
        return resource

    class Poller:
        def __init__(self, name: str) -> None:
            self.duration = hash(name) % 100

        def wait(self, duration: int) -> None:
            self.duration -= duration

        def done(self) -> bool:
            return self.duration <= 0

    def side_effect_begin_delete_by_id(azure_id: str, sdk_version: str) -> Poller:
        return Poller(azure_id + sdk_version)

    mocker.patch.object(
        ResourcesOperations, "get_by_id", side_effect=side_effect_get_by_id
    )

    mocker.patch.object(
        ResourcesOperations,
        "begin_delete_by_id",
        side_effect=side_effect_begin_delete_by_id,
    )


@fixture
def mock_upgrade_accept(mocker: MockerFixture):
    mocker.patch.object(
        Upgrade,
        "can_proceed",
        return_value=True,
    )

    mocker.patch.object(
        Upgrade,
        "prepare",
        return_value=5,
    )


@fixture
def mock_upgrade_deny(mocker: MockerFixture):
    mocker.patch.object(
        Upgrade,
        "can_proceed",
        return_value=False,
    )

    mocker.patch.object(
        Upgrade,
        "prepare",
        return_value=5,
    )
