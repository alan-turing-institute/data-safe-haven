"""Mixin class for anything Pulumi-related"""
import pathlib
from data_safe_haven.exceptions import DataSafeHavenPulumiException

class PulumiMixin:
    """Mixin class for anything Pulumi-related"""

    def __init__(self, config, project_path, *args, **kwargs):
        self.env = {
            "AZURE_STORAGE_ACCOUNT": config.metadata.storage_account_name,
            "AZURE_STORAGE_KEY": config.storage_account_key(),
            "AZURE_KEYVAULT_AUTH_VIA_CLI": "true",
        }
        self.pulumi_path = pathlib.Path(project_path) / "pulumi"
        super().__init__(*args, **kwargs)

    def evaluate(self, result, print_fn):
        if result == "succeeded":
            print_fn("Pulumi operation <fg=green>succeeded</>.")
        else:
            print_fn("Pulumi operation <fg=red>failed</>.")
            raise DataSafeHavenPulumiException("Pulumi operation failed.")
