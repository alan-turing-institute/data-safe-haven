"""Ensure failed teardown leaves Pulumi recovery state and explains next steps."""

from unittest.mock import Mock, call

import pytest

from data_safe_haven.exceptions import DataSafeHavenPulumiError
from data_safe_haven.infrastructure.project_manager import ProjectManager


def fake_manager():
    return Mock()


def test_teardown_success_runs_cleanup_after_destroy():
    manager = fake_manager()
    ProjectManager.teardown(manager)
    assert manager.mock_calls.index(call.destroy()) < manager.mock_calls.index(
        call.cleanup()
    )
    manager.refresh.assert_called_once_with()
    manager.destroy.assert_called_once_with()
    manager.cleanup.assert_called_once_with()
    manager.cancel.assert_not_called()


def test_teardown_failure_does_not_erase_pulumi_state():
    manager = fake_manager()
    failed = DataSafeHavenPulumiError("Azure subnet in use")
    manager.destroy.side_effect = failed

    with pytest.raises(
        DataSafeHavenPulumiError,
        match="Pulumi infrastructure teardown did not complete",
    ) as captured:
        ProjectManager.teardown(manager)

    assert captured.value.__cause__ is failed
    manager.cleanup.assert_not_called()
    message = manager.logger.error.call_args.args[0]
    assert "Some Azure resources may still exist" in message
    assert "rerun the same teardown command" in message
    assert "Do not redeploy" in message


def test_refresh_failure_preserves_stack_and_instructions():
    manager = fake_manager()
    manager.refresh.side_effect = RuntimeError("Azure API unavailable")

    with pytest.raises(DataSafeHavenPulumiError) as captured:
        ProjectManager.teardown(manager)

    assert isinstance(captured.value.__cause__, RuntimeError)
    manager.destroy.assert_not_called()
    manager.cleanup.assert_not_called()
    manager.logger.error.assert_called_once()


def test_cleanup_failure_is_reported_without_another_destroy():
    manager = fake_manager()
    manager.cleanup.side_effect = OSError("cannot remove project metadata")

    with pytest.raises(DataSafeHavenPulumiError):
        ProjectManager.teardown(manager)

    manager.destroy.assert_called_once_with()
    manager.cleanup.assert_called_once_with()
    assert "rerun the same teardown command" in manager.logger.error.call_args.args[0]


def test_force_teardown_cancels_operation_before_refresh():
    manager = fake_manager()
    ProjectManager.teardown(manager, force=True)
    manager.cancel.assert_called_once()
    assert manager.mock_calls.index(call.cancel()) < manager.mock_calls.index(
        call.refresh()
    )
    manager.refresh.assert_called_once_with()
    manager.destroy.assert_called_once_with()
