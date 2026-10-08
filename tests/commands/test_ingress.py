"""CLI coverage for post-ingress storage firewall cleanup."""

from types import SimpleNamespace

from typer.testing import CliRunner

from data_safe_haven.commands.cli import application
from data_safe_haven.exceptions import DataSafeHavenAzureStorageError
from data_safe_haven.functions import alphanumeric, sha256hash, truncate_tokens
from data_safe_haven.infrastructure.programs.sre.data import (
    sensitive_data_storage_account_name,
)


def _cli_mocks(mocker, admin_ip_addresses=None):
    context = SimpleNamespace(subscription_name="SHM Subscription")
    context_manager = mocker.Mock(unsafe=True)
    context_manager.assert_context.return_value = context
    mocker.patch(
        "data_safe_haven.commands.ingress.ContextManager.from_file",
        return_value=context_manager,
    )
    config = SimpleNamespace(
        sre=SimpleNamespace(
            admin_ip_addresses=admin_ip_addresses or ["198.51.100.200"]
        ),
        azure=SimpleNamespace(subscription_id="sre-sub-id"),
    )
    mocker.patch(
        "data_safe_haven.commands.ingress.SREConfig.from_remote_by_name",
        return_value=config,
    )
    mocker.patch(
        "data_safe_haven.commands.ingress.DSHPulumiConfig.from_remote",
        return_value=SimpleNamespace(project_names=["sandbox"]),
    )
    stack = mocker.patch("data_safe_haven.commands.ingress.SREProjectManager")
    stack.return_value.stack_name = "shm-test-sre-sandbox"
    stack.return_value.output.return_value = "sre-rg"
    azure = mocker.patch("data_safe_haven.commands.ingress.AzureSdk")
    azure.return_value.get_subscription_name.return_value = "SRE Subscription"
    azure.return_value.remove_storage_account_ip_rule.return_value = True
    return stack, azure


def test_command_closes_exact_rule_using_deployed_stack_target(mocker):
    stack, azure = _cli_mocks(mocker)
    result = CliRunner().invoke(
        application,
        ["ingress", "close-firewall", "sandbox", "--ip", "203.0.113.10"],
    )
    assert result.exit_code == 0, result.output
    assert "Removed ingress firewall rule 203.0.113.10/32" in result.output
    azure.return_value.remove_storage_account_ip_rule.assert_called_once_with(
        "sre-rg",
        sensitive_data_storage_account_name("shm-test-sre-sandbox"),
        "203.0.113.10/32",
    )
    assert stack.return_value.output.call_args.args == ("sre_resource_group",)


def test_absent_rule_reports_no_change(mocker):
    _, azure = _cli_mocks(mocker)
    azure.return_value.remove_storage_account_ip_rule.return_value = False
    result = CliRunner().invoke(
        application, ["ingress", "close-firewall", "sandbox", "--ip", "203.0.113.10"]
    )
    assert result.exit_code == 0
    assert "already absent" in result.output


def test_bad_ip_is_rejected_before_any_azure_operation(mocker):
    azure = mocker.patch("data_safe_haven.commands.ingress.AzureSdk")
    result = CliRunner().invoke(
        application,
        ["ingress", "close-firewall", "sandbox", "--ip", "not-an-ip"],
    )
    assert result.exit_code != 0
    azure.assert_not_called()
    assert "Expected an IPv4 address or CIDR" in result.output


def test_refuses_to_remove_rule_covering_admin_address(mocker):
    _, azure = _cli_mocks(mocker, admin_ip_addresses=["203.0.113.19"])
    result = CliRunner().invoke(
        application,
        ["ingress", "close-firewall", "sandbox", "--ip", "203.0.113.0/24"],
    )
    assert result.exit_code != 0
    assert "administrator IP" in result.output
    azure.assert_not_called()


def test_azure_failure_reports_error_and_exit_code(mocker):
    _, azure = _cli_mocks(mocker)
    azure.return_value.remove_storage_account_ip_rule.side_effect = (
        DataSafeHavenAzureStorageError("Azure refused network update")
    )
    result = CliRunner().invoke(
        application,
        ["ingress", "close-firewall", "sandbox", "--ip", "203.0.113.10"],
    )
    assert result.exit_code != 0
    assert "Could not close ingress firewall" in result.output


def test_sensitive_storage_name_matches_existing_pulumi_naming_scheme():
    # Before extracting a helper this was computed inline in SREDataComponent.
    stack_name = "shm-test-sre-sandbox"
    expected = alphanumeric(
        f"{''.join(truncate_tokens(stack_name.split('-'), 11))}"
        f"sensitivedata{sha256hash('sre_data')}"
    )[:24]
    assert sensitive_data_storage_account_name(stack_name) == expected
