"""Built-in SRE saved searches use supported logging tables and stable IDs."""

from uuid import UUID

from data_safe_haven.infrastructure.programs.sre.log_queries import (
    DEFAULT_SAVED_QUERIES,
    saved_query_id,
)


def test_three_distinct_queries_cover_security_and_data_transfers() -> None:
    assert set(DEFAULT_SAVED_QUERIES) == {
        "failed_workspace_logins",
        "ingress_uploads",
        "egress_downloads",
    }
    titles = [title for title, _ in DEFAULT_SAVED_QUERIES.values()]
    assert len(titles) == len(set(titles))

    auth = DEFAULT_SAVED_QUERIES["failed_workspace_logins"][1]
    assert auth.startswith("Syslog\n")
    assert 'Facility in~ ("auth", "authpriv")' in auth
    assert "SyslogMessage" in auth
    assert "TimeGenerated >= ago(" in auth

    for key, container, operation in (
        ("ingress_uploads", "ingress", "PutBlob"),
        ("egress_downloads", "egress", "GetBlob"),
    ):
        query = DEFAULT_SAVED_QUERIES[key][1]
        assert query.startswith("StorageBlobLogs\n")
        assert f'Uri contains "/{container}/"' in query
        assert operation in query
        assert "StatusCode" in query
        assert "CallerIpAddress" in query
        assert "TimeGenerated >= ago(" in query


def test_azure_saved_search_ids_are_valid_and_stable_per_sre() -> None:
    identifiers = {
        key: saved_query_id("shm-alpha-sre-project", key)
        for key in DEFAULT_SAVED_QUERIES
    }
    assert len(set(identifiers.values())) == len(identifiers)
    for key, identifier in identifiers.items():
        assert str(UUID(identifier)) == identifier
        assert UUID(identifier).version == 5
        assert identifier == saved_query_id("shm-alpha-sre-project", key)
        assert identifier != saved_query_id("shm-beta-sre-project", key)
