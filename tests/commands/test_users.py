from data_safe_haven.commands.users import users_command_group


class TestAdd:
    def test_invalid_shm(
        self,
        mocker,
        runner,
        tmp_contexts_gems,  # noqa: ARG002
        mock_config_from_remote,  # noqa: ARG002
        mock_pulumi_config_from_remote,  # noqa: ARG002
    ):
        result = runner.invoke(users_command_group, ["add", "users.csv"])

        assert result.exit_code == 1
        assert "Have you deployed the SHM?" in result.stdout
