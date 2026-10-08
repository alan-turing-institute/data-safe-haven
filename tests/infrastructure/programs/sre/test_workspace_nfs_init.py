"""Ensure cloud-init mounts NFS only after the NFS helper is installed."""

import subprocess
from pathlib import Path

import pytest
import yaml

from data_safe_haven.infrastructure.programs.sre.workspaces import SREWorkspacesComponent


@pytest.mark.parametrize("data_disk_support", [False, True])
def test_nfs_is_deferred_until_after_packages(tmp_path: Path, data_disk_support: bool) -> None:
    cloudinit = SREWorkspacesComponent.template_cloudinit(
        apt_proxy_server_hostname="apt.internal.test",
        data_disk_support=data_disk_support,
        storage_account_desired_state_name="sadesiredstate",
        storage_account_data_private_sensitive_name="sasensitive",
        storage_account_data_private_user_name="sauserdata",
    )
    config = yaml.safe_load(cloudinit)

    # The cloud-init mounts module runs before the packages module. NFS must
    # not appear here, or mount -a fails without /sbin/mount.nfs.
    assert config["mounts"]
    assert all(
        len(mount) < 3 or mount[2] != "nfs" for mount in config["mounts"]
    )
    assert "nfs-common" in config["packages"]
    assert config["mounts"][0] == ["ephemeral0", "/mnt/scratch"]
    assert (len(config["mounts"]) == 2) is data_disk_support

    files = {entry["path"]: entry for entry in config["write_files"]}
    script = files["/usr/local/sbin/dsh-register-nfs-mounts"]["content"]
    commands = config["runcmd"]
    register_idx = commands.index("/usr/local/sbin/dsh-register-nfs-mounts")
    mount_idx = commands.index("mount -fav")
    assert register_idx < mount_idx
    assert commands.index(
        "mkdir -p /var/local/ansible /mnt/input /mnt/output /mnt/shared /home"
    ) < register_idx

    # Exercise the exact registration shell code against an isolated fstab,
    # not the developer's machine. Reruns must not duplicate mount entries.
    fstab = tmp_path / "fstab"
    fstab.write_text("proc /proc proc defaults 0 0\n", encoding="utf-8")
    script = script.replace("/etc/fstab", str(fstab))
    subprocess.run(["bash", "-n", "-c", script], check=True)  # noqa: S603
    subprocess.run(["bash", "-c", script], check=True)  # noqa: S603
    first = fstab.read_text(encoding="utf-8")
    subprocess.run(["bash", "-c", script], check=True)  # noqa: S603
    assert fstab.read_text(encoding="utf-8") == first

    nfs = [line for line in first.splitlines() if " nfs " in line]
    assert len(nfs) == len(
        {"/var/local/ansible", "/mnt/input", "/mnt/output", "/mnt/shared", "/home"}
    )
    for path in (
        "/var/local/ansible",
        "/mnt/input",
        "/mnt/output",
        "/mnt/shared",
        "/home",
    ):
        assert sum(f" {path} nfs " in line for line in nfs) == 1
    assert all("{{" not in line for line in nfs)
