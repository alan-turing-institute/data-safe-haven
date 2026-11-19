"""SRE database SKU options must be optional, validated and propagated."""

import pytest
from pydantic import ValidationError

from data_safe_haven.config import SREConfig
from data_safe_haven.config.config_sections import (
    ConfigSubsectionDatabaseSkus,
    ConfigSubsectionMssqlSku,
    ConfigSubsectionPostgresqlSku,
)
from data_safe_haven.infrastructure.components.composite.microsoft_sql_database import (
    MicrosoftSQLDatabaseProps,
)
from data_safe_haven.infrastructure.components.composite.postgresql_database import (
    PostgresqlDatabaseProps,
)
from data_safe_haven.infrastructure.programs.sre.database_servers import (
    SREDatabaseServerProps,
)
from data_safe_haven.types import DatabaseSystem


def test_existing_sre_configs_without_database_sku_fields_are_compatible(sre_config):
    original = sre_config.model_dump(mode="json")
    original["sre"].pop("database_skus", None)
    loaded = SREConfig.model_validate(original)
    assert loaded.sre.database_skus.model_dump() == {
        "postgresql": {"name": "Standard_B2s", "tier": "Burstable"},
        "mssql": {"name": "GP_S_Gen5", "family": "Gen5", "capacity": 1},
    }


def test_configurable_skus_roundtrip_through_pydantic(sre_config):
    source = sre_config.model_dump(mode="json")
    source["sre"]["database_skus"] = {
        "postgresql": {"name": "Standard_D2s_v3", "tier": "GeneralPurpose"},
        "mssql": {"name": "GP_Gen5", "family": "Gen5", "capacity": 2},
    }
    updated = SREConfig.model_validate(source)
    assert updated.sre.database_skus.postgresql.name == "Standard_D2s_v3"
    assert updated.sre.database_skus.postgresql.tier == "GeneralPurpose"
    assert updated.sre.database_skus.mssql.name == "GP_Gen5"
    assert updated.sre.database_skus.mssql.capacity == 2
    assert (
        updated.model_dump(mode="json")["sre"]["database_skus"]
        == source["sre"]["database_skus"]
    )


@pytest.mark.parametrize("name", ["", "B2s", "standard_b2s"])
def test_invalid_postgres_sku_names_rejected(name):
    with pytest.raises(ValidationError, match="PostgreSQL SKU"):
        ConfigSubsectionPostgresqlSku(name=name)


@pytest.mark.parametrize("tier", ["free", "Premium", "General Purpose"])
def test_invalid_postgres_tiers_rejected(tier):
    with pytest.raises(ValidationError, match="tier"):
        ConfigSubsectionPostgresqlSku(tier=tier)


@pytest.mark.parametrize("capacity", [0, -1])
def test_invalid_mssql_capacity_rejected(capacity):
    with pytest.raises(ValidationError, match="capacity"):
        ConfigSubsectionMssqlSku(capacity=capacity)


def test_independent_optional_partial_engine_config():
    skus = ConfigSubsectionDatabaseSkus.model_validate(
        {"postgresql": {"name": "Standard_E2s_v3", "tier": "MemoryOptimized"}}
    )
    assert skus.postgresql.name == "Standard_E2s_v3"
    assert skus.mssql.name == "GP_S_Gen5"


def test_sre_database_server_props_preserve_supplied_config():
    skus = ConfigSubsectionDatabaseSkus(
        postgresql=ConfigSubsectionPostgresqlSku(
            name="Standard_D2s_v3", tier="GeneralPurpose"
        ),
        mssql=ConfigSubsectionMssqlSku(name="GP_Gen5", family="Gen5", capacity=2),
    )
    props = SREDatabaseServerProps(
        database_password="dummy-password",
        database_system=DatabaseSystem.POSTGRESQL,
        location="uksouth",
        resource_group_name="rg",
        sre_fqdn="sre.example.org",
        subnet_id="subnet",
        database_skus=skus,
    )
    assert props.database_skus is skus
    assert (
        SREDatabaseServerProps(
            database_password="dummy-password",
            database_system=DatabaseSystem.POSTGRESQL,
            location="uksouth",
            resource_group_name="rg",
            sre_fqdn="sre.example.org",
            subnet_id="subnet",
        ).database_skus.postgresql.name
        == "Standard_B2s"
    )


def test_postgresql_resource_props_use_custom_sku():
    props = PostgresqlDatabaseProps(
        database_names=[],
        database_password="password",
        database_resource_group_name="rg",
        database_server_name="db",
        database_subnet_id="subnet",
        database_username="databaseadmin",
        disable_secure_transport=False,
        location="uksouth",
        sku_name="Standard_D2s_v3",
        sku_tier="GeneralPurpose",
    )
    assert (props.sku_name, props.sku_tier) == (
        "Standard_D2s_v3",
        "GeneralPurpose",
    )


def test_mssql_resource_props_use_custom_sku():
    props = MicrosoftSQLDatabaseProps(
        database_names=[],
        database_password="password",
        database_resource_group_name="rg",
        database_server_name="db",
        database_subnet_id="subnet",
        database_username="databaseadmin",
        location="uksouth",
        sku_name="GP_Gen5",
        sku_family="Gen5",
        sku_capacity=2,
    )
    assert (props.sku_name, props.sku_family, props.sku_capacity) == (
        "GP_Gen5",
        "Gen5",
        2,
    )
