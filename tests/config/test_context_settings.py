import pytest
import yaml
from pydantic import ValidationError
from pytest import fixture

from data_safe_haven.config.context_settings import Context, ContextSettings
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)
from data_safe_haven.external import AzureApi


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


class TestContext:
    def test_constructor(self, context_dict):
        context = Context(**context_dict)
        assert isinstance(context, Context)
        assert all(
            getattr(context, item) == context_dict[item] for item in context_dict.keys()
        )
        assert context.storage_container_name == "config"

    def test_invalid_guid(self, context_dict):
        context_dict["admin_group_id"] = "not a guid"
        with pytest.raises(
            ValidationError, match="Value error, Expected GUID, for example"
        ):
            Context(**context_dict)

    def test_invalid_location(self, context_dict):
        context_dict["location"] = "not_a_location"
        with pytest.raises(
            ValidationError, match="Value error, Expected valid Azure location"
        ):
            Context(**context_dict)

    def test_invalid_subscription_name(self, context_dict):
        context_dict["subscription_name"] = "very " * 12 + "long name"
        with pytest.raises(
            ValidationError, match="String should have at most 64 characters"
        ):
            Context(**context_dict)

    def test_shm_name(self, context):
        assert context.shm_name == "acmedeployment"

    def test_work_directory(self, context, monkeypatch):
        monkeypatch.delenv("DSH_CONFIG_DIRECTORY", raising=False)
        assert "data_safe_haven/acmedeployment" in str(context.work_directory)

    def test_config_filename(self, context):
        assert context.config_filename == "config-acmedeployment.yaml"

    def test_resource_group_name(self, context):
        assert context.resource_group_name == "shm-acmedeployment-rg-context"

    def test_storage_account_name(self, context):
        assert context.storage_account_name == "shmacmedeploymentcontext"

    def test_long_storage_account_name(self, context_dict):
        context_dict["name"] = "very " * 5 + "long name"
        context = Context(**context_dict)
        assert context.storage_account_name == "shmveryveryveryvecontext"

    def test_key_vault_name(self, context):
        assert context.key_vault_name == "shm-acmedeplo-kv-context"

    def test_managed_identity_name(self, context):
        assert context.managed_identity_name == "shm-acmedeployment-identity-reader-context"

    def test_pulumi_backend_url(self, context):
        assert context.pulumi_backend_url == "azblob://pulumi"

    def test_pulumi_encryption_key(
        self, context, mock_key_vault_key  # noqa: ARG002
    ):
        key = context.pulumi_encryption_key
        assert key.key_name == context.pulumi_encryption_key_name
        assert key.key_vault_name == context.key_vault_name

    def test_pulumi_encryption_key_version(
        self, context, mock_key_vault_key  # noqa: ARG002
    ):
        version = context.pulumi_encryption_key_version
        assert version == "version"

    def test_pulumi_secrets_provider_url(self, context, mock_key_vault_key):
        assert context.pulumi_secrets_provider_url == "azurekeyvault://shm-acmedeplo-kv-context.vault.azure.net/keys/pulumi-encryption-key/version"


@fixture
def context_yaml():
    context_yaml = """\
        selected: acme_deployment
        contexts:
            acme_deployment:
                name: Acme Deployment
                admin_group_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
                location: uksouth
                subscription_name: Data Safe Haven (Acme)
            gems:
                name: Gems
                admin_group_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
                location: uksouth
                subscription_name: Data Safe Haven (Gems)"""
    return context_yaml


@fixture
def context_settings(context_yaml):
    return ContextSettings.from_yaml(context_yaml)


class TestContextSettings:
    def test_constructor(self):
        settings = ContextSettings(
            selected="acme_deployment",
            contexts={
                "acme_deployment": Context(
                    name="Acme Deployment",
                    admin_group_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
                    location="uksouth",
                    subscription_name="Data Safe Haven (Acme)",
                )
            },
        )
        assert isinstance(settings, ContextSettings)

    def test_null_selected(self, context_yaml):
        context_yaml = context_yaml.replace(
            "selected: acme_deployment", "selected: null"
        )

        settings = ContextSettings.from_yaml(context_yaml)
        assert settings.selected is None
        assert settings.context is None
        with pytest.raises(DataSafeHavenConfigError, match="No context selected"):
            settings.assert_context()

    def test_missing_selected(self, context_yaml):
        context_yaml = "\n".join(context_yaml.splitlines()[1:])
        msg = "\n".join(
            [
                "Could not load context settings.",
                "1 validation error for ContextSettings",
                "selected",
                "  Field required",
            ]
        )
        with pytest.raises(DataSafeHavenParameterError, match=msg):
            ContextSettings.from_yaml(context_yaml)

    def test_invalid_selected_input(self, context_yaml):
        context_yaml = context_yaml.replace(
            "selected: acme_deployment", "selected: invalid"
        )

        with pytest.raises(
            DataSafeHavenParameterError,
            match="Selected context 'invalid' is not defined.",
        ):
            ContextSettings.from_yaml(context_yaml)

    def test_invalid_yaml(self):
        invalid_yaml = "a: [1,2"
        with pytest.raises(
            DataSafeHavenConfigError, match="Could not parse context settings as YAML."
        ):
            ContextSettings.from_yaml(invalid_yaml)

    def test_yaml_not_dict(self):
        not_dict = "[1, 2, 3]"
        with pytest.raises(
            DataSafeHavenConfigError,
            match="Unable to parse context settings as a dict.",
        ):
            ContextSettings.from_yaml(not_dict)

    def test_selected(self, context_settings):
        assert context_settings.selected == "acme_deployment"

    def test_set_selected(self, context_settings):
        assert context_settings.selected == "acme_deployment"
        context_settings.selected = "gems"
        assert context_settings.selected == "gems"

    def test_invalid_selected(self, context_settings):
        with pytest.raises(
            DataSafeHavenParameterError, match="Context 'invalid' is not defined."
        ):
            context_settings.selected = "invalid"

    def test_context(self, context_yaml, context_settings):
        yaml_dict = yaml.safe_load(context_yaml)
        assert isinstance(context_settings.context, Context)
        assert all(
            getattr(context_settings.context, item)
            == yaml_dict["contexts"]["acme_deployment"][item]
            for item in yaml_dict["contexts"]["acme_deployment"].keys()
        )

    def test_set_context(self, context_yaml, context_settings):
        yaml_dict = yaml.safe_load(context_yaml)
        context_settings.selected = "gems"
        assert isinstance(context_settings.context, Context)
        assert all(
            getattr(context_settings.context, item)
            == yaml_dict["contexts"]["gems"][item]
            for item in yaml_dict["contexts"]["gems"].keys()
        )

    def test_set_context_none(self, context_settings):
        context_settings.selected = None
        assert context_settings.selected is None
        assert context_settings.context is None

    def test_assert_context(self, context_settings):
        context = context_settings.assert_context()
        assert context.name == "Acme Deployment"

    def test_assert_context_none(self, context_settings):
        context_settings.selected = None
        with pytest.raises(DataSafeHavenConfigError, match="No context selected"):
            context_settings.assert_context()

    def test_available(self, context_settings):
        available = context_settings.available
        assert isinstance(available, list)
        assert all(isinstance(item, str) for item in available)
        assert available == ["acme_deployment", "gems"]

    def test_update(self, context_settings):
        assert context_settings.context.name == "Acme Deployment"
        context_settings.update(name="replaced")
        assert context_settings.context.name == "replaced"

    def test_set_update(self, context_settings):
        context_settings.selected = "gems"
        assert context_settings.context.name == "Gems"
        context_settings.update(name="replaced")
        assert context_settings.context.name == "replaced"

    def test_update_none(self, context_settings):
        context_settings.selected = None
        with pytest.raises(DataSafeHavenConfigError, match="No context selected"):
            context_settings.update(name="replaced")

    def test_add(self, context_settings):
        context_settings.add(
            key="example",
            name="Example",
            subscription_name="Data Safe Haven (Example)",
            admin_group_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            location="uksouth",
        )
        context_settings.selected = "example"
        assert context_settings.selected == "example"
        assert context_settings.context.name == "Example"
        assert context_settings.context.subscription_name == "Data Safe Haven (Example)"

    def test_invalid_add(self, context_settings):
        with pytest.raises(
            DataSafeHavenParameterError,
            match="A context with key 'acme_deployment' is already defined.",
        ):
            context_settings.add(
                key="acme_deployment",
                name="Acme Deployment",
                subscription_name="Data Safe Haven (Acme)",
                admin_group_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
                location="uksouth",
            )

    def test_remove(self, context_settings):
        context_settings.remove("gems")
        assert "gems" not in context_settings.available
        assert context_settings.selected == "acme_deployment"

    def test_invalid_remove(self, context_settings):
        with pytest.raises(
            DataSafeHavenParameterError, match="No context with key 'invalid'."
        ):
            context_settings.remove("invalid")

    def test_remove_selected(self, context_settings):
        context_settings.remove("acme_deployment")
        assert "acme_deployment" not in context_settings.available
        assert context_settings.selected is None

    def test_from_file(self, tmp_path, context_yaml):
        config_file_path = tmp_path / "config.yaml"
        with open(config_file_path, "w") as f:
            f.write(context_yaml)
        settings = ContextSettings.from_file(config_file_path=config_file_path)
        assert settings.context.name == "Acme Deployment"

    def test_file_not_found(self, tmp_path):
        config_file_path = tmp_path / "config.yaml"
        with pytest.raises(DataSafeHavenConfigError, match="Could not find file"):
            ContextSettings.from_file(config_file_path=config_file_path)

    def test_write(self, tmp_path, context_yaml):
        config_file_path = tmp_path / "config.yaml"
        with open(config_file_path, "w") as f:
            f.write(context_yaml)
        settings = ContextSettings.from_file(config_file_path=config_file_path)
        settings.selected = "gems"
        settings.update(name="replaced")
        settings.write(config_file_path)
        with open(config_file_path) as f:
            context_dict = yaml.safe_load(f)
        assert context_dict["selected"] == "gems"
        assert context_dict["contexts"]["gems"]["name"] == "replaced"
