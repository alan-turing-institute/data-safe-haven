from data_safe_haven.commands.config import config_command_group
from data_safe_haven.config import ContextManager, SHMConfig
from data_safe_haven.exceptions import DataSafeHavenAzureError, DataSafeHavenConfigError
from data_safe_haven.external import AzureSdk


class TestShowSHM:
    def test_show(self, mocker, runner, context, shm_config_yaml):
        mock_method = mocker.patch.object(
            AzureSdk, "download_blob", return_value=shm_config_yaml
        )
        result = runner.invoke(config_command_group, ["show-shm"])

        assert result.exit_code == 0
        assert shm_config_yaml in result.stdout

        mock_method.assert_called_once_with(
            SHMConfig.default_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_show_file(self, mocker, runner, shm_config_yaml, tmp_path):
        mocker.patch.object(AzureSdk, "download_blob", return_value=shm_config_yaml)
        template_file = (tmp_path / "template_show.yaml").absolute()
        result = runner.invoke(
            config_command_group, ["show-shm", "--file", str(template_file)]
        )

        assert result.exit_code == 0
        with open(template_file) as f:
            template_text = f.read()
        assert shm_config_yaml in template_text

    def test_no_remote(self, mocker, runner):

        mocker.patch.object(
            SHMConfig, "from_remote", side_effect=DataSafeHavenAzureError(" ")
        )
        result = runner.invoke(config_command_group, ["show-shm"])
        assert "SHM must be deployed" in result.stdout
        assert result.exit_code == 1

    def test_no_context(self, mocker, runner):

        mocker.patch.object(
            ContextManager, "from_file", side_effect=DataSafeHavenConfigError(" ")
        )
        result = runner.invoke(config_command_group, ["show-shm"])
        assert "No context is selected" in result.stdout
        assert result.exit_code == 1

    def test_no_selected_context(self, mocker, runner):

        mocker.patch.object(
            ContextManager, "assert_context", side_effect=DataSafeHavenConfigError(" ")
        )
        result = runner.invoke(config_command_group, ["show-shm"])
        assert "No context is selected" in result.stdout
        assert result.exit_code == 1
