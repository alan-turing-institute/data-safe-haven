from typing import Any

import pulumi
import pulumi.runtime
from pytest import fixture

from data_safe_haven.config.config_sections import ConfigSubsectionGiteaMirror
from data_safe_haven.infrastructure.programs.sre.gitea_mirror_manager import (
    SREGiteaMirrorManagerComponent,
)


class TestSREGiteaMirrorManagerComponent:
    @pulumi.runtime.test  # type: ignore
    def test_creation(
        self, gitea_mirror_manager_component: SREGiteaMirrorManagerComponent
    ) -> None:
        """Basic test to ensure the component is being created correctly"""
        assert isinstance(
            gitea_mirror_manager_component, SREGiteaMirrorManagerComponent
        )

    @pulumi.runtime.test  # type: ignore
    def test_mirrormanager_image_tag(
        self, gitea_mirror_manager_component: SREGiteaMirrorManagerComponent
    ) -> Any:
        """Check that the mirrormanager container uses the v0.0.2 image"""

        def check(containers: list[Any]) -> None:
            mirrormanager = next(c for c in containers if c["name"] == "mirrormanager")
            assert mirrormanager["image"] == (
                "ghcr.io/alan-turing-institute/gitea-mirror-manager:v0.0.2"
            )

        return pulumi.Output.from_input(
            gitea_mirror_manager_component.container_group.containers
        ).apply(check)

    @pulumi.runtime.test  # type: ignore
    def test_mirror_interval_default(
        self, gitea_mirror_manager_component: SREGiteaMirrorManagerComponent
    ) -> Any:
        """Check that the mirror interval defaults to 10 minutes, and that Gitea's
        own cron floor (MIN_INTERVAL) and scan cadence (SCHEDULE) stay fixed"""

        def check(containers: list[Any]) -> None:
            mirrormanager = next(c for c in containers if c["name"] == "mirrormanager")
            interval = next(
                env["value"]
                for env in mirrormanager["environment_variables"]
                if env["name"] == "MIRROR_INTERVAL_MINUTES"
            )
            assert interval == "10"

            gitea = next(c for c in containers if c["name"] == "gitea")
            min_interval = next(
                env["value"]
                for env in gitea["environment_variables"]
                if env["name"] == "GITEA__mirror__MIN_INTERVAL"
            )
            assert min_interval == "1m"

            schedule = next(
                env["value"]
                for env in gitea["environment_variables"]
                if env["name"] == "GITEA__cron_0x2E_update_mirrors__SCHEDULE"
            )
            assert schedule == "@every 1m"

        return pulumi.Output.from_input(
            gitea_mirror_manager_component.container_group.containers
        ).apply(check)

    @pulumi.runtime.test  # type: ignore
    def test_admin_password_stored(
        self,
        gitea_mirror_manager_component: SREGiteaMirrorManagerComponent,
        gitea_admin_password: str,
    ) -> Any:
        def check(containers: list[Any]) -> None:
            gitea = next(c for c in containers if c["name"] == "gitea")
            admin_password = next(
                env["secure_value"]
                for env in gitea["environment_variables"]
                if env["name"] == "ADMIN_SERVER_PASSWORD"
            )
            assert admin_password == gitea_admin_password

        return pulumi.Output.from_input(
            gitea_mirror_manager_component.container_group.containers
        ).apply(check)

    @pulumi.runtime.test  # type: ignore
    def test_mirror_password_stored(
        self,
        gitea_mirror_manager_component: SREGiteaMirrorManagerComponent,
        gitea_user_password: str,
    ) -> Any:
        def check(containers: list[Any]) -> None:
            for container_name in ("mirrormanager", "gitea"):
                container = next(c for c in containers if c["name"] == container_name)
                mirror_password = next(
                    env["secure_value"]
                    for env in container["environment_variables"]
                    if env["name"] == "MIRROR_SERVER_PASSWORD"
                )
                assert mirror_password == gitea_user_password

        return pulumi.Output.from_input(
            gitea_mirror_manager_component.container_group.containers
        ).apply(check)


class TestSREGiteaMirrorManagerComponentCustomInterval:
    @fixture
    def repository_data(self) -> ConfigSubsectionGiteaMirror:
        return ConfigSubsectionGiteaMirror(repositories=[], mirror_interval_minutes=5)

    @pulumi.runtime.test  # type: ignore
    def test_mirror_interval_override(
        self, gitea_mirror_manager_component: SREGiteaMirrorManagerComponent
    ) -> Any:
        """Check that a configured mirror interval reaches mirrormanager, while
        Gitea's own cron floor (MIN_INTERVAL) and scan cadence (SCHEDULE) stay
        fixed at 1 minute regardless"""

        def check(containers: list[Any]) -> None:
            mirrormanager = next(c for c in containers if c["name"] == "mirrormanager")
            interval = next(
                env["value"]
                for env in mirrormanager["environment_variables"]
                if env["name"] == "MIRROR_INTERVAL_MINUTES"
            )
            assert interval == "5"

            gitea = next(c for c in containers if c["name"] == "gitea")
            min_interval = next(
                env["value"]
                for env in gitea["environment_variables"]
                if env["name"] == "GITEA__mirror__MIN_INTERVAL"
            )
            assert min_interval == "1m"

            schedule = next(
                env["value"]
                for env in gitea["environment_variables"]
                if env["name"] == "GITEA__cron_0x2E_update_mirrors__SCHEDULE"
            )
            assert schedule == "@every 1m"

        return pulumi.Output.from_input(
            gitea_mirror_manager_component.container_group.containers
        ).apply(check)
