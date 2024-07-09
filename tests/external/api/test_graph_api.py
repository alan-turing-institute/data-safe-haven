import pytest

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
