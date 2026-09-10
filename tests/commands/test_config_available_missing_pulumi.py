from data_safe_haven.commands.config import config_command_group
from data_safe_haven.config import ContextManager, DSHPulumiConfig
from data_safe_haven.external import AzureSdk


def test_available_before_first_sre_deployment(context_manager, mocker, runner):
    mocker.patch.object(ContextManager, "from_file", return_value=context_manager)
    mocker.patch.object(AzureSdk, "list_blobs", return_value=["sre-sandbox.yaml"])
    mocker.patch.object(DSHPulumiConfig, "remote_exists", return_value=False)
    mock_download = mocker.patch.object(AzureSdk, "download_blob")

    result = runner.invoke(config_command_group, ["available"])

    assert result.exit_code == 0
    assert "Available SRE configurations" in result.stdout
    assert "sandbox" in result.stdout
    mock_download.assert_not_called()
