from data_safe_haven.config.backend_settings import Context, ContextSettings
from data_safe_haven.exceptions import DataSafeHavenParameterError

import pytest
import yaml


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


class TestContextSettings:
    context_settings = """\
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

    def test_constructor(self):
        settings = ContextSettings(yaml.safe_load(self.context_settings))
        assert isinstance(settings, ContextSettings)

    def test_invalid(self):
        context_settings = "\n".join(self.context_settings.splitlines()[1:])

        with pytest.raises(DataSafeHavenParameterError) as exc:
            ContextSettings(yaml.safe_load(context_settings))
            assert "Missing Key: 'selected'" in exc

    def test_settings(self):
        settings = ContextSettings(yaml.safe_load(self.context_settings))
        assert isinstance(settings.settings, dict)

    def test_selected(self):
        settings = ContextSettings(yaml.safe_load(self.context_settings))
        assert settings.selected == "acme_deployment"

    def test_set_selected(self):
        settings = ContextSettings(yaml.safe_load(self.context_settings))
        assert settings.selected == "acme_deployment"
        settings.selected = "gems"
        assert settings.selected == "gems"

    def test_invalid_selected(self):
        settings = ContextSettings(yaml.safe_load(self.context_settings))
        with pytest.raises(DataSafeHavenParameterError) as exc:
            settings.selected = "invalid"
            assert "Context invalid is not defined." in exc

    def test_context(self):
        yaml_settings = yaml.safe_load(self.context_settings)
        settings = ContextSettings(yaml_settings)
        assert isinstance(settings.context, Context)
        assert all([
            getattr(settings.context, item) == yaml_settings["contexts"]["acme_deployment"][item]
            for item in yaml_settings["contexts"]["acme_deployment"].keys()
        ])

    def test_set_context(self):
        yaml_settings = yaml.safe_load(self.context_settings)
        settings = ContextSettings(yaml_settings)
        settings.selected = "gems"
        assert isinstance(settings.context, Context)
        assert all([
            getattr(settings.context, item) == yaml_settings["contexts"]["gems"][item]
            for item in yaml_settings["contexts"]["gems"].keys()
        ])

    def test_available(self):
        settings = ContextSettings(yaml.safe_load(self.context_settings))
        available = settings.available
        print(available)
        assert isinstance(available, list)
        assert all([isinstance(item, str) for item in available])
        assert available == ["acme_deployment", "gems"]

    def test_update(self):
        settings = ContextSettings(yaml.safe_load(self.context_settings))
        assert settings.context.name == "Acme Deployment"
        settings.update(name="replaced")
        assert settings.context.name == "replaced"

    def test_set_update(self):
        settings = ContextSettings(yaml.safe_load(self.context_settings))
        settings.selected = "gems"
        assert settings.context.name == "Gems"
        settings.update(name="replaced")
        assert settings.context.name == "replaced"

    def test_add(self):
        settings = ContextSettings(yaml.safe_load(self.context_settings))
        settings.add(
            key="example",
            name="Example",
            subscription_name="Data Safe Haven (Example)",
            admin_group_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
            location="uksouth",
        )
        settings.selected = "example"
        assert settings.selected == "example"
        assert settings.context.name == "Example"
        assert settings.context.subscription_name == "Data Safe Haven (Example)"

    def test_from_file(self, tmp_path):
        config_file_path = tmp_path / "config.yaml"
        with open(config_file_path, "w") as f:
            f.write(self.context_settings)
        settings = ContextSettings.from_file(config_file_path=config_file_path)
        assert settings.context.name == "Acme Deployment"

    def test_write(self, tmp_path):
        config_file_path = tmp_path / "config.yaml"
        with open(config_file_path, "w") as f:
            f.write(self.context_settings)
        settings = ContextSettings.from_file(config_file_path=config_file_path)
        settings.selected = "gems"
        settings.update(name="replaced")
        settings.write(config_file_path)
        with open(config_file_path, "r") as f:
            context_dict = yaml.safe_load(f)
        assert context_dict["selected"] == "gems"
        assert context_dict["contexts"]["gems"]["name"] == "replaced"
