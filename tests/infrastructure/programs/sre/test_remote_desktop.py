from typing import Any

import pulumi

from data_safe_haven.infrastructure.programs.sre.remote_desktop import (
    SRERemoteDesktopComponent,
)
from tests.infrastructure.programs.resource_assertions import assert_equal


def guacamole_user_sync_container(containers: list[Any]) -> dict[str, Any]:
    return next(
        container
        for container in containers
        if container["name"] == "guacamole-user-sync"
    )


def group_permissions(value: str) -> dict[str, set[str]]:
    return {
        group_name: set(permissions.split(","))
        for group_name, permissions in (entry.split("=") for entry in value.split(";"))
    }


class TestSRERemoteDesktopProps:
    @pulumi.runtime.test
    def test_guacamole_user_sync_image_version(
        self, remote_desktop_component: SRERemoteDesktopComponent
    ) -> Any:
        def check(containers: list[Any]) -> None:
            container = guacamole_user_sync_container(containers)
            assert_equal(
                "ghcr.io/alan-turing-institute/guacamole-user-sync:v0.8.1",
                container["image"],
            )

        return remote_desktop_component.container_group.containers.apply(check)

    @pulumi.runtime.test
    def test_guacamole_group_permissions_env_var_present(
        self, remote_desktop_component: SRERemoteDesktopComponent
    ) -> Any:
        def check(containers: list[Any]) -> None:
            container = guacamole_user_sync_container(containers)
            env_var = next(
                env
                for env in container["environment_variables"]
                if env["name"] == "GUACAMOLE_GROUP_PERMISSIONS"
            )
            assert env_var["value"]
            assert env_var.get("secure_value") is None

        return remote_desktop_component.container_group.containers.apply(check)

    @pulumi.runtime.test
    def test_guacamole_group_permissions_admin_group(
        self,
        admin_group_name: str,
        remote_desktop_component: SRERemoteDesktopComponent,
    ) -> Any:
        def check(containers: list[Any]) -> None:
            container = guacamole_user_sync_container(containers)
            value = next(
                env["value"]
                for env in container["environment_variables"]
                if env["name"] == "GUACAMOLE_GROUP_PERMISSIONS"
            )
            assert_equal(
                {"READ", "UPDATE", "DELETE", "ADMINISTER"},
                group_permissions(value)[admin_group_name],
            )

        return remote_desktop_component.container_group.containers.apply(check)

    @pulumi.runtime.test
    def test_guacamole_group_permissions_user_group(
        self,
        remote_desktop_component: SRERemoteDesktopComponent,
        user_group_name: str,
    ) -> Any:
        def check(containers: list[Any]) -> None:
            container = guacamole_user_sync_container(containers)
            value = next(
                env["value"]
                for env in container["environment_variables"]
                if env["name"] == "GUACAMOLE_GROUP_PERMISSIONS"
            )
            assert_equal({"READ"}, group_permissions(value)[user_group_name])

        return remote_desktop_component.container_group.containers.apply(check)

    @pulumi.runtime.test
    def test_guacamole_group_permissions_no_extra_groups(
        self,
        admin_group_name: str,
        remote_desktop_component: SRERemoteDesktopComponent,
        user_group_name: str,
    ) -> Any:
        def check(containers: list[Any]) -> None:
            container = guacamole_user_sync_container(containers)
            value = next(
                env["value"]
                for env in container["environment_variables"]
                if env["name"] == "GUACAMOLE_GROUP_PERMISSIONS"
            )
            assert_equal(
                {admin_group_name, user_group_name},
                set(group_permissions(value).keys()),
            )

        return remote_desktop_component.container_group.containers.apply(check)
