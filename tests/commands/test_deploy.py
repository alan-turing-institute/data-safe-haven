import data_safe_haven.commands.deploy
from data_safe_haven.commands.deploy import deploy_command_group
from data_safe_haven.external import AzureApi


class TestDeploySHM:
    def test_ensure_pulumi_config_upload(
        self,
        mocker,
        runner,
        context,
        mock_config_from_remote,  # noqa: ARG002
    ):
        def exception():
            raise Exception

        # Make early step in shm deploy function raise an exception
        mocker.patch.object(
            data_safe_haven.commands.deploy.GraphApi, "__init__", exception
        )
        # Ensure a new DSHPulumiProject is created
        mocker.patch.object(AzureApi, "blob_exists", return_value=False)
        # Mock DSHPulumiConfig.upload
        mock_upload = mocker.patch.object(
            data_safe_haven.commands.deploy.DSHPulumiConfig, "upload", return_value=None
        )

        result = runner.invoke(deploy_command_group, ["shm"])

        assert result.exit_code == 1
        mock_upload.assert_called_once_with(context)
