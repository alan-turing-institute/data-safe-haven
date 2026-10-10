"""Tests for PostgreSQL diagnostic settings on SRE database servers."""

from unittest.mock import patch

import pulumi

from data_safe_haven.infrastructure.components import (
    PostgresqlDatabaseComponent,
    PostgresqlDatabaseProps,
)
from data_safe_haven.infrastructure.programs.sre.database_servers import (
    SREDatabaseServerProps,
)
from data_safe_haven.types import DatabaseSystem


def _postgres_props(workspace_id: str | None = None) -> PostgresqlDatabaseProps:
    return PostgresqlDatabaseProps(
        database_names=[],
        database_password="secret-for-unit-test",
        database_resource_group_name="resource-group",
        database_server_name="unit-test-db",
        database_subnet_id="subnet-id",
        database_username="testadmin",
        disable_secure_transport=False,
        location="uksouth",
        log_analytics_workspace_id=workspace_id,
    )


@pulumi.runtime.test
def test_postgresql_logs_are_routed_to_sre_log_analytics_workspace() -> None:
    with patch(
        "data_safe_haven.infrastructure.components.composite.postgresql_database."
        "monitor.DiagnosticSetting"
    ) as diagnostic:
        component = PostgresqlDatabaseComponent(
            "postgres_logging_unit", _postgres_props("workspace-resource-id")
        )

    diagnostic.assert_called_once()
    kwargs = diagnostic.call_args.kwargs
    assert kwargs["workspace_id"] == "workspace-resource-id"
    assert kwargs["log_analytics_destination_type"] == "Dedicated"
    assert kwargs["name"] == "postgresql-server-logs"
    logs = kwargs["logs"]
    assert len(logs) == 1
    assert logs[0].category == "PostgreSQLLogs"
    assert logs[0].enabled is True
    assert kwargs["resource_uri"] is component.db_server.id


@pulumi.runtime.test
def test_postgresql_logs_are_optional_for_external_database_callers() -> None:
    with patch(
        "data_safe_haven.infrastructure.components.composite.postgresql_database."
        "monitor.DiagnosticSetting"
    ) as diagnostic:
        PostgresqlDatabaseComponent("postgres_without_logging_unit", _postgres_props())
    diagnostic.assert_not_called()


def test_research_postgres_prop_accepts_workspace_resource_id() -> None:
    props = SREDatabaseServerProps(
        database_password="test",
        database_system=DatabaseSystem.POSTGRESQL,
        location="uksouth",
        resource_group_name="rg-test",
        sre_fqdn="sre.example.test",
        subnet_id="subnet-id",
        log_analytics_workspace_id="my-law-resource-id",
    )
    assert props.log_analytics_workspace_id == "my-law-resource-id"


def test_research_database_prop_remains_backward_compatible() -> None:
    props = SREDatabaseServerProps(
        database_password="test",
        database_system=DatabaseSystem.POSTGRESQL,
        location="uksouth",
        resource_group_name="rg-test",
        sre_fqdn="sre.example.test",
        subnet_id="subnet-id",
    )
    assert props.log_analytics_workspace_id is None
