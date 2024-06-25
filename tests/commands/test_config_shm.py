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


class TestTemplateSHM:
    def test_template(self, runner):
        result = runner.invoke(config_command_group, ["template-shm"])
        assert result.exit_code == 0
        assert (
            "subscription_id: ID of the Azure subscription that the TRE will be deployed to"
            in result.stdout
        )
        assert "shm:" in result.stdout

    def test_template_file(self, runner, tmp_path):
        template_file = (tmp_path / "template_create.yaml").absolute()
        result = runner.invoke(
            config_command_group, ["template-shm", "--file", str(template_file)]
        )
        assert result.exit_code == 0
        with open(template_file) as f:
            template_text = f.read()
        assert (
            "subscription_id: ID of the Azure subscription that the TRE will be deployed to"
            in template_text
        )
        assert "shm:" in template_text


class TestUploadSHM:
    def test_upload_new(
        self, mocker, context, runner, shm_config_yaml, shm_config_file
    ):
        mock_exists = mocker.patch.object(
            SHMConfig, "remote_exists", return_value=False
        )
        mock_upload = mocker.patch.object(AzureApi, "upload_blob", return_value=None)
        result = runner.invoke(
            config_command_group,
            ["upload-shm", str(shm_config_file)],
        )
        assert result.exit_code == 0

        mock_exists.assert_called_once_with(context)
        mock_upload.assert_called_once_with(
            shm_config_yaml,
            SHMConfig.default_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

    def test_upload_no_changes(
        self, mocker, context, runner, shm_config, shm_config_file
    ):
        mock_exists = mocker.patch.object(SHMConfig, "remote_exists", return_value=True)
        mock_from_remote = mocker.patch.object(
            SHMConfig, "from_remote", return_value=shm_config
        )
        mock_upload = mocker.patch.object(AzureApi, "upload_blob", return_value=None)
        result = runner.invoke(
            config_command_group,
            ["upload-shm", str(shm_config_file)],
        )
        assert result.exit_code == 0

        mock_exists.assert_called_once_with(context)
        mock_from_remote.assert_called_once_with(context, filename=None)
        mock_upload.assert_not_called()

        assert "No changes, won't upload configuration." in result.stdout

    def test_upload_changes(
        self,
        mocker,
        context,
        runner,
        shm_config_alternate,
        shm_config_file,
        shm_config_yaml,
    ):
        mock_exists = mocker.patch.object(SHMConfig, "remote_exists", return_value=True)
        mock_from_remote = mocker.patch.object(
            SHMConfig, "from_remote", return_value=shm_config_alternate
        )
        mock_upload = mocker.patch.object(AzureApi, "upload_blob", return_value=None)
        result = runner.invoke(
            config_command_group,
            ["upload-shm", str(shm_config_file)],
            input="y\n",
        )
        assert result.exit_code == 0

        mock_exists.assert_called_once_with(context)
        mock_from_remote.assert_called_once_with(context, filename=None)
        mock_upload.assert_called_once_with(
            shm_config_yaml,
            SHMConfig.default_filename,
            context.resource_group_name,
            context.storage_account_name,
            context.storage_container_name,
        )

        assert "--- remote" in result.stdout
        assert "+++ local" in result.stdout

    def test_upload_changes_n(
        self, mocker, context, runner, shm_config_alternate, shm_config_file
    ):
        mock_exists = mocker.patch.object(SHMConfig, "remote_exists", return_value=True)
        mock_from_remote = mocker.patch.object(
            SHMConfig, "from_remote", return_value=shm_config_alternate
        )
        mock_upload = mocker.patch.object(AzureApi, "upload_blob", return_value=None)
        result = runner.invoke(
            config_command_group,
            ["upload-shm", str(shm_config_file)],
            input="n\n",
        )
        assert result.exit_code == 0

        mock_exists.assert_called_once_with(context)
        mock_from_remote.assert_called_once_with(context, filename=None)
        mock_upload.assert_not_called()

        assert "--- remote" in result.stdout
        assert "+++ local" in result.stdout

    def test_upload_no_file(self, mocker, runner):
        mocker.patch.object(AzureApi, "upload_blob", return_value=None)
        result = runner.invoke(
            config_command_group,
            ["upload-shm"],
        )
        assert result.exit_code == 2
