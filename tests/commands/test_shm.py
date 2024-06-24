import pytest

from data_safe_haven.commands.shm import shm_command_group


class TestDeploySHM:
    @pytest.mark.skip
    def test_context_infrastructure_create(
        self,
        runner,
        mock_backend_infrastructure_create_then_exit,  # noqa: ARG002
        mock_graph_api_add_custom_domain,  # noqa: ARG002
        mock_graph_api_create_token_administrator,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_shm_config_remote_exists,  # noqa: ARG002
        mock_shm_config_upload,  # noqa: ARG002
    ):
        result = runner.invoke(shm_command_group, ["deploy"])
        assert result.exit_code == 1
        assert "mock create" in result.stdout
        assert "mock creation error" in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(shm_command_group, ["deploy"])
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout

    def test_infrastructure_show_none(self, runner_none):
        result = runner_none.invoke(shm_command_group, ["deploy"])
        assert result.exit_code == 1
        assert "No context selected." in result.stdout

    def test_infrastructure_auth_failure(
        self,
        runner,
        mock_azure_authenticator_login_exception,  # noqa: ARG002
    ):
        result = runner.invoke(shm_command_group, ["deploy"])
        assert result.exit_code == 1
        assert "mock login" in result.stdout
        assert "mock login error" in result.stdout


class TestTeardownSHM:
    def test_teardown(
        self,
        runner,
        mock_backend_infrastructure_teardown_then_exit,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
    ):
        result = runner.invoke(shm_command_group, ["teardown"])
        assert result.exit_code == 1
        assert "mock teardown" in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(shm_command_group, ["teardown"])
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout

    def test_show_none(self, runner_none):
        result = runner_none.invoke(shm_command_group, ["teardown"])
        assert result.exit_code == 1
        assert "No context selected." in result.stdout

    def test_auth_failure(
        self,
        runner,
        mock_azure_authenticator_login_exception,  # noqa: ARG002
    ):
        result = runner.invoke(shm_command_group, ["teardown"])
        assert result.exit_code == 1
        assert "mock login" in result.stdout
        assert "mock login error" in result.stdout
