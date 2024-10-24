from data_safe_haven.infrastructure.programs.sre.workspaces import (
    SREWorkspacesComponent,
)


class TestTemplateCloudInit:
    def test_template_cloudinit(self):
        cloudinit = SREWorkspacesComponent.template_cloudinit(
            storage_account_desired_state_name="sadesiredstate",
        )

        assert (
            '- ["sadesiredstate.blob.core.windows.net:/sadesiredstate/desiredstate", /var/local/ansible, nfs, "ro,'
            in cloudinit
        )
