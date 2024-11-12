from data_safe_haven.commands.shm import shm_command_group


class TestDeploySHM:
    def test_infrastructure_deploy(
        self,
        runner,
        mock_imperative_shm_deploy_then_exit,  # noqa: ARG002
        mock_graph_api_add_custom_domain,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_shm_config_remote_exists,  # noqa: ARG002
        mock_shm_config_upload,  # noqa: ARG002
    ):
        result = runner.invoke(shm_command_group, ["deploy"])
        assert result.exit_code == 1
        assert "mock deploy" in result.stdout
        assert "mock deploy error" in result.stdout

    def test_infrastructure_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(shm_command_group, ["deploy"])
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout

    def test_infrastructure_show_none(self, runner_none):
        result = runner_none.invoke(shm_command_group, ["deploy"])
        assert result.exit_code == 1
        assert "No context selected." in result.stdout

    def test_infrastructure_auth_failure(
        self,
        runner,
        mock_azuresdk_get_credential_failure,  # noqa: ARG002
    ):
        result = runner.invoke(shm_command_group, ["deploy"])
        assert result.exit_code == 1
        assert "mock get_credential\n" in result.stdout
        assert "mock get_credential error" in result.stdout


class TestTeardownSHM:
    def test_teardown(
        self,
        runner,
        mock_imperative_shm_teardown_then_exit,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_shm_config_remote_exists,  # noqa: ARG002
    ):
        result = runner.invoke(shm_command_group, ["teardown"], input="y")
        assert result.exit_code == 1
        assert "mock teardown" in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(shm_command_group, ["teardown"])
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout

    def test_show_none(self, runner_none):
        result = runner_none.invoke(shm_command_group, ["teardown"])
        assert result.exit_code == 1
        assert "No context selected." in result.stdout

    def test_auth_failure(
        self,
        runner,
        mock_azuresdk_get_credential_failure,  # noqa: ARG002
        mock_shm_config_remote_exists,  # noqa: ARG002
    ):
        result = runner.invoke(shm_command_group, ["teardown"])
        assert result.exit_code == 1
        assert "mock get_credential\n" in result.stdout
        assert "mock get_credential error" in result.stdout
        assert "Could not teardown Safe Haven Management environment." in result.stdout

    def test_teardown_sres_exist(
        self,
        runner,
        mock_azuresdk_get_subscription_name,  # noqa: ARG002
        mock_pulumi_config_from_remote,  # noqa: ARG002
        mock_pulumi_config_remote_exists,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_shm_config_remote_exists,  # noqa: ARG002
    ):
        result = runner.invoke(shm_command_group, ["teardown"], input="y")
        assert result.exit_code == 1
        assert "Found deployed SREs" in result.stdout

    def test_teardown_user_cancelled(
        self,
        runner,
        mock_azuresdk_get_subscription_name,  # noqa: ARG002
        mock_pulumi_config_from_remote,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_shm_config_remote_exists,  # noqa: ARG002
    ):
        result = runner.invoke(shm_command_group, ["teardown"], input="n")
        assert result.exit_code == 0
        assert "cancelled" in result.stdout

    def test_teardown_no_pulumi_config(
        self,
        runner,
        mock_azuresdk_get_subscription_name,  # noqa: ARG002
        mock_pulumi_config_from_remote_fails,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_imperative_shm_teardown_then_exit,  # noqa: ARG002
        mock_shm_config_remote_exists,  # noqa: ARG002
    ):
        result = runner.invoke(shm_command_group, ["teardown"], input="y")
        assert result.exit_code == 1
        assert "mock teardown" in result.stdout
