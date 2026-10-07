"""Smoke tests should only target databases selected for an SRE."""

import subprocess
from pathlib import Path

import pytest
import yaml
from jinja2 import Environment, StrictUndefined

from data_safe_haven.infrastructure.programs.sre.desired_state import (
    SREDesiredStateComponent,
)
from data_safe_haven.resources import resources_path
from data_safe_haven.types import DatabaseSystem

ANSIBLE = resources_path / "workspace" / "ansible"
TEMPLATE = ANSIBLE / "templates/usr/local/smoke_tests/enabled_databases.j2"
SUITE = ANSIBLE / "files/usr/local/smoke_tests/run_all_tests.bats"


@pytest.mark.parametrize(
    "databases,expected",
    [
        ([], ""),
        ([DatabaseSystem.MICROSOFT_SQL_SERVER], "mssql\n"),
        ([DatabaseSystem.POSTGRESQL], "postgresql\n"),
        (
            [DatabaseSystem.MICROSOFT_SQL_SERVER, DatabaseSystem.POSTGRESQL],
            "mssql\npostgresql\n",
        ),
    ],
)
def test_deployed_databases_render_into_inventory(databases, expected):
    # Test the same enum values used for SRE database-server provisioning.
    variables = SREDesiredStateComponent.ansible_vars_file(
        database_systems=[database.value for database in databases],
        use_software_repositories=False,
    )
    rendered = yaml.safe_load(variables)
    assert rendered["database_systems"] == [database.value for database in databases]
    template = Environment(undefined=StrictUndefined, autoescape=True).from_string(
        TEMPLATE.read_text(encoding="utf-8")
    )
    assert template.render(**rendered) == expected


@pytest.mark.parametrize(
    "contents,database,expect_skipped",
    [
        ("", "mssql", True),
        ("", "postgresql", True),
        ("mssql\n", "mssql", False),
        ("mssql\n", "postgresql", True),
        ("postgresql\n", "mssql", True),
        ("postgresql\n", "postgresql", False),
        ("mssql\npostgresql\n", "mssql", False),
        ("mssql\npostgresql\n", "postgresql", False),
    ],
)
def test_database_selector_uses_inventory(tmp_path, contents, database, expect_skipped):
    manifest = tmp_path / "enabled_databases"
    manifest.write_text(contents, encoding="utf-8")
    _check_selector(manifest, database, expect_skipped=expect_skipped)


@pytest.mark.parametrize("database", ["mssql", "postgresql"])
def test_legacy_workspace_without_inventory_keeps_existing_checks(tmp_path, database):
    # Without a manifest, do not silently disable previously enabled checks.
    _check_selector(tmp_path / "not-created", database, expect_skipped=False)


def _check_selector(manifest: Path, database: str, *, expect_skipped: bool) -> None:
    # Evaluate exactly the production shell function. Stub Bats 'skip' only;
    # a real database connection and package install are not required.
    functions = SUITE.read_text(encoding="utf-8").split("# Mounted drives", maxsplit=1)[
        0
    ]
    script = (
        functions
        + "\nskip() { printf '%s' \"$1\"; exit 42; }\n"
        + f'check_db_deployed "{database}"\n'
    )
    result = subprocess.run(
        ["/bin/bash", "-c", script],
        env={"SMOKE_TEST_DATABASES_FILE": str(manifest), "PATH": "/usr/bin:/bin"},
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == (42 if expect_skipped else 0)
    if expect_skipped:
        assert "not deployed" in result.stdout


@pytest.mark.parametrize(
    "database,language,label",
    [
        ("mssql", "Python", "MS SQL"),
        ("mssql", "R", "MS SQL"),
        ("postgresql", "Python", "Postgres"),
        ("postgresql", "R", "Postgres"),
    ],
)
def test_skip_precedes_credentials_and_dependency_install(database, language, label):
    script = SUITE.read_text(encoding="utf-8")
    block = script.split(f'@test "{label} database ({language})" {{', maxsplit=1)[
        1
    ].split("\n}", maxsplit=1)[0]
    assert f'check_db_deployed "{database}"' in block
    assert block.index("check_db_deployed") < block.index("check_db_credentials")
    assert block.index("check_db_deployed") < block.index(
        "initialise_" if language == "Python" else "initialise_r"
    )
