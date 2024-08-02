import logging

import azure.functions as func
import requests
from requests.auth import HTTPBasicAuth
from shared_code import (
    api_root,
    check_args,
    get_args,
    gitea_host,
    handle_response,
    missing_parameters_repsonse,
    repos_path,
    timeout,
)


def main(req: func.HttpRequest) -> func.HttpResponse:
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
