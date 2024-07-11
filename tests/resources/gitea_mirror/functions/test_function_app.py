import json

import azure.functions as func
from pytest import fixture

from data_safe_haven.resources.gitea_mirror.functions.function_app import (
    gitea_host,
    api_root,
    migrate_path,
    repos_path,
    str_or_none,
    create_mirror,
    delete_mirror,
)


class TestStrOrNone:
    def test_str_or_none(self):
        assert str_or_none("hello") == "hello"
        assert str_or_none(None) is None


@fixture
def create_mirror_func():
    return create_mirror.build().get_user_function()


@fixture
def delete_mirror_func():
    return delete_mirror.build().get_user_function()


class TestCreateMirror:
    def test_create_mirror(self, create_mirror_func, requests_mock):
        req = func.HttpRequest(
            method="POST",
            body=json.dumps({
                "address": "https://github.com/user/repo",
                "name": "repo",
                "password": "password",
                "username": "username",
            }).encode(),
            url="/api/create-mirror",
        )

        requests_mock.post(
            gitea_host + api_root + migrate_path,
            status_code=201
        )
        requests_mock.patch(
            gitea_host + api_root + repos_path + "/username/repo",
            status_code=200
        )

        response = create_mirror_func(req)
        assert response.status_code == 200
        assert b"Mirror successfully created." in response._HttpResponse__body

    def test_create_mirror_missing_args(self, create_mirror_func, requests_mock):
        req = func.HttpRequest(
            method="POST",
            body=json.dumps({
                "name": "repo",
                "password": "password",
                "username": "username",
            }).encode(),
            url="/api/create-mirror",
        )

        requests_mock.post(
            gitea_host + api_root + migrate_path,
            status_code=201
        )
        requests_mock.patch(
            gitea_host + api_root + repos_path + "/username/repo",
            status_code=200
        )

        response = create_mirror_func(req)
        assert response.status_code == 400
        assert b"Required parameter not provided." in response._HttpResponse__body

    def test_create_mirror_mirror_fail(self, create_mirror_func, requests_mock):
        req = func.HttpRequest(
            method="POST",
            body=json.dumps({
                "address": "https://github.com/user/repo",
                "name": "repo",
                "password": "password",
                "username": "username",
            }).encode(),
            url="/api/create-mirror",
        )

        requests_mock.post(
            gitea_host + api_root + migrate_path,
            status_code=409
        )
        requests_mock.patch(
            gitea_host + api_root + repos_path + "/username/repo",
            status_code=200
        )

        response = create_mirror_func(req)
        assert response.status_code == 400
        assert b"Error creating repository." in response._HttpResponse__body

    def test_create_mirror_configure_fail(self, create_mirror_func, requests_mock):
        req = func.HttpRequest(
            method="POST",
            body=json.dumps({
                "address": "https://github.com/user/repo",
                "name": "repo",
                "password": "password",
                "username": "username",
            }).encode(),
            url="/api/create-mirror",
        )

        requests_mock.post(
            gitea_host + api_root + migrate_path,
            status_code=201
        )
        requests_mock.patch(
            gitea_host + api_root + repos_path + "/username/repo",
            status_code=403
        )

        response = create_mirror_func(req)
        assert response.status_code == 400
        assert b"Error configuring repository." in response._HttpResponse__body


class TestDeleteMirror:
    def test_delete_mirror(self, delete_mirror_func, requests_mock):
        req = func.HttpRequest(
            method="POST",
            body=json.dumps({
                "owner": "admin",
                "name": "repo",
                "password": "password",
                "username": "username",
            }).encode(),
            url="/api/delete-mirror",
        )

        requests_mock.delete(
            gitea_host + api_root + repos_path + "/admin/repo",
            status_code=204,
        )

        response = delete_mirror_func(req)
        assert response.status_code == 200

    def test_delete_mirror_missing_args(self, delete_mirror_func, requests_mock):
        req = func.HttpRequest(
            method="POST",
            body=json.dumps({
                "name": "repo",
                "owner": "admin",
                "password": "password",
            }).encode(),
            url="/api/delete-mirror",
        )

        requests_mock.delete(
            gitea_host + api_root + repos_path + "/admin/repo",
            status_code=204,
        )

        response = delete_mirror_func(req)
        assert response.status_code == 400
        assert b"Required parameter not provided." in response._HttpResponse__body

    def test_delete_mirror_fail(self, delete_mirror_func, requests_mock):
        req = func.HttpRequest(
            method="POST",
            body=json.dumps({
                "name": "repo",
                "owner": "admin",
                "password": "password",
                "username": "admin",
            }).encode(),
            url="/api/delete-mirror",
        )

        requests_mock.delete(
            gitea_host + api_root + repos_path + "/admin/repo",
            status_code=404,
        )

        response = delete_mirror_func(req)
        assert response.status_code == 400
        assert b"Error deleting repository." in response._HttpResponse__body
