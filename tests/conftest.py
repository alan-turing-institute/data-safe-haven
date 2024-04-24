from pathlib import Path

from pytest import fixture

import data_safe_haven.config.context_settings as context_mod
from data_safe_haven.config.config import (
    Config,
    ConfigSectionAzure,
    ConfigSectionSHM,
    ConfigSectionSRE,
    ConfigSubsectionRemoteDesktopOpts,
)
from data_safe_haven.config.context_settings import Context


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
def context_tmpdir(context_dict, tmpdir, monkeypatch):
    monkeypatch.setattr(context_mod, "config_dir", lambda: Path(tmpdir))
    return Context(**context_dict), tmpdir


@fixture
def config_yaml():
    return """azure:
  subscription_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
  tenant_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
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
def azure_config():
    return ConfigSectionAzure(
        subscription_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
    )


@fixture
def shm_config():
    return ConfigSectionSHM(
        aad_tenant_id="d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        admin_email_address="admin@example.com",
        admin_ip_addresses=["0.0.0.0"],  # noqa: S104
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
    sre_config_1 = ConfigSectionSRE(index=1)
    sre_config_2 = ConfigSectionSRE(index=2)
    return Config(
        azure=azure_config,
        shm=shm_config,
        sres={
            "sre1": sre_config_1,
            "sre2": sre_config_2,
        },
    )
