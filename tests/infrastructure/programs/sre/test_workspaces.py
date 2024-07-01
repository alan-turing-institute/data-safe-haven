import pytest

from data_safe_haven.infrastructure.programs.sre.workspaces import (
    SREWorkspacesComponent,
)


class TestCloudInitIndent:
    @pytest.mark.parametrize(
        "string,indent,expected",
        [
            ("hello\nworld\n!!!", 2, "hello\n  world\n  !!!"),
            ("hello\nworld\n!!!", 0, "hello\nworld\n!!!"),
        ],
    )
    def test_cloud_init_indent(self, string, indent, expected):
        assert SREWorkspacesComponent.cloud_init_indent(string, indent) == expected


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
