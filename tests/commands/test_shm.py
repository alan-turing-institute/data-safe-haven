import data_safe_haven.commands.shm
from data_safe_haven.commands.shm import shm_command_group
from data_safe_haven.context_infrastructure import ContextInfrastructure
from data_safe_haven.exceptions import DataSafeHavenAzureAPIAuthenticationError
from data_safe_haven.external import AzureApi
from data_safe_haven.external.interface.azure_authenticator import AzureAuthenticator


class TestDeploySHM:
    def test_context_infrastructure_create(self, runner, monkeypatch):
        def mock_create_then_exit(self):  # noqa: ARG001
            print("mock create")  # noqa: T201
            msg = "Failed to authenticate with Azure API."
            raise DataSafeHavenAzureAPIAuthenticationError(msg)

        monkeypatch.setattr(ContextInfrastructure, "create", mock_create_then_exit)

        result = runner.invoke(shm_command_group, ["deploy"])
        assert "mock create" in result.stdout
        assert result.exit_code == 1

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(shm_command_group, ["deploy"])
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout

    def test_infrastructure_show_none(self, runner_none):
        result = runner_none.invoke(shm_command_group, ["deploy"])
        assert result.exit_code == 1
        assert "No context selected." in result.stdout

    def test_infrastructure_auth_failure(self, runner, mocker):
        def mock_login_failure(self):  # noqa: ARG001
            msg = "Failed to authenticate with Azure API."
            raise DataSafeHavenAzureAPIAuthenticationError(msg)

        mocker.patch.object(AzureAuthenticator, "login", mock_login_failure)

        result = runner.invoke(shm_command_group, ["deploy"])
        assert result.exit_code == 1
        assert "Failed to authenticate with the Azure API." in result.stdout

    def test_pulumi_config_upload(
        self,
        mocker,
        runner,
        context,
        mock_shm_config_from_remote,  # noqa: ARG002
        monkeypatch,
    ):
        def mock_create(self):  # noqa: ARG001
            print("mock create")  # noqa: T201

        def mock_exception():
            raise Exception

        monkeypatch.setattr(ContextInfrastructure, "create", mock_create)

        # Make the step after DSHPulumi deployment in shm deploy function raise an exception
        mocker.patch.object(
            data_safe_haven.commands.shm.GraphApi, "__init__", mock_exception
        )
        # Ensure a new DSHPulumiProject is created
        mocker.patch.object(AzureApi, "blob_exists", return_value=False)
        # Mock DSHPulumiConfig.upload
        mock_upload = mocker.patch.object(
            data_safe_haven.commands.shm.DSHPulumiConfig, "upload", return_value=None
        )

        result = runner.invoke(shm_command_group, ["deploy"])

        assert result.exit_code == 1
        mock_upload.assert_called_once_with(context)


class TestTeardownSHM:
    def test_teardown(self, runner, monkeypatch):
        def mock_teardown_then_exit(self):  # noqa: ARG001
            print("mock teardown")  # noqa: T201
            msg = "Failed to authenticate with Azure API."
            raise DataSafeHavenAzureAPIAuthenticationError(msg)

        monkeypatch.setattr(ContextInfrastructure, "teardown", mock_teardown_then_exit)

        result = runner.invoke(shm_command_group, ["teardown"])
        assert "mock teardown" in result.stdout
        assert result.exit_code == 1

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(shm_command_group, ["teardown"])
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout

    def test_show_none(self, runner_none):
        result = runner_none.invoke(shm_command_group, ["teardown"])
        assert result.exit_code == 1
        assert "No context selected." in result.stdout

    def test_auth_failure(self, runner, mocker):
        def mock_login(self):  # noqa: ARG001
            msg = "Failed to authenticate with Azure API."
            raise DataSafeHavenAzureAPIAuthenticationError(msg)

        mocker.patch.object(AzureAuthenticator, "login", mock_login)

        result = runner.invoke(shm_command_group, ["teardown"])
        assert result.exit_code == 1
        assert "Failed to authenticate with the Azure API." in result.stdout
