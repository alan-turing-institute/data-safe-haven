import pathlib
import re
import dotmap
import yaml
from data_safe_haven.exceptions import DataSafeHavenInputException
from data_safe_haven import __version__


class Config:
    def __init__(self, path):
        try:
            with open(pathlib.Path(path), "r") as f_config:
                base_yaml = yaml.safe_load(f_config)
        except Exception as exc:
            raise DataSafeHavenInputException(
                f"Could not load config YAML file '{path}'"
            ) from exc

        self.data = self.expand_base_yaml(base_yaml)

    def expand_base_yaml(self, yaml_):
        alphanumeric = re.compile(r"[^0-9a-zA-Z]+")
        deployment_name = alphanumeric.sub("", yaml_["deployment"]["name"]).lower()
        yaml_["pulumi"] = {
            "encryption_key_name": f"encryption-{deployment_name}-pulumi",
            "key_vault_name": f"kv-{deployment_name}-pulumi",
            "resource_group_name": f"rg-{deployment_name}-pulumi",
            "storage_account_name": f"st{deployment_name}pulumi",
            "storage_container_name": f"pulumi-state",
        }
        yaml_["tags"] = {
            "deployed_by": "Python",
            "project": "Data Safe Haven",
            "version": __version__,
            "component": "Infrastructure",
        }
        return dotmap.DotMap(yaml_)

    def __getattr__(self, name):
        return self.data[name]
