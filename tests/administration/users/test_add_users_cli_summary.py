"""User-add CLI only prints a username table after all accounts were created."""

from types import SimpleNamespace

from typer.testing import CliRunner

from data_safe_haven.administration.users.research_user import ResearchUser
from data_safe_haven.commands.users import users_command_group
from data_safe_haven.exceptions import DataSafeHavenUserHandlingError


def _setup(mocker):
    context_manager = mocker.Mock(unsafe=True)
    context_manager.assert_context.return_value = mocker.Mock()
    mocker.patch(
        "data_safe_haven.commands.users.ContextManager.from_file",
        return_value=context_manager,
    )
    mocker.patch(
        "data_safe_haven.commands.users.SHMConfig.from_remote",
        return_value=SimpleNamespace(
            shm=SimpleNamespace(entra_tenant_id="tenant-123", fqdn="test.example")
        ),
    )
    mocker.patch("data_safe_haven.commands.users.GraphApi.from_scopes")
    return mocker.patch("data_safe_haven.commands.users.UserHandler.add")


def test_add_users_prints_full_generated_logins_at_end(mocker):
    add = _setup(mocker)
    add.return_value = [
        ResearchUser(given_name="Özge", surname="Müller", domain="test.example"),
        ResearchUser(given_name="Jane", surname="Doe", domain="test.example"),
    ]
    result = CliRunner().invoke(users_command_group, ["add", "users.csv"])
    assert result.exit_code == 0, result.output
    assert "Name" in result.output and "Username" in result.output
    assert "ozge.muller@test.example" in result.output
    assert "jane.doe@test.example" in result.output
    add.assert_called_once()


def test_add_users_does_not_print_success_table_on_failed_batch(mocker):
    add = _setup(mocker)
    add.side_effect = DataSafeHavenUserHandlingError("Cannot create a user")
    result = CliRunner().invoke(users_command_group, ["add", "users.csv"])
    assert result.exit_code == 1
    assert "Could not add users to Data Safe Haven" in result.output
    assert "Username" not in result.output
