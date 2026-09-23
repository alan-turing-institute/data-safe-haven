from pytest import CaptureFixture, LogCaptureFixture
from pytest_mock import MockerFixture
from typer.testing import CliRunner

from data_safe_haven.commands.sre import sre_command_group
from data_safe_haven.config import Context, ContextManager
from data_safe_haven.exceptions import DataSafeHavenAzureError
from data_safe_haven.external import AzureSdk, GraphApi


class TestDeploySRE:
    def test_deploy(
        self,
        runner: CliRunner,
        mock_azuresdk_get_subscription_name,  # noqa: ARG002
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

    def test_deploy_cli_full(
        self,
        runner: CliRunner,
        mock_azuresdk_get_subscription_name,  # noqa: ARG002
        mock_contextmanager_assert_context,  # noqa: ARG002
        mock_ip_1_2_3_4,  # noqa: ARG002
        mock_pulumi_config_from_remote_or_create,  # noqa: ARG002
        mock_pulumi_config_upload,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        mock_graph_api_get_application_by_name,  # noqa: ARG002
        mock_upgrade_accept,  # noqa: ARG002
        mock_sre_deploy_actions,  # noqa: ARG002
        mock_azuresdk_get_credential,  # noqa: ARG002
    ) -> None:
        result = runner.invoke(sre_command_group, ["deploy", "sandbox"])
        assert result.exit_code == 1
        assert "SRE will be registered in SHM 'shm.acme.com'" in result.stdout
        assert (
            "SHM is deployed to subscription 'Data Safe Haven Acme' (35ebced1-4e7a-4c1f-b634-c0886937085d)"
            in result.stdout
        )
        assert (
            "Ensure config: azure-native:subscriptionId=35ebced1-4e7a-4c1f-b634-c0886937085d"
            in result.stdout
        )
        assert (
            "Ensure config: azure-native:tenantId=d5c5c439-1115-4cb6-ab50-b8e547b6c8dd"
            in result.stdout
        )
        assert (
            "Set config: shm-subscription-id=35ebced1-4e7a-4c1f-b634-c0886937085d"
            in result.stdout
        )
        assert "Deploy refresh: run_program=False" in result.stdout
        assert "Deploy preview: disable_diff=False" in result.stdout
        assert "Deploy update" in result.stdout
        assert (
            "Could not deploy Secure Research Environment 'sandbox'"
            not in result.stdout
        )

    def test_no_application(
        self,
        caplog: LogCaptureFixture,
        runner: CliRunner,
        mocker,
        mock_azuresdk_get_subscription_name,  # noqa: ARG002
        mock_contextmanager_assert_context,  # noqa: ARG002
        mock_ip_1_2_3_4,  # noqa: ARG002
        mock_pulumi_config_from_remote_or_create,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        mock_graphapi_get_credential,  # noqa: ARG002
    ) -> None:
        mocker.patch.object(GraphApi, "get_application_by_name", return_value=None)

        result = runner.invoke(sre_command_group, ["deploy", "sandbox"])
        assert result.exit_code == 1
        assert (
            "No Entra application 'Data Safe Haven (acmedeployment) Pulumi Service Principal' was found."
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
        mock_ip_1_2_3_4,  # noqa: ARG002
        mock_pulumi_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        mock_sre_project_manager_teardown_then_exit,  # noqa: ARG002
    ) -> None:
        result = runner.invoke(sre_command_group, ["teardown", "sandbox"], input="y")
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

    def test_teardown_cancelled(
        self,
        runner: CliRunner,
        mock_ip_1_2_3_4,  # noqa: ARG002
        mock_pulumi_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        mock_sre_project_manager_teardown_then_exit,  # noqa: ARG002
    ) -> None:
        result = runner.invoke(sre_command_group, ["teardown", "sandbox"], input="n")
        assert result.exit_code == 0
        assert "cancelled by user" in result.stdout
