from pytest import fixture
from typer.testing import CliRunner

from data_safe_haven.config import (
    ContextSettings,
    DSHPulumiConfig,
    SHMConfig,
    SREConfig,
)


@fixture
def context(context_yaml):
    return ContextSettings.from_yaml(context_yaml).context


@fixture
def mock_pulumi_config_from_remote(mocker, pulumi_config):
    mocker.patch.object(DSHPulumiConfig, "from_remote", return_value=pulumi_config)


@fixture
def mock_pulumi_config_no_key_from_remote(mocker, pulumi_config_no_key):
    mocker.patch.object(
        DSHPulumiConfig, "from_remote", return_value=pulumi_config_no_key
    )


@fixture
def mock_shm_config_from_remote(mocker, shm_config):
    mocker.patch.object(SHMConfig, "from_remote", return_value=shm_config)


@fixture
def mock_sre_config_from_remote(mocker, sre_config):
    mocker.patch.object(SREConfig, "from_remote_by_name", return_value=sre_config)


@fixture
def runner(tmp_contexts):
    runner = CliRunner(
        env={
            "DSH_CONFIG_DIRECTORY": str(tmp_contexts),
            "COLUMNS": "500",  # Set large number of columns to avoid rich wrapping text
            "TERM": "dumb",  # Disable colours, style and interactive rich features
        },
        mix_stderr=False,
    )
    return runner


@fixture
def runner_none(tmp_contexts_none):
    runner = CliRunner(
        env={
            "DSH_CONFIG_DIRECTORY": str(tmp_contexts_none),
            "COLUMNS": "500",  # Set large number of columns to avoid rich wrapping text
            "TERM": "dumb",  # Disable colours, style and interactive rich features
        },
        mix_stderr=False,
    )
    return runner


@fixture
def runner_no_context_file(tmp_path):
    runner = CliRunner(
        env={
            "DSH_CONFIG_DIRECTORY": str(tmp_path),
            "COLUMNS": "500",  # Set large number of columns to avoid rich wrapping text
            "TERM": "dumb",  # Disable colours, style and interactive rich features
        },
        mix_stderr=False,
    )
    return runner


@fixture
def tmp_contexts(tmp_path, context_yaml):
    config_file_path = tmp_path / "contexts.yaml"
    with open(config_file_path, "w") as f:
        f.write(context_yaml)
    return tmp_path


@fixture
def tmp_contexts_gems(tmp_path, context_yaml):
    context_yaml = context_yaml.replace("selected: acmedeployment", "selected: gems")
    config_file_path = tmp_path / "contexts.yaml"
    with open(config_file_path, "w") as f:
        f.write(context_yaml)
    return tmp_path


@fixture
def tmp_contexts_none(tmp_path, context_yaml):
    context_yaml = context_yaml.replace("selected: acmedeployment", "selected: null")
    config_file_path = tmp_path / "contexts.yaml"
    with open(config_file_path, "w") as f:
        f.write(context_yaml)
    return tmp_path
