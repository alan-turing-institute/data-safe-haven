from typing import Any

import pulumi
import pulumi.runtime
from pytest import fixture

from data_safe_haven.config.config_sections import ConfigSubsectionGiteaMirror
from data_safe_haven.infrastructure.programs.sre.gitea_server import (
    SREGiteaServerComponent,
)


class TestSREGiteaServerComponent:
    @pulumi.runtime.test  # type: ignore
    def test_creation(self, gitea_server_component: SREGiteaServerComponent) -> None:
        """Basic test to ensure the component is being created correctly"""
        assert isinstance(gitea_server_component, SREGiteaServerComponent)

    @pulumi.runtime.test  # type: ignore
    def test_min_interval_default(
        self, gitea_server_component: SREGiteaServerComponent
    ) -> Any:
        """Check that GITEA__mirror__MIN_INTERVAL defaults to 10m"""

        def check(containers: list[Any]) -> None:
            gitea = next(c for c in containers if c["name"] == "gitea")
            min_interval = next(
                env["value"]
                for env in gitea["environment_variables"]
                if env["name"] == "GITEA__mirror__MIN_INTERVAL"
            )
            assert min_interval == "10m"

        return pulumi.Output.from_input(
            gitea_server_component.container_group.containers
        ).apply(check)


class TestSREGiteaServerComponentCustomInterval:
    @fixture
    def repository_data(self) -> ConfigSubsectionGiteaMirror:
        return ConfigSubsectionGiteaMirror(repositories=[], mirror_interval_minutes=1)

    @pulumi.runtime.test  # type: ignore
    def test_min_interval_override(
        self, gitea_server_component: SREGiteaServerComponent
    ) -> Any:
        """Check that GITEA__mirror__MIN_INTERVAL follows a configured override"""

        def check(containers: list[Any]) -> None:
            gitea = next(c for c in containers if c["name"] == "gitea")
            min_interval = next(
                env["value"]
                for env in gitea["environment_variables"]
                if env["name"] == "GITEA__mirror__MIN_INTERVAL"
            )
            assert min_interval == "1m"

        return pulumi.Output.from_input(
            gitea_server_component.container_group.containers
        ).apply(check)
