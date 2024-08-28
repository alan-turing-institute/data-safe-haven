from data_safe_haven.commands.sre import sre_command_group


class TestDeploySRE:
    def test_deploy(
        self,
        runner,
        mock_graph_api_token,  # noqa: ARG002
        mock_contextmanager_assert_context,  # noqa: ARG002
        mock_ip_1_2_3_4,  # noqa: ARG002
        mock_pulumi_config_from_remote_or_create,  # noqa: ARG002
        mock_pulumi_config_upload,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        mock_graph_api_get_application_by_name,  # noqa: ARG002
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
        mock_azuresdk_get_credential_failure,  # noqa: ARG002
    ):
        result = runner.invoke(sre_command_group, ["deploy", "sandbox"])
        assert result.exit_code == 1
        assert "mock get_credential\n" in result.stdout
        assert "mock get_credential error" in result.stdout

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


class TestTeardownSRE:
    def test_teardown(
        self,
        runner,
        mock_graph_api_token,  # noqa: ARG002
        mock_ip_1_2_3_4,  # noqa: ARG002
        mock_pulumi_config_from_remote,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        mock_sre_project_manager_teardown_then_exit,  # noqa: ARG002
    ):
        result = runner.invoke(sre_command_group, ["teardown", "sandbox"])
        assert result.exit_code == 1
        assert "mock teardown" in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(
            sre_command_group, ["teardown", "sandbox"]
        )
        assert result.exit_code == 1
        assert "Could not find file" in result.stdout

    def test_no_shm(
        self,
        capfd,
        runner,
        mock_shm_config_from_remote_fails,  # noqa: ARG002
    ):
        result = runner.invoke(sre_command_group, ["teardown", "sandbox"])
        out, _ = capfd.readouterr()
        assert result.exit_code == 1
        assert "mock from_remote failure" in out

    def test_auth_failure(
        self,
        runner,
        mock_azuresdk_get_credential_failure,  # noqa: ARG002
    ):
        result = runner.invoke(sre_command_group, ["teardown", "sandbox"])
        assert result.exit_code == 1
        assert "mock get_credential\n" in result.stdout
        assert "mock get_credential error" in result.stdout
