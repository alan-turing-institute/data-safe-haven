from data_safe_haven.commands.pulumi import pulumi_command_group


class TestRun:
    def test_run_shm(
        self,
        runner,
        mock_config_from_remote,  # noqa: ARG002
        mock_pulumi_config_from_remote,  # noqa: ARG002
        mock_azure_cli_confirm,  # noqa: ARG002
        mock_install_plugins,  # noqa: ARG002
        mock_key_vault_key,  # noqa: ARG002
        offline_pulumi_account,  # noqa: ARG002
        local_project_settings,  # noqa: ARG002
    ):
        result = runner.invoke(pulumi_command_group, ["shm", "stack ls"])
        assert result.exit_code == 0
        assert "shm-acmedeployment*" in result.stdout

    def test_run_shm_invalid(
        self,
        runner,
        mock_config_from_remote,  # noqa: ARG002
        mock_pulumi_config_from_remote,  # noqa: ARG002
        mock_azure_cli_confirm,  # noqa: ARG002
        mock_install_plugins,  # noqa: ARG002
        mock_key_vault_key,  # noqa: ARG002
        offline_pulumi_account,  # noqa: ARG002
        local_project_settings,  # noqa: ARG002
    ):
        result = runner.invoke(pulumi_command_group, ["shm", "not a pulumi command"])
        assert result.exit_code == 1

    def test_run_sre_no_name(
        self,
        runner,
    ):
        result = runner.invoke(pulumi_command_group, ["sre", "stack ls"])
        assert result.exit_code == 1
        assert "--sre-name is required." in result.stdout
