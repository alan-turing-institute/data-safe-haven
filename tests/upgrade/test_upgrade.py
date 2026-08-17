from unittest import mock

from pytest import CaptureFixture, raises

from data_safe_haven import version
from data_safe_haven.external import AzureSdk
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.upgrade import Upgrade, UpgradeFailedError


class TestUpgrade:
    def test_user_checks_sre_same_version(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        capsys: CaptureFixture[str],
    ) -> None:
        """Check that same-version deployments proceed automatically."""
        with mock.patch.object(AzureSdk, "get_version", return_value="5.7.1"):
            with mock.patch.object(version, "__version__", new="5.7.1"):
                upgrade = Upgrade(sre_project_manager)
                proceed = upgrade.can_proceed()
                assert proceed
                captured = capsys.readouterr()
                assert (
                    "Deployment will therefore trigger an upgrade." not in captured.out
                )
                assert not upgrade.fresh_deployment

    def test_user_checks_sre_newer(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        capsys: CaptureFixture[str],
    ) -> None:
        """Check that if the SRE is newer than DSH the deployment is aborted."""
        with mock.patch.object(AzureSdk, "get_version", return_value="5.7.1"):
            with mock.patch.object(version, "__version__", new="5.7.0"):
                upgrade = Upgrade(sre_project_manager)
                proceed = upgrade.can_proceed()
                assert not proceed
                captured = capsys.readouterr()
                assert (
                    "Deployment will therefore trigger an upgrade." not in captured.out
                )

    def test_user_checks_sre_older_confirm(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        mock_confirm_yes: None,  # noqa: ARG002
        capsys: CaptureFixture[str],
    ) -> None:
        """Check that upgrade to a newer SRE requires confirmation."""
        with mock.patch.object(AzureSdk, "get_version", return_value="5.7.0"):
            with mock.patch.object(version, "__version__", new="5.7.1"):
                upgrade = Upgrade(sre_project_manager)
                proceed = upgrade.can_proceed()
                assert proceed
                captured = capsys.readouterr()
                assert "Deployment will therefore trigger an upgrade." in captured.out
                assert "5.7.0" in captured.out
                assert "5.7.1" in captured.out

    def test_user_checks_sre_older_deny(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        mock_confirm_no: None,  # noqa: ARG002
        capsys: CaptureFixture[str],
    ) -> None:
        """Check that downgrading is not allowed."""
        with mock.patch.object(AzureSdk, "get_version", return_value="5.7.0"):
            with mock.patch.object(version, "__version__", new="5.7.1"):
                upgrade = Upgrade(sre_project_manager)
                proceed = upgrade.can_proceed()
                assert not proceed
                captured = capsys.readouterr()
                assert "Deployment will therefore trigger an upgrade." in captured.out
                assert "5.7.0" in captured.out
                assert "5.7.1" in captured.out

    def test_user_checks_patch_upgrade(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        mock_confirm_no: None,  # noqa: ARG002
        capsys: CaptureFixture[str],
    ) -> None:
        """Check that patch version increments trigger an upgrade."""
        with mock.patch.object(AzureSdk, "get_version", return_value="5.8.0"):
            with mock.patch.object(version, "__version__", new="5.8.1"):
                upgrade = Upgrade(sre_project_manager)
                proceed = upgrade.can_proceed()
                assert not proceed
                captured = capsys.readouterr()
                assert "Deployment will therefore trigger an upgrade." in captured.out
                assert "Gitea" not in captured.out

    def test_user_checks_minor_upgrade(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        mock_confirm_no: None,  # noqa: ARG002
        capsys: CaptureFixture[str],
    ) -> None:
        """Check that minor version increments trigger an upgrade."""
        with mock.patch.object(AzureSdk, "get_version", return_value="5.6.1"):
            with mock.patch.object(version, "__version__", new="5.8.1"):
                upgrade = Upgrade(sre_project_manager)
                proceed = upgrade.can_proceed()
                assert not proceed
                captured = capsys.readouterr()
                assert "Gitea" in captured.out
                assert "Gitea mirror" in captured.out
                assert "Hedgedoc" in captured.out

    def test_user_checks_major_upgrade(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        mock_confirm_no: None,  # noqa: ARG002
        capsys: CaptureFixture[str],
    ) -> None:
        """Check that major version increments trigger an upgrade."""
        with mock.patch.object(AzureSdk, "get_version", return_value="3.9.9"):
            with mock.patch.object(version, "__version__", new="6.7.3"):
                upgrade = Upgrade(sre_project_manager)
                proceed = upgrade.can_proceed()
                assert not proceed
                captured = capsys.readouterr()
                assert "Gitea" in captured.out
                assert "Gitea mirror" in captured.out
                assert "Hedgedoc" in captured.out

    def test_user_checks_sre_fresh(
        self,
        sre_project_manager: SREProjectManager,
    ) -> None:
        """Checks that fresh deployments are correctly recognised."""
        with mock.patch.object(AzureSdk, "get_version", return_value="5.7.1"):
            with mock.patch.object(version, "__version__", new="5.7.1"):
                upgrade = Upgrade(sre_project_manager)
                proceed = upgrade.can_proceed()
                assert proceed
                assert upgrade.fresh_deployment

    def test_prepare_no_changes(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        mock_confirm_yes: None,  # noqa: ARG002
        capsys: CaptureFixture[str],
    ) -> None:
        """Check that an upgrade that requires no preparation also indicates
        that there are no changes to the stack.
        """
        with mock.patch.object(AzureSdk, "get_version", return_value="3.9.9"):
            with mock.patch.object(version, "__version__", new="4.0.0"):
                upgrade = Upgrade(sre_project_manager)
                proceed = upgrade.can_proceed()
                assert proceed
                captured = capsys.readouterr()
                assert "Deployment will therefore trigger an upgrade." in captured.out
                changes = upgrade.prepare()
                assert not changes

    def test_prepare_no_proceed(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        mock_confirm_no: None,  # noqa: ARG002
        capsys: CaptureFixture[str],
    ) -> None:
        """Check that attempting to prepare when the user denied the upgrade
        raises an exception.
        """
        with mock.patch.object(AzureSdk, "get_version", return_value="3.9.9"):
            with mock.patch.object(version, "__version__", new="4.0.0"):
                upgrade = Upgrade(sre_project_manager)
                proceed = upgrade.can_proceed()
                assert not proceed
                captured = capsys.readouterr()
                assert "Deployment will therefore trigger an upgrade." in captured.out
                with raises(UpgradeFailedError):
                    changes = upgrade.prepare()
                    assert not changes

    def test_prepare_fresh(
        self,
        sre_project_manager: SREProjectManager,
        mock_confirm_no: None,  # noqa: ARG002
        capsys: CaptureFixture[str],
    ) -> None:
        """Checks that fresh deployments do not trigger q confirmation and do not
        identify changes to the stack.
        """
        with mock.patch.object(AzureSdk, "get_version", return_value="3.9.9"):
            with mock.patch.object(version, "__version__", new="4.0.0"):
                upgrade = Upgrade(sre_project_manager)
                proceed = upgrade.can_proceed()
                assert proceed
                assert upgrade.fresh_deployment
                captured = capsys.readouterr()
                assert (
                    "Deployment will therefore trigger an upgrade." not in captured.out
                )
                changes = upgrade.prepare()
                assert not changes

    def test_prepare_upgrade_below_5_8_0(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        mock_confirm_yes: None,  # noqa: ARG002
        capsys: CaptureFixture[str],
        mock_azuresdk_resource_manager_client: None,  # noqa: ARG002
    ) -> None:
        """Check that an upgrade that requires no preparation also indicates that
        there are no changes to the stack.
        """
        with mock.patch.object(AzureSdk, "get_version", return_value="5.7.8"):
            with mock.patch.object(version, "__version__", new="5.7.9"):
                upgrade = Upgrade(sre_project_manager)
                proceed = upgrade.can_proceed()
                assert proceed
                captured = capsys.readouterr()
                assert "Deployment will therefore trigger an upgrade." in captured.out
                changes = upgrade.prepare()
                assert not changes

    def test_prepare_upgrade_5_8_0(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        mock_confirm_yes: None,  # noqa: ARG002
        capsys: CaptureFixture[str],
        mock_azuresdk_resource_manager_client: None,  # noqa: ARG002
    ) -> None:
        """Check that an upgrade that requires no preparation also indicates that
        there are no changes to the stack.
        """
        with mock.patch.object(AzureSdk, "get_version", return_value="5.7.9"):
            with mock.patch.object(version, "__version__", new="5.8.0"):
                upgrade = Upgrade(sre_project_manager)
                proceed = upgrade.can_proceed()
                assert proceed
                captured = capsys.readouterr()
                assert "Deployment will therefore trigger an upgrade." in captured.out
                changes = upgrade.prepare()
                assert changes

    def test_prepare_upgrade_above_5_8_0(
        self,
        sre_project_manager: SREProjectManager,
        mock_sre_project_manager_output: None,  # noqa: ARG002
        mock_confirm_yes: None,  # noqa: ARG002
        capsys: CaptureFixture[str],
        mock_azuresdk_resource_manager_client: None,  # noqa: ARG002
    ) -> None:
        """Check that an upgrade that requires no preparation also indicates that
        there are no changes to the stack.
        """
        with mock.patch.object(AzureSdk, "get_version", return_value="5.8.0"):
            with mock.patch.object(version, "__version__", new="5.8.1"):
                upgrade = Upgrade(sre_project_manager)
                proceed = upgrade.can_proceed()
                assert proceed
                captured = capsys.readouterr()
                assert "Deployment will therefore trigger an upgrade." in captured.out
                changes = upgrade.prepare()
                assert not changes
