from pytest import fixture

from data_safe_haven.config.context_settings import Context
from data_safe_haven.external import AzureApi


@fixture
def context_dict():
    return {
        "admin_group_id": "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        "location": "uksouth",
        "name": "Acme Deployment",
        "subscription_name": "Data Safe Haven (Acme)",
    }


@fixture
def context(context_dict):
    return Context(**context_dict)


@fixture
def config_yaml():
    return """azure:
  subscription_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
  tenant_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
pulumi:
  stacks: {}
shm:
  aad_tenant_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
  admin_email_address: admin@example.com
  admin_ip_addresses:
  - 0.0.0.0/32
  fqdn: shm.acme.com
  timezone: UTC
sres:
  sre1:
    data_provider_ip_addresses: []
    databases: []
    index: 1
    remote_desktop:
      allow_copy: false
      allow_paste: false
    research_user_ip_addresses: []
    software_packages: none
    workspace_skus: []
  sre2:
    data_provider_ip_addresses: []
    databases: []
    index: 2
    remote_desktop:
      allow_copy: false
      allow_paste: false
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
def mock_download_blob(monkeypatch, context, config_yaml):
    def mock_download_blob(
        self,  # noqa: ARG001
        blob_name: str,
        resource_group_name: str,
        storage_account_name: str,
        storage_container_name: str,
    ):
        assert blob_name == context.config_filename
        assert resource_group_name == context.resource_group_name
        assert storage_account_name == context.storage_account_name
        assert storage_container_name == context.storage_container_name
        return config_yaml

    monkeypatch.setattr(AzureApi, "download_blob", mock_download_blob)


@fixture
def mock_upload_blob(monkeypatch, context):
    def mock_upload_blob(
        self,  # noqa: ARG001
        blob_data: bytes | str,  # noqa: ARG001
        blob_name: str,
        resource_group_name: str,
        storage_account_name: str,
        storage_container_name: str,
    ):
        assert blob_name == context.config_filename
        assert resource_group_name == context.resource_group_name
        assert storage_account_name == context.storage_account_name
        assert storage_container_name == context.storage_container_name
        pass

    monkeypatch.setattr(AzureApi, "upload_blob", mock_upload_blob)
