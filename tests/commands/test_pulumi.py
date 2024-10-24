from data_safe_haven.commands.pulumi import pulumi_command_group


class TestRun:
    def test_run_sre(
        self,
        runner,
        local_project_settings,  # noqa: ARG002
        mock_install_plugins,  # noqa: ARG002
        mock_key_vault_key,  # noqa: ARG002
        mock_pulumi_config_no_key_from_remote,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        offline_pulumi_account,  # noqa: ARG002
    ):
        result = runner.invoke(pulumi_command_group, ["sandbox", "stack ls"])
        assert result.exit_code == 0
        assert "shm-acmedeployment-sre-sandbox*" in result.stdout

    def test_run_sre_incorrect_arguments(
        self,
        runner,
    ):
        result = runner.invoke(pulumi_command_group, ["stack ls"])
        assert result.exit_code == 2
        assert "Usage: run [OPTIONS] SRE_NAME COMMAND" in result.stderr

    def test_run_sre_invalid_command(
        self,
        runner,
        local_project_settings,  # noqa: ARG002
        mock_install_plugins,  # noqa: ARG002
        mock_key_vault_key,  # noqa: ARG002
        mock_pulumi_config_no_key_from_remote,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        offline_pulumi_account,  # noqa: ARG002
    ):
        result = runner.invoke(
            pulumi_command_group, ["sandbox", "not a pulumi command"]
        )
        assert result.exit_code == 1
        assert "Failed to run command 'not a pulumi command'." in result.stdout

    def test_run_sre_invalid_name(
        self,
        runner,
        local_project_settings,  # noqa: ARG002
        mock_install_plugins,  # noqa: ARG002
        mock_key_vault_key,  # noqa: ARG002
        mock_pulumi_config_no_key_from_remote,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_alternate_from_remote,  # noqa: ARG002
        offline_pulumi_account,  # noqa: ARG002
    ):
        result = runner.invoke(pulumi_command_group, ["alternate", "stack ls"])
        assert result.exit_code == 1
        assert "No SRE named alternative is defined" in result.stdout
