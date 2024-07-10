import logging

import azure.functions as func
import requests
from requests.auth import HTTPBasicAuth

app = func.FunctionApp()


@app.route(route="create-mirror", auth_level=func.AuthLevel.ANONYMOUS)
def create_mirror(req: func.HttpRequest) -> func.HttpResponse:  #
    logging.info("Request received.")

    try:
        req_body = req.get_json()
    except ValueError:
        pass
    else:
        address = req_body.get("address")
        name = req_body.get("name")
        password = req_body.get("password")
        username = req_body.get("username")
    logging.info(
        f"parameters: address={address}, name={name}, password={password}, username={username}"
    )

    if None in [address, name, password, username]:
        msg = "Required parameter not provided."
        logging.critical(msg)
        return func.HttpResponse(
            msg,
            status_code=400,
        )

    # gitea_host = "http://gitea_mirror.local"
    gitea_host = "http://localhost:3000"
    api_root = "/api/v1"
    migrate_path = "/repos/migrate"
    repos_path = "/repos"
    extra_data = {
        "description": f"Read-only mirror of {address}",
        "mirror": True,
        "mirror_interval": "10m",
    }
    timeout = 60

    auth = HTTPBasicAuth(
        username=username,
        password=password,
    )

    logging.info("Sending request to create mirror.")

    response = requests.post(
        auth=auth,
        data={
            "clone_addr": address,
            "repo_name": name,
        }
        | extra_data,
        timeout=timeout,
        url=gitea_host + api_root + migrate_path,
    )

    logging.info(f"Response status code: {response.status_code}.")
    logging.debug(f"Response contents: {response.json()}.")
    if response.status_code != 201:  # noqa: PLR2004
        return func.HttpResponse(
            "Error creating repository.",
            status_code=400,
        )

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
        url=gitea_host + api_root + repos_path + f"/{username}/{name}",
    )

    logging.info(f"Response status code: {response.status_code}.")
    logging.debug(f"Response contents: {response.json()}.")
    if response.status_code != requests.codes.ok:
        return func.HttpResponse(
            "Error configuring repository.",
            status_code=400,
        )

    return func.HttpResponse(
        "Mirror successfully created",
        status_code=200,
    )
