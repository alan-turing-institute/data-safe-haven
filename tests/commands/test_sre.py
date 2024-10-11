from pytest import CaptureFixture, LogCaptureFixture
from pytest_mock import MockerFixture
from typer.testing import CliRunner

from data_safe_haven.commands.sre import sre_command_group
from data_safe_haven.config import Context, ContextManager
from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.external import AzureSdk


class TestDeploySRE:
    def test_deploy(
        self,
        runner: CliRunner,
        mock_azuresdk_get_subscription_name,  # noqa: ARG002
        mock_graph_api_token,  # noqa: ARG002
        mock_contextmanager_assert_context,  # noqa: ARG002
        mock_ip_1_2_3_4,  # noqa: ARG002
        mock_pulumi_config_from_remote_or_create,  # noqa: ARG002
        mock_pulumi_config_upload,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        mock_graph_api_get_application_by_name,  # noqa: ARG002
        mock_sre_project_manager_deploy_then_exit,  # noqa: ARG002
    ) -> None:
        result = runner.invoke(sre_command_group, ["deploy", "sandbox"])
        assert result.exit_code == 1
        assert "mock deploy" in result.stdout
        assert "mock deploy error" in result.stdout

    def test_no_application(
        self,
        caplog: LogCaptureFixture,
        runner: CliRunner,
        mock_azuresdk_get_subscription_name,  # noqa: ARG002
        mock_contextmanager_assert_context,  # noqa: ARG002
        mock_graph_api_token,  # noqa: ARG002
        mock_ip_1_2_3_4,  # noqa: ARG002
        mock_pulumi_config_from_remote_or_create,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
    ) -> None:
        result = runner.invoke(sre_command_group, ["deploy", "sandbox"])
        assert result.exit_code == 1
        assert (
            "No Entra application 'Data Safe Haven (Acme Deployment) Pulumi Service Principal' was found."
            in caplog.text
        )
        assert "Please redeploy your SHM." in caplog.text

    def test_no_application_secret(
        self,
        caplog: LogCaptureFixture,
        runner: CliRunner,
        context: Context,
        mocker: MockerFixture,
        mock_azuresdk_get_subscription_name,  # noqa: ARG002
        mock_graph_api_get_application_by_name,  # noqa: ARG002
        mock_graph_api_token,  # noqa: ARG002
        mock_ip_1_2_3_4,  # noqa: ARG002
        mock_pulumi_config_from_remote_or_create,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
    ) -> None:
        mocker.patch.object(
            AzureSdk, "get_keyvault_secret", side_effect=DataSafeHavenAzureError("")
        )
        mocker.patch.object(ContextManager, "assert_context", return_value=context)
        result = runner.invoke(sre_command_group, ["deploy", "sandbox"])
        assert result.exit_code == 1
        assert (
            "No Entra application secret 'Pulumi Deployment Secret' was found. Please redeploy your SHM."
            in caplog.text
        )

    def test_no_context_file(self, runner_no_context_file) -> None:
        result = runner_no_context_file.invoke(sre_command_group, ["deploy", "sandbox"])
        assert result.exit_code == 1
        assert "Could not find file" in result.stdout

    def test_auth_failure(
        self,
        runner: CliRunner,
        mock_azuresdk_get_credential_failure,  # noqa: ARG002
    ) -> None:
        result = runner.invoke(sre_command_group, ["deploy", "sandbox"])
        assert result.exit_code == 1
        assert "mock get_credential\n" in result.stdout
        assert "mock get_credential error" in result.stdout

    def test_no_shm(
        self,
        capfd,
        runner: CliRunner,
        mock_shm_config_from_remote_fails,  # noqa: ARG002
    ) -> None:
        result = runner.invoke(sre_command_group, ["deploy", "sandbox"])
        out, _ = capfd.readouterr()
        assert result.exit_code == 1
        assert "mock from_remote failure" in out


class TestTeardownSRE:
    def test_teardown(
        self,
        runner: CliRunner,
        mock_graph_api_token,  # noqa: ARG002
        mock_ip_1_2_3_4,  # noqa: ARG002
        mock_pulumi_config_from_remote,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        mock_sre_project_manager_teardown_then_exit,  # noqa: ARG002
    ) -> None:
        result = runner.invoke(sre_command_group, ["teardown", "sandbox"])
        assert result.exit_code == 1
        assert "mock teardown" in result.stdout

    def test_no_context_file(self, runner_no_context_file) -> None:
        result = runner_no_context_file.invoke(
            sre_command_group, ["teardown", "sandbox"]
        )
        assert result.exit_code == 1
        assert "Could not find file" in result.stdout

    def test_no_shm(
        self,
        capfd: CaptureFixture,
        runner: CliRunner,
        mock_shm_config_from_remote_fails,  # noqa: ARG002
    ) -> None:
        result = runner.invoke(sre_command_group, ["teardown", "sandbox"])
        out, _ = capfd.readouterr()
        assert result.exit_code == 1
        assert "mock from_remote failure" in out

    def test_auth_failure(
        self,
        runner: CliRunner,
        mock_azuresdk_get_credential_failure,  # noqa: ARG002
    ) -> None:
        result = runner.invoke(sre_command_group, ["teardown", "sandbox"])
        assert result.exit_code == 1
        assert "mock get_credential\n" in result.stdout
        assert "mock get_credential error" in result.stdout
