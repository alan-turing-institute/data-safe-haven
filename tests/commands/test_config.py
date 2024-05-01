from data_safe_haven.commands.config import config_command_group
from data_safe_haven.config import Config
from data_safe_haven.external import AzureApi


class TestTemplate:
    def test_template(self, runner):
        result = runner.invoke(config_command_group, ["template"])
        assert result.exit_code == 0
        assert "subscription_id: Azure subscription ID" in result.stdout
        assert "shm:" in result.stdout
        assert "sres:" in result.stdout

    def test_template_file(self, runner, tmp_path):
        template_file = (tmp_path / "template_create.yaml").absolute()
        result = runner.invoke(
            config_command_group, ["template", "--file", str(template_file)]
        )
        assert result.exit_code == 0
        with open(template_file) as f:
            template_text = f.read()
        assert "subscription_id: Azure subscription ID" in template_text
        assert "shm:" in template_text
        assert "sres:" in template_text


class TestUpload:
    def test_upload(self, mocker, context, runner, config_yaml, config_file):
        mock_method = mocker.patch.object(AzureApi, "upload_blob", return_value=None)
        result = runner.invoke(
            config_command_group,
            ["upload", str(config_file)],
        )
        assert result.exit_code == 0

        mock_method.assert_called_once_with(
            config_yaml,
            Config.filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_upload_no_file(self, mocker, runner):
        mocker.patch.object(AzureApi, "upload_blob", return_value=None)
        result = runner.invoke(
            config_command_group,
            ["upload"],
        )
        assert result.exit_code == 2


class TestShow:
    def test_show(self, mocker, runner, context, config_yaml):
        mock_method = mocker.patch.object(
            AzureApi, "download_blob", return_value=config_yaml
        )
        result = runner.invoke(config_command_group, ["show"])

        assert result.exit_code == 0
        assert config_yaml in result.stdout

        mock_method.assert_called_once_with(
            Config.filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_show_file(self, mocker, runner, config_yaml, tmp_path):
        mocker.patch.object(AzureApi, "download_blob", return_value=config_yaml)
        template_file = (tmp_path / "template_show.yaml").absolute()
        result = runner.invoke(
            config_command_group, ["show", "--file", str(template_file)]
        )

        assert result.exit_code == 0
        with open(template_file) as f:
            template_text = f.read()
        assert config_yaml in template_text
