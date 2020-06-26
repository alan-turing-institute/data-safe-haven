#!/usr/bin/env python3

import json
import argparse
from pathlib import Path
from urllib.parse import quote as url_quote
import requests


def http_error(msg, response):
    return requests.HTTPError(
        msg + ": Unexpected response: " + response.reason + " ("
        + response.status_code + "), content: " + response.text
    )

def get_gitlab_config(file=None, server=None, value=None):
    """Get GitLab server details and user secrets.
    Parameters
    ----------
    file : str, optional
        Path to configuration file, by default None which resolves to
        .secrets/gitlab-config.json in the user's home directory.
    server : str, optional
        Name of the server to get details for (must match format in config file),
        by default None which returns alls ervers.
    value : str, optional
        Name of the configuration value to return, by default None which returns
        all parameters.
    Returns
    -------
    dict or str
        If server and value are not None, str of the requested value. If only
        server or neither specified, dict of all the relevant values.
    """
    if file is None:
        file = f"{Path.home()}/.secrets/gitlab-config.json"

    with open(file, "r") as f:
        config = json.load(f)

    if server is None and value is None:
        return config
    elif value is None:
        return config[server]
    elif server is None:
        raise ValueError("If value is given, server must also be given.")
    else:
        return config[server][value]


def get_api_config(server, file=None):
    """Construct API URL, headers and other settings.
    Parameters
    ----------
    server : str
        Which server to get secrets for (name present in config file).
    file : str
        Path to configuration file, by default None which resolves to
        .secrets/gitlab-config.json in the user's home directory.
    Returns
    -------
    dict
        Secrets api_url, api_token, ip and headers.
    """
    config = get_gitlab_config(file=file, server=server, value=None)

    ip = config["ip_address"]
    token = config["api_token"]
    api_url = f"http://{ip}/api/v4"
    headers = {"Authorization": "Bearer " + token}

    return {"api_url": api_url, "api_token": token, "ip": ip, "headers": headers}


def get_project_by_id(config, project_id):
    """Get the details of a project from its ID.

    Parameters
    ----------
    project_id : int
        ID of the project on the gitlab server.
    config : dict
        Gitlab details and secrets as returned by get_api_config

    Returns
    -------
    dict
        Project JSON as returned by the gitlab API.
    """
    endpoint = config["api_url"] + f"/projects/{project_id}"
    response = requests.get(endpoint, headers=config["headers"])

    if response.status_code != 200:
        raise http_error("Getting project", response)

    return response.json()


def get_project(config, namespace, repo_name):
    # build url-encoded repo_name
    repo_path_encoded = url_quote(namespace + "/" + repo_name, safe="")

    # Does repo_name exist?
    response = requests.get(
        config["api_url"] + "/projects/" + repo_path_encoded,
        headers=config["headers"],
    )

    if response.status_code == 404:
        return False
    elif response.status_code == 200:
        # The json response body is never empty for a project that
        # exists (and so is "truthy")
        return response.json()
    else:
        # Not using `response.raise_for_status()`, since we also want
        # to raise an exception on unexpected "successful" responses
        # (not 200)
        raise http_error("Getting project", response)


def get_group_ids(gitlab_config):
    groups_url = "{}/groups/".format(gitlab_config["api_url"])
    response = requests.get(groups_url, headers=gitlab_config["headers"])
    if response.status_code != 200:
        raise http_error("Geting group namespace ids", response)

    gitlab_groups = response.json()

    return {group["name"]: group["id"] for group in gitlab_groups}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Get GitLab configuration values.")
    parser.add_argument("--file", help="Location of config file.", default=None)
    parser.add_argument(
        "--server", help="Name of server to get config for.", default=None
    )
    parser.add_argument("--value", help="Configuration value to get.", default=None)
    args = parser.parse_args()

    print(get_gitlab_config(file=args.file, server=args.server, value=args.value))
