import data_safe_haven.commands.shm
from data_safe_haven.commands.shm import shm_command_group
from data_safe_haven.external import AzureApi


class TestDeploySHM:
    def test_ensure_pulumi_config_upload(
        self,
        mocker,
        runner,
        context,
        mock_shm_config_from_remote,  # noqa: ARG002
    ):
        def exception():
            raise Exception

        # Make early step in shm deploy function raise an exception
        mocker.patch.object(
            data_safe_haven.commands.shm.GraphApi, "__init__", exception
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
