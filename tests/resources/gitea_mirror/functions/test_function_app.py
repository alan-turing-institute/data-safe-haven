import json

import azure.functions as func

from data_safe_haven.resources.gitea_mirror.functions.function_app import (
    str_or_none,
    delete_mirror,
)


class TestStrOrNone:
    def test_str_or_none(self):
        assert str_or_none("hello") == "hello"
        assert str_or_none(None) is None


class TestDeleteMirror:
    def test_delete_mirror(self, requests_mock):
        req = func.HttpRequest(
            method="POST",
            body=json.dumps({
                "name": "repo",
                "owner": "admin",
                "password": "password",
                "username": "username",
            }).encode(),
            url="/api/delete-mirror",
        )

        function = delete_mirror.build().get_user_function()

        requests_mock.delete(
            "http://localhost:3000/api/v1/repos/admin/repo",
            status_code=204,
        )

        response = function(req)
        assert response.status_code == 200
