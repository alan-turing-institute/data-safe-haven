import pytest

from data_safe_haven.exceptions import DataSafeHavenValueError
from data_safe_haven.external import GraphApi


class TestGraphApi:
    def test_from_scopes(self):
        api = GraphApi.from_scopes(
            scopes=["scope1", "scope2"], tenant_id=pytest.guid_tenant
        )
        assert api.credential.tenant_id == pytest.guid_tenant
        assert "scope1" in api.credential.scopes
        assert "scope2" in api.credential.scopes

    def test_from_token(self, graph_api_token):
        api = GraphApi.from_token(graph_api_token)
        assert api.credential.tenant_id == pytest.guid_tenant
        assert "GroupMember.Read.All" in api.credential.scopes
        assert "User.Read.All" in api.credential.scopes

    def test_from_token_invalid(self):
        with pytest.raises(
            DataSafeHavenValueError,
            match="Could not construct GraphApi from provided token.",
        ):
            GraphApi.from_token("not a jwt")

    def test_add_custom_domain(
        self,
        requests_mock,
        mock_graphapicredential_get_token,  # noqa: ARG002
    ):
        domain_name = "example.com"
        requests_mock.get(
            "https://graph.microsoft.com/v1.0/domains",
            json={"value": [{"id": domain_name}, {"id": "example.org"}]},
        )
        requests_mock.get(
            f"https://graph.microsoft.com/v1.0/domains/{domain_name}/verificationDnsRecords",
            json={
                "value": [
                    {"recordType": "Caa", "text": "caa-record-text"},
                    {"recordType": "Txt", "text": "txt-record-text"},
                ]
            },
        )
        api = GraphApi.from_scopes(scopes=[], tenant_id=pytest.guid_tenant)
        result = api.add_custom_domain(domain_name)
        assert result == "txt-record-text"

    def test_token(
        self,
        graph_api_token,
        mock_graphapicredential_get_token,  # noqa: ARG002
    ):
        api = GraphApi.from_token(graph_api_token)
        assert api.token == graph_api_token
