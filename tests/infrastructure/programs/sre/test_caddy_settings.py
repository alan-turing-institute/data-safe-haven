"""Caddy provisioning is consistent across SRE services."""

import ast

import pytest

from data_safe_haven.infrastructure.programs.sre import (
    caddy_settings,
    gitea_server,
    hedgedoc_server,
    remote_desktop,
    software_repositories,
)


@pytest.mark.parametrize(
    "service,read_only",
    [
        (gitea_server, True),
        (hedgedoc_server, True),
        (remote_desktop, False),
        (software_repositories, True),
    ],
)
def test_caddy_resource_settings_remain_shared(service, read_only):
    tree = ast.parse(open(service.__file__, encoding="utf-8").read())
    caddy_containers = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr != "ContainerArgs":
            continue
        kwargs = {item.arg: item.value for item in node.keywords}
        if ast.unparse(kwargs.get("name")) == "CADDY_NAME[:63]":
            caddy_containers.append(kwargs)

    assert len(caddy_containers) == 1
    fields = caddy_containers[0]
    assert ast.unparse(fields["image"]) == "CADDY_IMAGE"
    assert ast.unparse(fields["resources"]).count("CADDY_CPU") == 1
    assert ast.unparse(fields["resources"]).count("CADDY_MEMORY_GB") == 1
    mounts = fields["volume_mounts"]
    assert ast.unparse(mounts).count("CADDY_CONFIG_MOUNT_PATH") == 1
    assert ast.unparse(mounts).count("CADDY_CONFIG_VOLUME_NAME") == 1
    assert f"read_only={read_only}" in ast.unparse(mounts)


def test_shared_caddy_values_match_existing_provisioning():
    assert caddy_settings.CADDY_IMAGE == "caddy:2.11.4"
    assert caddy_settings.CADDY_NAME == "caddy"
    assert caddy_settings.CADDY_CPU == 0.5
    assert caddy_settings.CADDY_MEMORY_GB == 0.5
    assert caddy_settings.CADDY_CONFIG_MOUNT_PATH == "/etc/caddy"
    assert caddy_settings.CADDY_CONFIG_VOLUME_NAME == "caddy-etc-caddy"
