from data_safe_haven.commands.context import context_command_group

from pytest import fixture
from typer.testing import CliRunner

context_settings = """\
    selected: acme_deployment
    contexts:
        acme_deployment:
            name: Acme Deployment
            admin_group_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
            location: uksouth
            subscription_name: Data Safe Haven (Acme)
        gems:
            name: Gems
            admin_group_id: d5c5c439-1115-4cb6-ab50-b8e547b6c8dd
            location: uksouth
            subscription_name: Data Safe Haven (Gems)"""


@fixture
def tmp_contexts(tmp_path):
    config_file_path = tmp_path / "contexts.yaml"
    with open(config_file_path, "w") as f:
        f.write(context_settings)
    return tmp_path


@fixture
def runner(tmp_contexts):
    runner = CliRunner(
        env={
            "DSH_CONFIG_DIRECTORY": str(tmp_contexts),
            "COLUMNS": "500"  # Set large number of columns to avoid rich wrapping text
        },
        mix_stderr=False,
    )
    return runner


class TestShow:
    def test_show(self, runner):
        result = runner.invoke(context_command_group, ["show"])
        assert result.exit_code == 0
        assert "Current context: acme_deployment" in result.stdout
        assert "Name: Acme Deployment" in result.stdout


class TestAvailable:
    def test_available(self, runner):
        result = runner.invoke(context_command_group, ["available"])
        assert result.exit_code == 0
        assert "acme_deployment*" in result.stdout
        assert "gems" in result.stdout


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
                "--subscription",
                "Data Safe Haven (Example)",
            ]
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
                "--subscription",
                "Data Safe Haven (Acme)",
            ]
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
                "--subscription",
                "Data Safe Haven (Example)",
            ]
        )
        assert result.exit_code == 2
        # This works because the context_command_group Typer writes this error
        assert "Invalid value for '--admin-group': Expected GUID" in result.stderr

    def test_add_missing_ags(self, runner):
        result = runner.invoke(
            context_command_group,
            [
                "add",
                "example",
                "--name",
                "Example",
            ]
        )
        assert result.exit_code == 2
        assert "Missing option" in result.stderr


class TestUpdate:
    def test_update(self, runner):
        result = runner.invoke(context_command_group, ["update", "--name", "New Name"])
        assert result.exit_code == 0
        result = runner.invoke(context_command_group, ["show"])
        assert result.exit_code == 0
        assert "Name: New Name" in result.stdout


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
