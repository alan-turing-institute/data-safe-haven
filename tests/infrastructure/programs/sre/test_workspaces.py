from data_safe_haven.infrastructure.programs.sre.workspaces import (
    SREWorkspacesComponent,
)


class TestTemplateCloudInit:
    def test_template_cloudinit(self):
        cloudinit = SREWorkspacesComponent.template_cloudinit(
            storage_account_data_desired_state_name="storageaccount",
        )

        assert (
            '- ["storageaccount.blob.core.windows.net:/storageaccount/desiredstate", /var/local/ansible, nfs, "ro,'
            in cloudinit
        )
