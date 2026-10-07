from data_safe_haven.administration.users.entra_users import EntraUsers
from data_safe_haven.commands.users import users_command_group
from data_safe_haven.config import SHMConfig
from data_safe_haven.external import GraphApi


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

    def test_missing_csv_country_code_is_reported_to_cli(
        self, mocker, runner, tmp_path, shm_config
    ):
        csv_file = tmp_path / "users.csv"
        csv_file.write_text(
            "GivenName,Surname,Phone,Email,CountryCode\n"
            "Ada,Lovelace,+441234567890,ada@example.org,\n"
        )
        mocker.patch.object(SHMConfig, "from_remote", return_value=shm_config)
        mocker.patch.object(GraphApi, "from_scopes", return_value=mocker.Mock())
        add_to_entra = mocker.patch.object(EntraUsers, "add")

        result = runner.invoke(users_command_group, ["add", str(csv_file)])

        assert result.exit_code == 1
        assert "line 2 is missing values for: CountryCode" in result.stdout
        add_to_entra.assert_not_called()


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

    def test_mismatched_domain(
        self,
        mock_graphapi_get_credential,  # noqa: ARG002
        mock_pulumi_config_no_key_from_remote,  # noqa: ARG002
        mock_shm_config_from_remote,  # noqa: ARG002
        mock_sre_config_from_remote,  # noqa: ARG002
        mock_entra_user_list,  # noqa: ARG002
        runner,
        tmp_contexts,  # noqa: ARG002
    ):
        result = runner.invoke(
            users_command_group, ["register", "-u", "harry.lime", "sandbox"]
        )

        assert result.exit_code == 0
        assert (
            "principal domain name must match the domain of the SRE to be registered"
            in result.stdout
        )

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
