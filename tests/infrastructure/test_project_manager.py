from pulumi.automation import (
    LocalWorkspace,
    ProjectSettings,
    Stack,
    StackSettings,
)
from pytest import CaptureFixture, raises

from data_safe_haven.config import DSHPulumiProject
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenPulumiError,
)
from data_safe_haven.infrastructure import SREProjectManager
from data_safe_haven.infrastructure.project_manager import ProjectManager
from data_safe_haven.upgrade import UpgradeAbortedError

ACME_SRE_SUBSCRIPTION = "Data Safe Haven Acme"


class TestSREProjectManager:
    def test_constructor(
        self,
        context_no_secrets,
        sre_config,
        pulumi_config_no_key,
        pulumi_project_sandbox,
    ):
        sre = SREProjectManager(
            context_no_secrets,
            sre_config,
            pulumi_config_no_key,
        )
        assert isinstance(sre, SREProjectManager)
        assert isinstance(sre, ProjectManager)
        assert sre.context == context_no_secrets
        assert sre.pulumi_project == pulumi_project_sandbox

    def test_cleanup(
        self,
        capsys,
        mock_azuresdk_blob_exists,  # noqa: ARG002
        mock_azuresdk_purge_keyvault,  # noqa: ARG002
        mock_azuresdk_remove_blob,  # noqa: ARG002
        sre_project_manager,
    ):
        sre_project_manager.cleanup()
        stdout, _ = capsys.readouterr()
        assert (
            "Removed Pulumi stack backup shm-acmedeployment-sre-sandbox.json.bak."
            in stdout
        )
        assert "Purged Azure Key Vault shmacmedsresandbosecrets." in stdout

    def test_ensure_config(self, sre_project_manager):
        sre_project_manager.ensure_config(
            "azure-native:location", "uksouth", secret=False
        )
        sre_project_manager.ensure_config("data-safe-haven:variable", "8", secret=False)

    def test_ensure_config_exception(self, sre_project_manager):

        with raises(
            DataSafeHavenPulumiError,
            match=r"Unchangeable configuration option 'azure-native:location'.*your configuration: 'ukwest', Pulumi workspace: 'uksouth'",
        ):
            sre_project_manager.ensure_config(
                "azure-native:location", "ukwest", secret=False
            )

    def test_new_project(
        self,
        context_no_secrets,
        sre_config,
        pulumi_config_empty,
    ):
        sre = SREProjectManager(
            context_no_secrets,
            sre_config,
            pulumi_config_empty,
            create_project=True,
        )
        assert isinstance(sre, SREProjectManager)
        assert isinstance(sre, ProjectManager)
        assert sre.context == context_no_secrets
        # Ensure a project was created
        assert isinstance(sre.pulumi_project, DSHPulumiProject)
        assert "sandbox" in pulumi_config_empty.project_names
        assert pulumi_config_empty["sandbox"].stack_config == {}
        assert pulumi_config_empty.encrypted_key is None

    def test_new_project_fail(
        self,
        context_no_secrets,
        sre_config,
        pulumi_config_empty,
    ):
        sre = SREProjectManager(
            context_no_secrets, sre_config, pulumi_config_empty, create_project=False
        )
        with raises(
            DataSafeHavenConfigError,
            match=r"No SRE named sandbox is defined.",
        ):
            _ = sre.pulumi_project

    def test_project_settings(self, sre_project_manager):
        project_settings = sre_project_manager.project_settings
        assert isinstance(project_settings, ProjectSettings)
        assert project_settings.name == "data-safe-haven"
        assert project_settings.runtime == "python"
        assert project_settings.backend is None

    def test_stack_settings(self, sre_project_manager):
        stack_settings = sre_project_manager.stack_settings
        assert isinstance(stack_settings, StackSettings)
        assert stack_settings.config == sre_project_manager.pulumi_project.stack_config
        assert (
            stack_settings.encrypted_key
            == sre_project_manager.pulumi_config.encrypted_key
        )
        assert (
            stack_settings.secrets_provider
            == sre_project_manager.context.pulumi_secrets_provider_url
        )

    def test_pulumi_project(self, sre_project_manager, pulumi_project_sandbox):
        assert sre_project_manager.pulumi_project == pulumi_project_sandbox

    def test_run_pulumi_command(self, sre_project_manager):
        stdout = sre_project_manager.run_pulumi_command("stack ls")
        assert "shm-acmedeployment-sre-sandbox*" in stdout

    def test_run_pulumi_command_command_error(self, sre_project_manager):
        with raises(
            DataSafeHavenPulumiError,
            match=r"Failed to run command.",
        ):
            sre_project_manager.run_pulumi_command("notapulumicommand")

    def test_stack(self, sre_project_manager):
        stack = sre_project_manager.stack
        assert isinstance(stack, Stack)

    def test_stack_config(self, sre_project_manager):
        stack = sre_project_manager.stack
        assert stack.name == "shm-acmedeployment-sre-sandbox"
        assert isinstance(stack.workspace, LocalWorkspace)
        workspace = stack.workspace
        assert (
            workspace.secrets_provider
            == sre_project_manager.context.pulumi_secrets_provider_url
        )
        config = stack.get_all_config()
        assert config["azure-native:location"].value == "uksouth"
        assert config["data-safe-haven:variable"].value == "8"

    def test_update_dsh_pulumi_project(self, sre_project_manager):
        sre_project_manager.set_config("new-key", "hello", secret=False)
        config = sre_project_manager.stack.get_all_config()
        assert "data-safe-haven:new-key" in config
        assert config.get("data-safe-haven:new-key").value == "hello"
        sre_project_manager.update_dsh_pulumi_project()
        stack_config = sre_project_manager.pulumi_project.stack_config
        assert "data-safe-haven:new-key" in stack_config
        assert stack_config.get("data-safe-haven:new-key") == "hello"

    def test_upgrade_path_accept(
        self,
        sre_project_manager: SREProjectManager,
        mock_upgrade_accept: None,  # noqa: ARG002
        capsys: CaptureFixture[str],
    ) -> None:
        """Test that the deployment upgrade path is giving the expected
        outputs when the user accepts the request to perform an upgrade.
        """
        sre_project_manager.upgrade(ACME_SRE_SUBSCRIPTION)
        captured = capsys.readouterr()
        assert "Performing refresh following changes." in captured.out

    def test_upgrade_path_deny(
        self,
        sre_project_manager: SREProjectManager,
        mock_upgrade_deny: None,  # noqa: ARG002
    ) -> None:
        """Test that the deployment upgrade path is giving the expected
        outputs when the user rejects the request to perform an upgrade.
        """
        with raises(
            UpgradeAbortedError,
            match=r"Deployment aborted.",
        ):
            sre_project_manager.upgrade(ACME_SRE_SUBSCRIPTION)
