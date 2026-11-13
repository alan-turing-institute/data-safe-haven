"""Version-aware Pulumi refresh must run the program for provider changes."""

from unittest.mock import call

import pytest
from packaging.version import Version

from data_safe_haven.infrastructure.project_manager import ProjectManager


def fake_manager(mocker):
    manager = mocker.Mock()
    manager._options = {
        "sre-subscription-name": ("test-sre-subscription", False, False)
    }
    return manager


@pytest.mark.parametrize(
    ("current", "deployed", "fresh", "explicit", "expected"),
    [
        ("5.8.0", "5.6.0", False, False, True),
        ("5.8.0", "5.8.0", False, False, False),
        ("5.8.0", "5.6.0", False, True, True),
        ("5.8.0", "5.8.0", False, True, True),
        ("5.8.0", "0.0.0", True, False, False),
    ],
)
def test_refresh_mode_selected_before_refresh(
    mocker, current, deployed, fresh, explicit, expected
):
    manager = fake_manager(mocker)
    upgrade = mocker.Mock(
        dsh_version=Version(current),
        sre_version=Version(deployed),
        fresh_deployment=fresh,
    )
    upgrade.can_proceed.return_value = True
    mocker.patch(
        "data_safe_haven.infrastructure.project_manager.Upgrade",
        return_value=upgrade,
    )

    ProjectManager.deploy(manager, run_program=explicit)

    upgrade.can_proceed.assert_called_once_with()
    manager.refresh.assert_called_once_with(expected)
    manager.upgrade.assert_called_once_with(
        "test-sre-subscription",
        run_program=expected,
        validated_upgrade=upgrade,
    )
    assert manager.mock_calls.index(call.refresh(expected)) < (
        manager.mock_calls.index(
            call.upgrade(
                "test-sre-subscription",
                run_program=expected,
                validated_upgrade=upgrade,
            )
        )
    )
    manager.update.assert_called_once_with()


def test_downgrade_or_rejected_upgrade_never_refreshes(mocker):
    manager = fake_manager(mocker)
    upgrade = mocker.Mock(
        dsh_version=Version("5.7.0"),
        sre_version=Version("5.8.0"),
        fresh_deployment=False,
    )
    upgrade.can_proceed.return_value = False
    mocker.patch(
        "data_safe_haven.infrastructure.project_manager.Upgrade",
        return_value=upgrade,
    )

    with pytest.raises(Exception, match="Pulumi deployment failed"):
        ProjectManager.deploy(manager)

    manager.refresh.assert_not_called()
    manager.upgrade.assert_not_called()
    manager.update.assert_not_called()


def test_prechecked_upgrade_does_not_prompt_twice(mocker):
    manager = fake_manager(mocker)
    upgrade = mocker.Mock()
    upgrade.prepare.return_value = True

    ProjectManager.upgrade(
        manager,
        "test-sre-subscription",
        run_program=True,
        validated_upgrade=upgrade,
    )

    upgrade.can_proceed.assert_not_called()
    upgrade.prepare.assert_called_once_with()
    manager.refresh.assert_called_once_with(True)  # noqa: FBT003


def test_explicit_run_program_on_new_install(mocker):
    manager = fake_manager(mocker)
    upgrade = mocker.Mock(fresh_deployment=True)
    upgrade.can_proceed.return_value = True
    mocker.patch(
        "data_safe_haven.infrastructure.project_manager.Upgrade",
        return_value=upgrade,
    )

    ProjectManager.deploy(manager, run_program=True)
    manager.refresh.assert_called_once_with(True)  # noqa: FBT003
