import logging

import azure.functions as func
import requests
from requests.auth import HTTPBasicAuth

from shared_code import (
    get_args, check_args, missing_parameters_repsonse, timeout, gitea_host, api_root,
    migrate_path, repos_path, handle_response
)


def main(req: func.HttpRequest) -> func.HttpResponse:
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
        "Mirror successfully created.",
        status_code=200,
    )
