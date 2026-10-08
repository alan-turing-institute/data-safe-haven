"""Regression coverage for Azure 429 responses during Pulumi resource teardown."""

from unittest.mock import MagicMock, patch

import pytest
from pulumi import automation

from data_safe_haven.exceptions import DataSafeHavenPulumiError
from data_safe_haven.infrastructure.project_manager import (
    PULUMI_DESTROY_PARALLELISM,
    PULUMI_DESTROY_THROTTLE_RETRIES,
    PULUMI_DESTROY_THROTTLE_WAIT_SECONDS,
    ProjectManager,
)


def command_error(message: str) -> automation.CommandError:
    return automation.CommandError(
        automation.CommandResult(stdout="", stderr=message, code=1)
    )


@pytest.fixture
def manager():
    manager = object.__new__(ProjectManager)
    manager._stack = MagicMock()
    manager._stack.destroy.return_value.summary.result = "succeeded"
    manager.logger = MagicMock()
    manager.evaluate = MagicMock()
    manager.log_exception = MagicMock()
    with patch.object(ProjectManager, "pulumi_extra_args", property(lambda _: {})):
        yield manager


def test_destroy_limits_parallel_operations(manager):
    manager.destroy()
    manager._stack.destroy.assert_called_once_with(parallel=PULUMI_DESTROY_PARALLELISM)
    assert PULUMI_DESTROY_PARALLELISM < 16
    manager.evaluate.assert_called_once_with("succeeded")


def test_destroy_retries_azure_throttling_then_succeeds(manager):
    error = command_error('Status=429 Code="ResourceRequestsThrottled"')
    manager._stack.destroy.side_effect = [
        error,
        error,
        manager._stack.destroy.return_value,
    ]
    with patch("data_safe_haven.infrastructure.project_manager.time.sleep") as sleeper:
        manager.destroy()
    assert manager._stack.destroy.call_count == 3
    assert all(
        call.kwargs["parallel"] == PULUMI_DESTROY_PARALLELISM
        for call in manager._stack.destroy.call_args_list
    )
    assert [call.args[0] for call in sleeper.call_args_list] == [
        PULUMI_DESTROY_THROTTLE_WAIT_SECONDS,
        PULUMI_DESTROY_THROTTLE_WAIT_SECONDS * 2,
    ]


def test_rate_limit_retries_are_bounded(manager):
    error = command_error("TooManyRequests HTTP 429")
    manager._stack.destroy.side_effect = error
    with patch("data_safe_haven.infrastructure.project_manager.time.sleep") as sleeper:
        with pytest.raises(DataSafeHavenPulumiError, match="Pulumi destroy failed"):
            manager.destroy()
    assert manager._stack.destroy.call_count == PULUMI_DESTROY_THROTTLE_RETRIES + 1
    assert sleeper.call_count == PULUMI_DESTROY_THROTTLE_RETRIES
    manager.log_exception.assert_called_once_with(error)


def test_unrelated_errors_fail_without_retry(manager):
    error = command_error("InsufficientPermissions")
    manager._stack.destroy.side_effect = error
    with patch("data_safe_haven.infrastructure.project_manager.time.sleep") as sleeper:
        with pytest.raises(DataSafeHavenPulumiError):
            manager.destroy()
    manager._stack.destroy.assert_called_once()
    sleeper.assert_not_called()


def test_existing_nic_dependency_retry_is_preserved(manager):
    error = command_error("NetworkProfileAlreadyInUseWithContainerNics")
    manager._stack.destroy.side_effect = [error, manager._stack.destroy.return_value]
    with patch("data_safe_haven.infrastructure.project_manager.time.sleep") as sleeper:
        manager.destroy()
    manager._stack.destroy.assert_called()
    sleeper.assert_called_once_with(10)
