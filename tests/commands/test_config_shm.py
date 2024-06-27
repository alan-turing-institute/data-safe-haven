from data_safe_haven.commands.config import config_command_group
from data_safe_haven.config import SHMConfig
from data_safe_haven.external import AzureApi


class TestShowSHM:
    def test_show(self, mocker, runner, context, shm_config_yaml):
        mock_method = mocker.patch.object(
            AzureApi, "download_blob", return_value=shm_config_yaml
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
        mocker.patch.object(AzureApi, "download_blob", return_value=shm_config_yaml)
        template_file = (tmp_path / "template_show.yaml").absolute()
        result = runner.invoke(
            config_command_group, ["show-shm", "--file", str(template_file)]
        )

        assert result.exit_code == 0
        with open(template_file) as f:
            template_text = f.read()
        assert shm_config_yaml in template_text
