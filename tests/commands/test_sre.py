from data_safe_haven.commands.sre import sre_command_group


class TestDeploySRE:
    def test_deploy(
        self,
        runner,
        mock_azure_cli_confirm,  # noqa: ARG002
        mock_graph_api_create_token_administrator,  # noqa: ARG002
        mock_pulumi_config_from_remote_or_create,  # noqa: ARG002
        mock_pulumi_config_upload,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        mock_sre_project_manager_deploy_then_exit,  # noqa: ARG002
    ):
        result = runner.invoke(sre_command_group, ["deploy", "sandbox"])
        assert result.exit_code == 1
        assert "mock deploy" in result.stdout
        assert "mock deploy error" in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(sre_command_group, ["deploy", "sandbox"])
        assert result.exit_code == 1
        assert "Could not find file" in result.stdout

    def test_auth_failure(
        self,
        runner,
        mock_azure_authenticator_login_exception,  # noqa: ARG002
    ):
        result = runner.invoke(sre_command_group, ["deploy", "sandbox"])
        assert result.exit_code == 1
        assert "mock login" in result.stdout
        assert "mock login error" in result.stdout

    def test_no_shm(
        self,
        capfd,
        runner,
        mock_shm_config_from_remote_fails,  # noqa: ARG002
    ):
        result = runner.invoke(sre_command_group, ["deploy", "sandbox"])
        out, _ = capfd.readouterr()
        assert result.exit_code == 1
        assert "mock from_remote failure" in out
