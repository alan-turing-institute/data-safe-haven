from data_safe_haven.commands.context import context_command_group
from data_safe_haven.context_infrastructure import ContextInfrastructure
from data_safe_haven.exceptions import DataSafeHavenAzureAPIAuthenticationError
from data_safe_haven.external.interface.azure_authenticator import AzureAuthenticator


class TestShow:
    def test_show(self, runner):
        result = runner.invoke(context_command_group, ["show"])
        assert result.exit_code == 0
        assert "Current context: acme_deployment" in result.stdout
        assert "Name: Acme Deployment" in result.stdout

    def test_show_none(self, runner_none):
        result = runner_none.invoke(context_command_group, ["show"])
        assert result.exit_code == 0
        assert "Current context: None" in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(context_command_group, ["show"])
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout


class TestAvailable:
    def test_available(self, runner):
        result = runner.invoke(context_command_group, ["available"])
        assert result.exit_code == 0
        assert "acme_deployment*" in result.stdout
        assert "gems" in result.stdout

    def test_available_none(self, runner_none):
        result = runner_none.invoke(context_command_group, ["available"])
        assert result.exit_code == 0
        assert "acme_deployment" in result.stdout
        assert "gems" in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(context_command_group, ["available"])
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout


class TestSwitch:
    def test_switch(self, runner):
        result = runner.invoke(context_command_group, ["switch", "gems"])
        assert result.exit_code == 0
        assert "Switched context to 'gems'." in result.stdout
        result = runner.invoke(context_command_group, ["available"])
        assert result.exit_code == 0
        assert "gems*" in result.stdout

    def test_invalid_switch(self, runner):
        result = runner.invoke(context_command_group, ["switch", "invalid"])
        assert result.exit_code == 1
        # Unable to check error as this is written outside of any Typer
        # assert "Context 'invalid' is not defined " in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(
            context_command_group, ["switch", "context"]
        )
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout


class TestAdd:
    def test_add(self, runner):
        result = runner.invoke(
            context_command_group,
            [
                "add",
                "example",
                "--name",
                "Example",
                "--admin-group",
                "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
                "--location",
                "uksouth",
                "--subscription-name",
                "Data Safe Haven Example",
            ],
        )
        assert result.exit_code == 0
        result = runner.invoke(context_command_group, ["switch", "example"])
        assert result.exit_code == 0

    def test_add_duplicate(self, runner):
        result = runner.invoke(
            context_command_group,
            [
                "add",
                "acme_deployment",
                "--name",
                "Acme Deployment",
                "--admin-group",
                "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
                "--location",
                "uksouth",
                "--subscription-name",
                "Data Safe Haven Acme",
            ],
        )
        assert result.exit_code == 1
        # Unable to check error as this is written outside of any Typer
        # assert "A context with key 'acme_deployment' is already defined." in result.stdout

    def test_add_invalid_uuid(self, runner):
        result = runner.invoke(
            context_command_group,
            [
                "add",
                "example",
                "--name",
                "Example",
                "--admin-group",
                "not a uuid",
                "--location",
                "uksouth",
                "--subscription-name",
                "Data Safe Haven Example",
            ],
        )
        assert result.exit_code == 2
        # This works because the context_command_group Typer writes this error
        assert "Invalid value for '--admin-group': Expected GUID" in result.stderr

    def test_add_invalid_subscription_name(self, runner):
        result = runner.invoke(
            context_command_group,
            [
                "add",
                "example",
                "--name",
                "Example",
                "--admin-group",
                "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
                "--location",
                "uksouth",
                "--subscription-name",
                "Invalid Subscription Name  ",
            ],
        )
        assert result.exit_code == 2
        # This works because the context_command_group Typer writes this error
        assert "Invalid value for '--subscription-name':" in result.stderr

    def test_add_missing_ags(self, runner):
        result = runner.invoke(
            context_command_group,
            [
                "add",
                "example",
                "--name",
                "Example",
            ],
        )
        assert result.exit_code == 2
        assert "Missing option" in result.stderr

    def test_add_bootstrap(self, tmp_contexts, runner):
        (tmp_contexts / "contexts.yaml").unlink()
        result = runner.invoke(
            context_command_group,
            [
                "add",
                "acme_deployment",
                "--name",
                "Acme Deployment",
                "--admin-group",
                "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
                "--location",
                "uksouth",
                "--subscription-name",
                "Data Safe Haven Acme",
            ],
        )
        assert result.exit_code == 0
        assert (tmp_contexts / "contexts.yaml").exists()
        result = runner.invoke(context_command_group, ["show"])
        assert result.exit_code == 0
        assert "Name: Acme Deployment" in result.stdout
        result = runner.invoke(context_command_group, ["available"])
        assert result.exit_code == 0
        assert "acme_deployment*" in result.stdout
        assert "gems" not in result.stdout


class TestUpdate:
    def test_update(self, runner):
        result = runner.invoke(context_command_group, ["update", "--name", "New Name"])
        assert result.exit_code == 0
        result = runner.invoke(context_command_group, ["show"])
        assert result.exit_code == 0
        assert "Name: New Name" in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(
            context_command_group, ["update", "--name", "New Name"]
        )
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout


class TestRemove:
    def test_remove(self, runner):
        result = runner.invoke(context_command_group, ["remove", "gems"])
        assert result.exit_code == 0
        result = runner.invoke(context_command_group, ["available"])
        assert result.exit_code == 0
        assert "gems" not in result.stdout

    def test_remove_invalid(self, runner):
        result = runner.invoke(context_command_group, ["remove", "invalid"])
        assert result.exit_code == 1
        # Unable to check error as this is written outside of any Typer
        # assert "No context with key 'invalid'." in result.stdout

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(
            context_command_group, ["remove", "gems"]
        )
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout


class TestCreate:
    def test_create(self, runner, monkeypatch):
        def mock_create(self):  # noqa: ARG001
            print("mock create")  # noqa: T201

        monkeypatch.setattr(ContextInfrastructure, "create", mock_create)

        result = runner.invoke(context_command_group, ["create"])
        assert "mock create" in result.stdout
        assert result.exit_code == 0

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(context_command_group, ["create"])
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout

    def test_show_none(self, runner_none):
        result = runner_none.invoke(context_command_group, ["create"])
        assert result.exit_code == 1
        assert "No context selected." in result.stdout

    def test_auth_failure(self, runner, mocker):
        def mock_login(self):  # noqa: ARG001
            raise DataSafeHavenAzureAPIAuthenticationError

        mocker.patch.object(AzureAuthenticator, "login", mock_login)

        result = runner.invoke(context_command_group, ["create"])
        assert result.exit_code == 1
        assert "Failed to authenticate with the Azure API." in result.stdout


class TestTeardown:
    def test_teardown(self, runner, monkeypatch):
        def mock_teardown(self):  # noqa: ARG001
            print("mock teardown")  # noqa: T201

        monkeypatch.setattr(ContextInfrastructure, "teardown", mock_teardown)

        result = runner.invoke(context_command_group, ["teardown"])
        assert "mock teardown" in result.stdout
        assert result.exit_code == 0

    def test_no_context_file(self, runner_no_context_file):
        result = runner_no_context_file.invoke(context_command_group, ["teardown"])
        assert result.exit_code == 1
        assert "No context configuration file." in result.stdout

    def test_show_none(self, runner_none):
        result = runner_none.invoke(context_command_group, ["teardown"])
        assert result.exit_code == 1
        assert "No context selected." in result.stdout

    def test_auth_failure(self, runner, mocker):
        def mock_login(self):  # noqa: ARG001
            raise DataSafeHavenAzureAPIAuthenticationError

        mocker.patch.object(AzureAuthenticator, "login", mock_login)

        result = runner.invoke(context_command_group, ["teardown"])
        assert result.exit_code == 1
        assert "Failed to authenticate with the Azure API." in result.stdout
