from datetime import UTC, datetime, timedelta

from pytest import fixture, mark

from data_safe_haven.commands import application
from data_safe_haven.exceptions import DataSafeHavenAzureStorageError
from data_safe_haven.external import AzureSdk
from data_safe_haven.infrastructure import SREProjectManager

COMMAND = ["create-sas", "sandbox", "--container", "ingress"]


def utc_offset(**kwargs) -> str:
    return (datetime.now(UTC) + timedelta(**kwargs)).strftime("%Y-%m-%dT%H:%M:%S")


@fixture
def stack_outputs():
    return {
        "data": {"storage_account_data_private_sensitive_name": "sensitivedata"},
        "sre_resource_group": "resource-group",
    }


@fixture
def mock_sre_project_manager_outputs(mocker, stack_outputs):
    mocker.patch.object(
        SREProjectManager, "output", side_effect=lambda name: stack_outputs[name]
    )


@fixture
def mock_azuresdk_sas(mocker):
    mocker.patch.object(
        AzureSdk, "get_subscription_name", return_value="SRE subscription"
    )
    return (
        mocker.patch.object(AzureSdk, "ensure_storage_account_ip_rule"),
        mocker.patch.object(
            AzureSdk,
            "generate_container_sas_url",
            return_value="https://sensitivedata.blob.core.windows.net/ingress?sas",
        ),
    )


@fixture
def deployed_sre(
    mock_azuresdk_get_credential,
    mock_azuresdk_get_subscription,
    mock_ip_1_2_3_4,
    mock_pulumi_config_no_key_from_remote,
    mock_sre_config_from_remote,
    mock_sre_project_manager_outputs,
):
    pass


class TestCreateSas:
    def test_create_sas(
        self,
        runner,
        deployed_sre,  # noqa: ARG002
        mock_azuresdk_sas,
    ):
        mock_ensure_ip_rule, mock_generate_sas = mock_azuresdk_sas
        start = utc_offset(hours=1)
        result = runner.invoke(
            application,
            [
                *COMMAND,
                "--ip",
                "5.6.7.8",
                "--start",
                start,
                "--end",
                utc_offset(days=1),
            ],
        )

        assert result.exit_code == 0
        assert (
            "https://sensitivedata.blob.core.windows.net/ingress?sas" in result.stdout
        )
        mock_ensure_ip_rule.assert_called_once_with(
            "5.6.7.8", "resource-group", "sensitivedata"
        )
        _, kwargs = mock_generate_sas.call_args
        assert mock_generate_sas.call_args.args == ("ingress", "sensitivedata")
        assert kwargs["ip_address"] == "5.6.7.8"
        assert kwargs["start"] == datetime.fromisoformat(start).replace(tzinfo=UTC)
        assert kwargs["permissions"].write
        assert kwargs["permissions"].list
        assert not kwargs["permissions"].read

    @mark.parametrize(
        "window,message",
        [
            (
                ["--start", utc_offset(hours=2), "--end", utc_offset(hours=1)],
                "The end time must be after the start time.",
            ),
            (
                ["--start", utc_offset(days=-2), "--end", utc_offset(days=-1)],
                "The end time must be in the future.",
            ),
            (
                ["--end", utc_offset(days=8)],
                "The end time must be at most 7 days from now.",
            ),
        ],
    )
    def test_invalid_window(self, runner, window, message):
        result = runner.invoke(
            application,
            [*COMMAND, "--ip", "5.6.7.8", *window],
        )

        assert result.exit_code == 2
        assert message in result.stderr

    def test_invalid_ip(self, runner):
        result = runner.invoke(
            application,
            [*COMMAND, "--ip", "not-an-ip", "--end", utc_offset(days=1)],
        )

        assert result.exit_code == 2
        assert "Expected valid IPv4 address" in result.stderr

    def test_invalid_container(self, runner):
        result = runner.invoke(
            application,
            [
                "create-sas",
                "sandbox",
                "--container",
                "some-container",
                "--ip",
                "5.6.7.8",
                "--end",
                utc_offset(days=1),
            ],
        )

        assert result.exit_code == 2
        assert "'some-container' is not one of 'ingress'" in result.stderr

    def test_azure_error(
        self,
        runner,
        deployed_sre,  # noqa: ARG002
        mock_azuresdk_sas,
    ):
        mock_ensure_ip_rule, _ = mock_azuresdk_sas
        mock_ensure_ip_rule.side_effect = DataSafeHavenAzureStorageError("mock error")
        result = runner.invoke(
            application,
            [*COMMAND, "--ip", "5.6.7.8", "--end", utc_offset(days=1)],
        )

        assert result.exit_code == 1
        assert (
            "Could not create a SAS token for container 'ingress' of SRE 'sandbox'"
            in result.stdout
        )
