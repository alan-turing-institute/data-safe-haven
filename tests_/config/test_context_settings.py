import pytest
import yaml
from pydantic import ValidationError
from pytest import fixture

from data_safe_haven.config.context_settings import Context, ContextSettings
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenParameterError,
)


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
        with pytest.raises(ValidationError) as exc:
            Context(**context_dict)
            assert "Value error, Expected GUID, for example" in exc

    def test_invalid_location(self, context_dict):
        context_dict["location"] = "not_a_location"
        with pytest.raises(ValidationError) as exc:
            Context(**context_dict)
            assert "Value error, Expected valid Azure location" in exc

    def test_invalid_subscription_name(self, context_dict):
        context_dict["subscription_name"] = "very " * 12 + "long name"
        with pytest.raises(ValidationError) as exc:
            Context(**context_dict)
            assert "String should have at most 64 characters" in exc

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
        context_yaml = context_yaml.replace("selected: acme_deployment", "selected: null")

        settings = ContextSettings.from_yaml(context_yaml)
        assert settings.selected is None
        assert settings.context is None
        with pytest.raises(DataSafeHavenConfigError) as exc:
            settings.assert_context()
            assert "No context selected" in exc

    def test_missing_selected(self, context_yaml):
        context_yaml = "\n".join(context_yaml.splitlines()[1:])

        with pytest.raises(DataSafeHavenParameterError) as exc:
            ContextSettings.from_yaml(context_yaml)
            assert "Could not load context settings" in exc
            assert "1 validation error for ContextSettings" in exc
            assert "selected" in exc
            assert "Field required" in exc

    def test_invalid_selected_input(self, context_yaml):
        context_yaml = context_yaml.replace(
            "selected: acme_deployment", "selected: invalid"
        )

        with pytest.raises(DataSafeHavenParameterError) as exc:
            ContextSettings.from_yaml(context_yaml)
            assert "Selected context 'invalid' is not defined." in exc

    def test_invalid_yaml(self):
        invalid_yaml = "a: [1,2"
        with pytest.raises(DataSafeHavenConfigError) as exc:
            ContextSettings.from_yaml(invalid_yaml)
            assert "Could not parse context settings as YAML." in exc

    def test_yaml_not_dict(self):
        not_dict = "[1, 2, 3]"
        with pytest.raises(DataSafeHavenConfigError) as exc:
            ContextSettings.from_yaml(not_dict)
            assert "Unable to parse context settings as a dict." in exc

    def test_selected(self, context_settings):
        assert context_settings.selected == "acme_deployment"

    def test_set_selected(self, context_settings):
        assert context_settings.selected == "acme_deployment"
        context_settings.selected = "gems"
        assert context_settings.selected == "gems"

    def test_invalid_selected(self, context_settings):
        with pytest.raises(DataSafeHavenParameterError) as exc:
            context_settings.selected = "invalid"
            assert "Context invalid is not defined." in exc

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
        with pytest.raises(DataSafeHavenConfigError) as exc:
            context_settings.assert_context()
            assert "No context selected" in exc

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
        with pytest.raises(DataSafeHavenConfigError) as exc:
            context_settings.update(name="replaced")
            assert "No context selected" in exc

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
        with pytest.raises(DataSafeHavenParameterError) as exc:
            context_settings.add(
                key="acme_deployment",
                name="Acme Deployment",
                subscription_name="Data Safe Haven (Acme)",
                admin_group_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
                location="uksouth",
            )
            assert "A context with key 'acme' is already defined." in exc

    def test_remove(self, context_settings):
        context_settings.remove("gems")
        assert "gems" not in context_settings.available
        assert context_settings.selected == "acme_deployment"

    def test_invalid_remove(self, context_settings):
        with pytest.raises(DataSafeHavenParameterError) as exc:
            context_settings.remove("invalid")
            assert "No context with key 'invalid'." in exc

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
        with pytest.raises(DataSafeHavenConfigError) as exc:
            ContextSettings.from_file(config_file_path=config_file_path)
            assert "Could not find file" in exc

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
