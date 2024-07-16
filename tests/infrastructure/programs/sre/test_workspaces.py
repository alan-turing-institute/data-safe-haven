from data_safe_haven.infrastructure.programs.sre.workspaces import (
    SREWorkspacesComponent,
)


class TestTemplateCloudInit:
    def test_template_cloudinit(self):
        cloudinit = SREWorkspacesComponent.template_cloudinit(
            container_desired_state_private_key="PRIVATE_KEY",
            container_desired_state_name="container",
            storage_account_data_configuration_name="storageaccount",
            container_desired_state_local_user="user",
        )

        assert "content: |\n      PRIVATE_KEY" in cloudinit
        assert (
            "scp -i /root/.ssh/desired_state_rsa -r container.storageaccount.user@container.blob.core.windows.net:ansible"
            in cloudinit
        )
