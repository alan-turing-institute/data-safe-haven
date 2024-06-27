from pytest import fixture
from typer.testing import CliRunner

from data_safe_haven.config import (
    Context,
    ContextManager,
    DSHPulumiConfig,
    SHMConfig,
    SREConfig,
)
from data_safe_haven.exceptions import (
    DataSafeHavenAzureAPIAuthenticationError,
    DataSafeHavenAzureError,
)
from data_safe_haven.external import AzureApi, GraphApi
from data_safe_haven.external.interface.azure_authenticator import AzureAuthenticator
from data_safe_haven.infrastructure import ImperativeSHM


@fixture
def context(context_yaml) -> Context:
    return ContextManager.from_yaml(context_yaml).context


@fixture
def mock_azure_api_blob_exists_false(mocker):
    mocker.patch.object(AzureApi, "blob_exists", return_value=False)


@fixture
def mock_azure_authenticator_login_exception(mocker):
    def login_then_exit():
        print("mock login")  # noqa: T201
        msg = "mock login error"
        raise DataSafeHavenAzureAPIAuthenticationError(msg)

    mocker.patch.object(
        AzureAuthenticator,
        "login",
        side_effect=login_then_exit,
    )


@fixture
def mock_graph_api_add_custom_domain(mocker):
    mocker.patch.object(
        GraphApi, "add_custom_domain", return_value="dummy-verification-record"
    )


@fixture
def mock_graph_api_create_token_administrator(mocker):
    mocker.patch.object(
        GraphApi, "create_token_administrator", return_value="dummy-token"
    )


@fixture
def mock_imperative_shm_deploy(mocker):
    mocker.patch.object(
        ImperativeSHM,
        "deploy",
        side_effect=print("mock deploy"),  # noqa: T201
    )


@fixture
def mock_imperative_shm_deploy_then_exit(mocker):
    def create_then_exit():
        print("mock deploy")  # noqa: T201
        msg = "mock deploy error"
        raise DataSafeHavenAzureAPIAuthenticationError(msg)

    mocker.patch.object(
        ImperativeSHM,
        "deploy",
        side_effect=create_then_exit,
    )


@fixture
def mock_imperative_shm_teardown_then_exit(mocker):
    def teardown_then_exit():
        print("mock teardown")  # noqa: T201
        msg = "mock teardown error"
        raise DataSafeHavenAzureAPIAuthenticationError(msg)

    mocker.patch.object(
        ImperativeSHM,
        "teardown",
        side_effect=teardown_then_exit,
    )


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
def mock_shm_config_from_remote_fails(mocker):
    mocker.patch.object(
        SHMConfig,
        "from_remote",
        side_effect=DataSafeHavenAzureError("mock from_remote failure"),
    )


@fixture
def mock_shm_config_remote_exists(mocker):
    mocker.patch.object(SHMConfig, "remote_exists", return_value=True)


@fixture
def mock_shm_config_remote_yaml_diff(mocker):
    mocker.patch.object(SHMConfig, "remote_yaml_diff", return_value=[])


@fixture
def mock_shm_config_upload(mocker):
    mocker.patch.object(SHMConfig, "upload", return_value=None)


@fixture
def mock_sre_config_from_remote(mocker, sre_config):
    mocker.patch.object(SREConfig, "from_remote_by_name", return_value=sre_config)


@fixture
def mock_sre_config_alternate_from_remote(mocker, sre_config_alternate):
    mocker.patch.object(
        SREConfig, "from_remote_by_name", return_value=sre_config_alternate
    )


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
