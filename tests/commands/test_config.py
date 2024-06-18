from data_safe_haven.commands.config import config_command_group
from data_safe_haven.config import Config
from data_safe_haven.external import AzureApi


class TestTemplate:
    def test_template(self, runner):
        result = runner.invoke(config_command_group, ["template-sre"])
        assert result.exit_code == 0
        assert "subscription_id: Azure subscription ID" in result.stdout
        assert "shm:" in result.stdout
        assert "sre:" in result.stdout

    def test_template_file(self, runner, tmp_path):
        template_file = (tmp_path / "template_create.yaml").absolute()
        result = runner.invoke(
            config_command_group, ["template-sre", "--file", str(template_file)]
        )
        assert result.exit_code == 0
        with open(template_file) as f:
            template_text = f.read()
        assert "subscription_id: Azure subscription ID" in template_text
        assert "shm:" in template_text
        assert "sre:" in template_text


class TestUpload:
    def test_upload_new(
        self, mocker, context, runner, sre_config_yaml, sre_config_file
    ):
        sre_name = "sre 1"
        sre_filename = Config.sre_filename_from_name(sre_name)
        mock_exists = mocker.patch.object(Config, "remote_exists", return_value=False)
        mock_upload = mocker.patch.object(AzureApi, "upload_blob", return_value=None)
        result = runner.invoke(
            config_command_group,
            ["upload-sre", sre_name, str(sre_config_file)],
        )
        assert result.exit_code == 0

        mock_exists.assert_called_once_with(context, filename=sre_filename)
        mock_upload.assert_called_once_with(
            sre_config_yaml,
            sre_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_upload_no_changes(
        self, mocker, context, runner, sre_config, sre_config_file
    ):
        sre_name = "sre 1"
        sre_filename = Config.sre_filename_from_name(sre_name)
        mock_exists = mocker.patch.object(Config, "remote_exists", return_value=True)
        mock_from_remote = mocker.patch.object(
            Config, "from_remote", return_value=sre_config
        )
        mock_upload = mocker.patch.object(AzureApi, "upload_blob", return_value=None)
        result = runner.invoke(
            config_command_group,
            ["upload-sre", sre_name, str(sre_config_file)],
        )
        assert result.exit_code == 0

        mock_exists.assert_called_once_with(context, filename=sre_filename)
        mock_from_remote.assert_called_once_with(context, filename=sre_filename)
        mock_upload.assert_not_called()

        assert "No changes, won't upload configuration." in result.stdout

    def test_upload_changes(
        self,
        mocker,
        context,
        runner,
        sre_config_alternate,
        sre_config_file,
        sre_config_yaml,
    ):
        sre_name = "sre 1"
        sre_filename = Config.sre_filename_from_name(sre_name)
        mock_exists = mocker.patch.object(Config, "remote_exists", return_value=True)
        mock_from_remote = mocker.patch.object(
            Config, "from_remote", return_value=sre_config_alternate
        )
        mock_upload = mocker.patch.object(AzureApi, "upload_blob", return_value=None)
        result = runner.invoke(
            config_command_group,
            ["upload-sre", sre_name, str(sre_config_file)],
            input="y\n",
        )
        assert result.exit_code == 0

        mock_exists.assert_called_once_with(context, filename=sre_filename)
        mock_from_remote.assert_called_once_with(context, filename=sre_filename)
        mock_upload.assert_called_once_with(
            sre_config_yaml,
            sre_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

        assert "--- remote" in result.stdout
        assert "+++ local" in result.stdout

    def test_upload_changes_n(
        self, mocker, context, runner, sre_config_alternate, sre_config_file
    ):
        sre_name = "sre 1"
        sre_filename = Config.sre_filename_from_name(sre_name)
        mock_exists = mocker.patch.object(Config, "remote_exists", return_value=True)
        mock_from_remote = mocker.patch.object(
            Config, "from_remote", return_value=sre_config_alternate
        )
        mock_upload = mocker.patch.object(AzureApi, "upload_blob", return_value=None)
        result = runner.invoke(
            config_command_group,
            ["upload-sre", sre_name, str(sre_config_file)],
            input="n\n",
        )
        assert result.exit_code == 0

        mock_exists.assert_called_once_with(context, filename=sre_filename)
        mock_from_remote.assert_called_once_with(context, filename=sre_filename)
        mock_upload.assert_not_called()

        assert "--- remote" in result.stdout
        assert "+++ local" in result.stdout

    def test_upload_no_file(self, mocker, runner):
        mocker.patch.object(AzureApi, "upload_blob", return_value=None)
        result = runner.invoke(
            config_command_group,
            ["upload-sre", "sre-name"],
        )
        assert result.exit_code == 2


class TestShow:
    def test_show(self, mocker, runner, context, sre_config_yaml):
        sre_name = "sre 1"
        mock_method = mocker.patch.object(
            AzureApi, "download_blob", return_value=sre_config_yaml
        )
        result = runner.invoke(config_command_group, ["show-sre", sre_name])

        assert result.exit_code == 0
        assert sre_config_yaml in result.stdout

        mock_method.assert_called_once_with(
            Config.sre_filename_from_name(sre_name),
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_show_file(self, mocker, runner, sre_config_yaml, tmp_path):
        mocker.patch.object(AzureApi, "download_blob", return_value=sre_config_yaml)
        template_file = (tmp_path / "template_show.yaml").absolute()
        result = runner.invoke(
            config_command_group, ["show-sre", "sre-name", "--file", str(template_file)]
        )

        assert result.exit_code == 0
        with open(template_file) as f:
            template_text = f.read()
        assert sre_config_yaml in template_text
