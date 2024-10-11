from data_safe_haven.commands.users import users_command_group


class TestAdd:
    def test_invalid_shm(
        self,
        mock_shm_config_from_remote_fails,  # noqa: ARG002
        runner,
        tmp_contexts_gems,  # noqa: ARG002
    ):
        result = runner.invoke(users_command_group, ["add", "users.csv"])

        assert result.exit_code == 1
        assert "Have you deployed the SHM?" in result.stdout


class TestListUsers:
    def test_invalid_shm(
        self,
        mock_shm_config_from_remote_fails,  # noqa: ARG002
        runner,
        tmp_contexts_gems,  # noqa: ARG002
    ):
        result = runner.invoke(users_command_group, ["list", "my_sre"])

        assert result.exit_code == 1
        assert "Have you deployed the SHM?" in result.stdout

    def test_invalid_sre(
        self,
        mock_pulumi_config_from_remote,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        runner,
    ):
        result = runner.invoke(users_command_group, ["list", "my_sre"])

        assert result.exit_code == 1
        assert "Is the SRE deployed?" in result.stdout


class TestRegister:
    def test_invalid_shm(
        self,
        mock_shm_config_from_remote_fails,  # noqa: ARG002
        runner,
        tmp_contexts_gems,  # noqa: ARG002
    ):
        result = runner.invoke(
            users_command_group, ["register", "-u", "Harry Lime", "my_sre"]
        )

        assert result.exit_code == 1
        assert "Have you deployed the SHM?" in result.stdout

    def test_invalid_sre(
        self,
        mock_pulumi_config_from_remote,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        runner,
        tmp_contexts,  # noqa: ARG002
    ):
        result = runner.invoke(
            users_command_group, ["register", "-u", "Harry Lime", "my_sre"]
        )

        assert result.exit_code == 1
        assert "Have you deployed the SRE?" in result.stdout


class TestRemove:
    def test_invalid_shm(
        self,
        mock_shm_config_from_remote_fails,  # noqa: ARG002
        runner,
        tmp_contexts_gems,  # noqa: ARG002
    ):
        result = runner.invoke(users_command_group, ["remove", "-u", "Harry Lime"])

        assert result.exit_code == 1
        assert "Have you deployed the SHM?" in result.stdout


class TestUnregister:
    def test_invalid_shm(
        self,
        mock_shm_config_from_remote_fails,  # noqa: ARG002
        runner,
        tmp_contexts_gems,  # noqa: ARG002
    ):
        result = runner.invoke(
            users_command_group, ["unregister", "-u", "Harry Lime", "my_sre"]
        )

        assert result.exit_code == 1
        assert "Have you deployed the SHM?" in result.stdout

    def test_invalid_sre(
        self,
        mock_pulumi_config_from_remote,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        runner,
        tmp_contexts,  # noqa: ARG002
    ):
        result = runner.invoke(
            users_command_group, ["unregister", "-u", "Harry Lime", "my_sre"]
        )

        assert result.exit_code == 1
        assert "Have you deployed the SRE?" in result.stdout
