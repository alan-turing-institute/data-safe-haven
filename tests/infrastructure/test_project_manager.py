from pulumi.automation import (
    LocalWorkspace,
    ProjectSettings,
    Stack,
    StackSettings,
)
from pytest import raises

from data_safe_haven.config import DSHPulumiProject
from data_safe_haven.exceptions import (
    DataSafeHavenConfigError,
    DataSafeHavenPulumiError,
)
from data_safe_haven.infrastructure import SHMProjectManager, SREProjectManager
from data_safe_haven.infrastructure.project_manager import (
    ProjectManager,
)


class TestSHMProjectManager:
    def test_constructor(
        self,
        context_no_secrets,
        sre_config,
        pulumi_config_no_key,
        pulumi_project,
        mock_azure_cli_confirm,  # noqa: ARG002
        mock_install_plugins,  # noqa: ARG002
    ):
        shm = SHMProjectManager(context_no_secrets, sre_config, pulumi_config_no_key)
        assert isinstance(shm, SHMProjectManager)
        assert isinstance(shm, ProjectManager)
        assert shm.context == context_no_secrets
        assert shm.pulumi_project == pulumi_project

    def test_new_project(
        self,
        context_no_secrets,
        sre_config,
        pulumi_config_empty,
        mock_azure_cli_confirm,  # noqa: ARG002
        mock_install_plugins,  # noqa: ARG002
    ):
        shm = SHMProjectManager(
            context_no_secrets, sre_config, pulumi_config_empty, create_project=True
        )
        assert isinstance(shm, SHMProjectManager)
        assert isinstance(shm, ProjectManager)
        assert shm.context == context_no_secrets
        # Ensure a project was created
        assert isinstance(shm.pulumi_project, DSHPulumiProject)
        assert "acmedeployment" in pulumi_config_empty.project_names
        assert pulumi_config_empty["acmedeployment"].stack_config == {}
        assert pulumi_config_empty.encrypted_key is None

    def test_new_project_fail(
        self,
        context_no_secrets,
        sre_config,
        pulumi_config_empty,
        mock_azure_cli_confirm,  # noqa: ARG002
        mock_install_plugins,  # noqa: ARG002
    ):
        shm = SHMProjectManager(
            context_no_secrets, sre_config, pulumi_config_empty, create_project=False
        )
        with raises(
            DataSafeHavenConfigError,
            match="No SHM/SRE named acmedeployment is defined.",
        ):
            _ = shm.pulumi_project

    def test_project_settings(self, shm_stack_manager):
        project_settings = shm_stack_manager.project_settings
        assert isinstance(project_settings, ProjectSettings)
        assert project_settings.name == "data-safe-haven"
        assert project_settings.runtime == "python"
        assert project_settings.backend is None

    def test_stack_settings(self, shm_stack_manager):
        stack_settings = shm_stack_manager.stack_settings
        assert isinstance(stack_settings, StackSettings)
        assert stack_settings.config == shm_stack_manager.pulumi_project.stack_config
        assert (
            stack_settings.encrypted_key
            == shm_stack_manager.pulumi_config.encrypted_key
        )
        assert (
            stack_settings.secrets_provider
            == shm_stack_manager.context.pulumi_secrets_provider_url
        )

    def test_pulumi_project(self, shm_stack_manager, pulumi_project):
        assert shm_stack_manager.pulumi_project == pulumi_project

    def test_run_pulumi_command(self, shm_stack_manager):
        stdout = shm_stack_manager.run_pulumi_command("stack ls")
        assert "shm-acmedeployment*" in stdout

    def test_run_pulumi_command_command_error(self, shm_stack_manager):
        with raises(
            DataSafeHavenPulumiError,
            match="Failed to run command.",
        ):
            shm_stack_manager.run_pulumi_command("notapulumicommand")

    def test_stack(self, shm_stack_manager):
        stack = shm_stack_manager.stack
        assert isinstance(stack, Stack)

    def test_stack_config(self, shm_stack_manager):
        stack = shm_stack_manager.stack
        assert stack.name == "shm-acmedeployment"
        assert isinstance(stack.workspace, LocalWorkspace)
        workspace = stack.workspace
        assert (
            workspace.secrets_provider
            == shm_stack_manager.context.pulumi_secrets_provider_url
        )
        config = stack.get_all_config()
        assert config["azure-native:location"].value == "uksouth"
        assert config["data-safe-haven:variable"].value == "5"

    def test_update_dsh_pulumi_project(self, shm_stack_manager):
        shm_stack_manager.set_config("new-key", "hello", secret=False)
        config = shm_stack_manager.stack.get_all_config()
        assert "data-safe-haven:new-key" in config
        assert config.get("data-safe-haven:new-key").value == "hello"
        shm_stack_manager.update_dsh_pulumi_project()
        stack_config = shm_stack_manager.pulumi_project.stack_config
        assert "data-safe-haven:new-key" in stack_config
        assert stack_config.get("data-safe-haven:new-key") == "hello"


class TestSREProjectManager:
    def test_constructor(
        self,
        context_no_secrets,
        sre_config,
        pulumi_config_no_key,
        pulumi_project_sandbox,
        mock_azure_cli_confirm,  # noqa: ARG002
        mock_install_plugins,  # noqa: ARG002
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

    def test_new_project(
        self,
        context_no_secrets,
        sre_config,
        pulumi_config_empty,
        mock_azure_cli_confirm,  # noqa: ARG002
        mock_install_plugins,  # noqa: ARG002
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
        mock_azure_cli_confirm,  # noqa: ARG002
        mock_install_plugins,  # noqa: ARG002
    ):
        sre = SREProjectManager(
            context_no_secrets, sre_config, pulumi_config_empty, create_project=False
        )
        with raises(
            DataSafeHavenConfigError,
            match="No SHM/SRE named sandbox is defined.",
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
            match="Failed to run command.",
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
