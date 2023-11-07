from data_safe_haven.config.context_settings import Context, ContextSettings
from data_safe_haven.exceptions import DataSafeHavenParameterError

import pytest
import yaml
from pytest import fixture


class TestContext:
    def test_constructor(self):
        context_dict = {
            "admin_group_id": "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            "location": "uksouth",
            "name": "Acme Deployment",
            "subscription_name": "Data Safe Haven (Acme)"
        }
        context = Context(**context_dict)
        assert isinstance(context, Context)
        assert all([
            getattr(context, item) == context_dict[item] for item in context_dict.keys()
        ])


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
    def test_constructor(self, context_yaml):
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

    def test_missing_selected(self, context_yaml):
        context_yaml = "\n".join(context_yaml.splitlines()[1:])

        with pytest.raises(DataSafeHavenParameterError) as exc:
            ContextSettings.from_yaml(context_yaml)
            assert "Could not load context settings" in exc
            assert "1 validation error for ContextSettings" in exc
            assert "selected" in exc
            assert "Field required" in exc

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
        assert all([
            getattr(context_settings.context, item) == yaml_dict["contexts"]["acme_deployment"][item]
            for item in yaml_dict["contexts"]["acme_deployment"].keys()
        ])

    def test_set_context(self, context_yaml, context_settings):
        yaml_dict = yaml.safe_load(context_yaml)
        context_settings.selected = "gems"
        assert isinstance(context_settings.context, Context)
        assert all([
            getattr(context_settings.context, item) == yaml_dict["contexts"]["gems"][item]
            for item in yaml_dict["contexts"]["gems"].keys()
        ])

    def test_available(self, context_settings):
        available = context_settings.available
        assert isinstance(available, list)
        assert all([isinstance(item, str) for item in available])
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
        context_settings.remove("acme_deployment")
        assert "acme_deployment" not in context_settings.available

    def test_invalid_remove(self, context_settings):
        with pytest.raises(DataSafeHavenParameterError) as exc:
            context_settings.remove("invalid")
            assert "No context with key 'invalid'." in exc

    def test_from_file(self, tmp_path, context_yaml):
        config_file_path = tmp_path / "config.yaml"
        with open(config_file_path, "w") as f:
            f.write(context_yaml)
        settings = ContextSettings.from_file(config_file_path=config_file_path)
        assert settings.context.name == "Acme Deployment"

    def test_write(self, tmp_path, context_yaml):
        config_file_path = tmp_path / "config.yaml"
        with open(config_file_path, "w") as f:
            f.write(context_yaml)
        settings = ContextSettings.from_file(config_file_path=config_file_path)
        settings.selected = "gems"
        settings.update(name="replaced")
        settings.write(config_file_path)
        with open(config_file_path, "r") as f:
            context_dict = yaml.safe_load(f)
        assert context_dict["selected"] == "gems"
        assert context_dict["contexts"]["gems"]["name"] == "replaced"
