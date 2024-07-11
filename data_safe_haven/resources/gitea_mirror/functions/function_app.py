import logging
from typing import Any

import azure.functions as func
import requests
from requests.auth import HTTPBasicAuth

app = func.FunctionApp()

# Global parameters
# gitea_host = "http://gitea_mirror.local"
gitea_host = "http://localhost:3000"
api_root = "/api/v1"
migrate_path = "/repos/migrate"
repos_path = "/repos"
timeout = 60


def get_args(args: list[str], req: func.HttpRequest) -> dict[str, str | None]:
    try:
        req_body = req.get_json()
    except ValueError:
        return {}

    args_dict = {arg: str_or_none(req_body.get(arg)) for arg in args}
    logging.info(f"Parameters: {args}.")
    return args_dict


def str_or_none(item: Any) -> str | None:
    return str(item) if item is not None else None


def check_args(args: dict[str, str | None]) -> dict[str, str] | None:
    if None in args.values():
        return None
    else:
        return {key: str(value) for key, value in args.items()}


def missing_parameters_repsonse() -> func.HttpResponse:
    msg = "Required parameter not provided."
    logging.critical(msg)
    return func.HttpResponse(
        msg,
        status_code=400,
    )


def handle_response(
    response: requests.Response, valid_codes: list[int], error_message: str
) -> func.HttpResponse | None:
    logging.info(f"Response status code: {response.status_code}.")
    logging.debug(f"Response contents: {response.text}.")
    if response.status_code not in valid_codes:
        return func.HttpResponse(
            error_message,
            status_code=400,
        )
    else:
        return None


@app.route(route="create-mirror", auth_level=func.AuthLevel.ANONYMOUS)
def create_mirror(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Request received.")

    raw_args = get_args(
        [
            "address",
            "name",
            "password",
            "username",
        ],
        req,
    )
    args = check_args(raw_args)
    if not args:
        return missing_parameters_repsonse()

    extra_data = {
        "description": f"Read-only mirror of {args['address']}",
        "mirror": True,
        "mirror_interval": "10m",
    }

    auth = HTTPBasicAuth(
        username=args["username"],
        password=args["password"],
    )

    logging.info("Sending request to create mirror.")

    response = requests.post(
        auth=auth,
        data={
            "clone_addr": args["address"],
            "repo_name": args["name"],
        }
        | extra_data,
        timeout=timeout,
        url=gitea_host + api_root + migrate_path,
    )

    if r := handle_response(response, [201], "Error creating repository."):
        return r

    # Some arguments of the migrate endpoint seem to be ignored or overwritten.
    # We set repository settings here.
    logging.info("Sending request to configure mirror repo.")

    response = requests.patch(
        auth=auth,
        data={
            "has_actions": False,
            "has_issues": False,
            "has_packages": False,
            "has_projects": False,
            "has_pull_requests": False,
            "has_releases": False,
            "has_wiki": False,
        },
        timeout=timeout,
        url=gitea_host + api_root + repos_path + f"/{args['username']}/{args['name']}",
    )

    if r := handle_response(response, [200], "Error configuring repository."):
        return r

    return func.HttpResponse(
        "Mirror successfully created",
        status_code=200,
    )


@app.route(route="delete-mirror", auth_level=func.AuthLevel.ANONYMOUS)
def delete_mirror(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Request received.")

    raw_args = get_args(
        [
            "name",
            "owner",
            "password",
            "username",
        ],
        req,
    )
    args = check_args(raw_args)
    if not args:
        return missing_parameters_repsonse()

    auth = HTTPBasicAuth(
        username=args["username"],
        password=args["password"],
    )

    logging.info("Sending request to delete repository.")
    response = requests.delete(
        auth=auth,
        timeout=timeout,
        url=gitea_host + api_root + repos_path + f"/{args['owner']}/{args['name']}",
    )

    if r := handle_response(response, [204], "Error deleting repository."):
        return r

    return func.HttpResponse(
        "Repository successfully deleted.",
        status_code=200,
    )
