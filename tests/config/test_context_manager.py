import pytest
import yaml
from pydantic import ValidationError

from data_safe_haven.config import Context, ContextManager
from data_safe_haven.exceptions import (
    DataSafeHavenAzureError,
    DataSafeHavenConfigError,
    DataSafeHavenTypeError,
    DataSafeHavenValueError,
)
from data_safe_haven.external import AzureSdk
from data_safe_haven.version import __version__


class TestContext:
    def test_constructor(self, context_dict):
        context = Context(**context_dict)
        assert isinstance(context, Context)
        assert all(
            getattr(context, item) == context_dict[item] for item in context_dict.keys()
        )
        assert context.storage_container_name == "config"
        assert context.pulumi_storage_container_name == "pulumi"
        assert context.pulumi_encryption_key_name == "pulumi-encryption-key"

    def test_invalid_subscription_name(self, context_dict):
        context_dict["subscription_name"] = "very " * 15 + "long name"
        with pytest.raises(
            ValidationError, match="String should have at most 80 characters"
        ):
            Context(**context_dict)

    def test_entra_application_name(self, context: Context) -> None:
        assert (
            context.entra_application_name
            == "Data Safe Haven (Acme Deployment) Pulumi Service Principal"
        )

    def test_entra_application_secret(self, context: Context, mocker) -> None:
        mocker.patch.object(
            AzureSdk, "get_keyvault_secret", return_value="secret-value"
        )
        assert context.entra_application_secret == "secret-value"  # noqa: S105

    def test_entra_application_secret_missing(self, context: Context, mocker) -> None:
        mocker.patch.object(
            AzureSdk,
            "get_keyvault_secret",
            side_effect=DataSafeHavenAzureError("Error message"),
        )
        assert context.entra_application_secret == ""

    def test_entra_application_secret_setter(self, context: Context, mocker) -> None:
        mock_set_keyvault_secret = mocker.patch.object(AzureSdk, "set_keyvault_secret")
        context.entra_application_secret = "secret-value"  # noqa: S105
        mock_set_keyvault_secret.assert_called_once_with(
            key_vault_name="shm-acmedeployment-kv",
            secret_name="pulumi-deployment-secret",
            secret_value="secret-value",
        )

    def test_tags(self, context):
        assert context.tags["description"] == "Acme Deployment"
        assert context.tags["project"] == "Data Safe Haven"
        assert context.tags["shm_name"] == "acmedeployment"
        assert context.tags["version"] == __version__

    def test_name(self, context):
        assert context.name == "acmedeployment"

    def test_work_directory(self, context, monkeypatch):
        monkeypatch.delenv("DSH_CONFIG_DIRECTORY", raising=False)
        assert "data_safe_haven/acmedeployment" in str(context.work_directory)

    def test_resource_group_name(self, context):
        assert context.resource_group_name == "shm-acmedeployment-rg"

    def test_storage_account_name(self, context):
        assert context.storage_account_name == "shmacmedeployment"

    def test_long_storage_account_name(self, context_dict):
        context_dict["name"] = "very" * 5 + "longname"
        context = Context(**context_dict)
        assert context.storage_account_name == "shmveryveryveryveryveryl"

    def test_key_vault_name(self, context):
        assert context.key_vault_name == "shm-acmedeployment-kv"

    def test_managed_identity_name(self, context):
        assert context.managed_identity_name == "shm-acmedeployment-identity-reader"

    def test_pulumi_backend_url(self, context):
        assert context.pulumi_backend_url == "azblob://pulumi"

    def test_pulumi_encryption_key(self, context, mock_key_vault_key):  # noqa: ARG002
        key = context.pulumi_encryption_key
        assert key.key_name == context.pulumi_encryption_key_name
        assert key.key_vault_name == context.key_vault_name

    def test_pulumi_encryption_key_version(
        self, context, mock_key_vault_key  # noqa: ARG002
    ):
        version = context.pulumi_encryption_key_version
        assert version == "version"

    def test_pulumi_secrets_provider_url(
        self, context, mock_key_vault_key  # noqa: ARG002
    ):
        assert (
            context.pulumi_secrets_provider_url
            == "azurekeyvault://shm-acmedeployment-kv.vault.azure.net/keys/pulumi-encryption-key/version"
        )


class TestContextManager:
    def test_constructor(self):
        settings = ContextManager(
            selected="acmedeployment",
            contexts={
                "acmedeployment": Context(
                    admin_group_name="Acme Admins",
                    description="Acme Deployment",
                    name="acmedeployment",
                    subscription_name="Data Safe Haven Acme",
                )
            },
        )
        assert isinstance(settings, ContextManager)

    def test_null_selected(self, context_yaml):
        context_yaml = context_yaml.replace(
            "selected: acmedeployment", "selected: null"
        )

        settings = ContextManager.from_yaml(context_yaml)
        assert settings.selected is None
        assert settings.context is None
        with pytest.raises(DataSafeHavenConfigError, match="No context selected"):
            settings.assert_context()

    def test_missing_selected(self, context_yaml):
        context_yaml = "\n".join(
            [line for line in context_yaml.splitlines() if "selected:" not in line]
        )
        with pytest.raises(
            DataSafeHavenTypeError,
            match="ContextManager configuration is invalid.",
        ):
            ContextManager.from_yaml(context_yaml)

    def test_invalid_selected_input(self, context_yaml):
        context_yaml = context_yaml.replace(
            "selected: acmedeployment", "selected: invalid"
        )
        with pytest.raises(
            DataSafeHavenTypeError,
            match="ContextManager configuration is invalid.",
        ):
            ContextManager.from_yaml(context_yaml)

    def test_invalid_yaml(self):
        invalid_yaml = "a: [1,2"
        with pytest.raises(
            DataSafeHavenConfigError,
            match="Could not parse ContextManager configuration as YAML.",
        ):
            ContextManager.from_yaml(invalid_yaml)

    def test_yaml_not_dict(self):
        not_dict = "[1, 2, 3]"
        with pytest.raises(
            DataSafeHavenConfigError,
            match="Unable to parse ContextManager configuration as a dict.",
        ):
            ContextManager.from_yaml(not_dict)

    def test_selected(self, context_manager):
        assert context_manager.selected == "acmedeployment"

    def test_set_selected(self, context_manager):
        assert context_manager.selected == "acmedeployment"
        context_manager.selected = "gems"
        assert context_manager.selected == "gems"

    def test_invalid_selected(self, context_manager):
        with pytest.raises(
            DataSafeHavenValueError, match="Context 'invalid' is not defined."
        ):
            context_manager.selected = "invalid"

    def test_context(self, context_yaml, context_manager):
        yaml_dict = yaml.safe_load(context_yaml)
        assert isinstance(context_manager.context, Context)
        assert all(
            getattr(context_manager.context, item)
            == yaml_dict["contexts"]["acmedeployment"][item]
            for item in yaml_dict["contexts"]["acmedeployment"].keys()
        )

    def test_set_context(self, context_yaml, context_manager):
        yaml_dict = yaml.safe_load(context_yaml)
        context_manager.selected = "gems"
        assert isinstance(context_manager.context, Context)
        assert all(
            getattr(context_manager.context, item)
            == yaml_dict["contexts"]["gems"][item]
            for item in yaml_dict["contexts"]["gems"].keys()
        )

    def test_set_context_none(self, context_manager):
        context_manager.selected = None
        assert context_manager.selected is None
        assert context_manager.context is None

    def test_assert_context(self, context_manager):
        context = context_manager.assert_context()
        assert context.description == "Acme Deployment"
        assert context.name == "acmedeployment"

    def test_assert_context_none(self, context_manager):
        context_manager.selected = None
        with pytest.raises(DataSafeHavenConfigError, match="No context selected"):
            context_manager.assert_context()

    def test_available(self, context_manager):
        available = context_manager.available
        assert isinstance(available, list)
        assert all(isinstance(item, str) for item in available)
        assert available == ["acmedeployment", "gems"]

    def test_update(self, context_manager):
        assert context_manager.context.description == "Acme Deployment"
        assert context_manager.context.name == "acmedeployment"
        context_manager.update(name="replaced")
        assert context_manager.context.name == "replaced"

    def test_set_update(self, context_manager):
        context_manager.selected = "gems"
        assert context_manager.context.description == "Gems"
        assert context_manager.context.name == "gems"
        context_manager.update(name="replaced")
        assert context_manager.context.name == "replaced"

    def test_update_none(self, context_manager):
        context_manager.selected = None
        with pytest.raises(DataSafeHavenConfigError, match="No context selected"):
            context_manager.update(name="replaced")

    def test_add(self, context_manager):
        context_manager.add(
            admin_group_name="Example Admins",
            description="Example Deployment",
            name="example",
            subscription_name="Data Safe Haven Example",
        )
        context_manager.selected = "example"
        assert context_manager.selected == "example"
        assert context_manager.context.description == "Example Deployment"
        assert context_manager.context.name == "example"
        assert context_manager.context.subscription_name == "Data Safe Haven Example"

    def test_invalid_add(self, context_manager):
        with pytest.raises(
            DataSafeHavenValueError,
            match="A context with name 'acmedeployment' is already defined.",
        ):
            context_manager.add(
                admin_group_name="Acme Admins",
                description="Acme Deployment",
                name="acmedeployment",
                subscription_name="Data Safe Haven Acme",
            )

    def test_remove(self, context_manager):
        context_manager.remove("gems")
        assert "gems" not in context_manager.available
        assert context_manager.selected == "acmedeployment"

    def test_invalid_remove(self, context_manager):
        with pytest.raises(
            DataSafeHavenValueError, match="No context with name 'invalid'."
        ):
            context_manager.remove("invalid")

    def test_remove_selected(self, context_manager):
        context_manager.remove("acmedeployment")
        assert "acmedeployment" not in context_manager.available
        assert context_manager.selected is None

    def test_from_file(self, tmp_path, context_yaml):
        config_file_path = tmp_path / "config.yaml"
        with open(config_file_path, "w") as f:
            f.write(context_yaml)
        settings = ContextManager.from_file(config_file_path=config_file_path)
        assert settings.context.description == "Acme Deployment"
        assert settings.context.name == "acmedeployment"

    def test_file_not_found(self, tmp_path):
        config_file_path = tmp_path / "config.yaml"
        with pytest.raises(DataSafeHavenConfigError, match="Could not find file"):
            ContextManager.from_file(config_file_path=config_file_path)

    def test_write(self, tmp_path, context_yaml):
        config_file_path = tmp_path / "config.yaml"
        with open(config_file_path, "w") as f:
            f.write(context_yaml)
        settings = ContextManager.from_file(config_file_path=config_file_path)
        settings.selected = "gems"
        settings.update(name="replaced")
        settings.write(config_file_path)
        with open(config_file_path) as f:
            context_dict = yaml.safe_load(f)
        assert context_dict["selected"] == "replaced"
        assert context_dict["contexts"]["replaced"]["name"] == "replaced"
