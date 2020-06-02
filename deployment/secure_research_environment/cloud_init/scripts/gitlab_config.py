#!/usr/bin/env python3

import json
import argparse
from pathlib import Path


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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Get GitLab configuration values.")
    parser.add_argument("--file", help="Location of config file.", default=None)
    parser.add_argument(
        "--server", help="Name of server to get config for.", default=None
    )
    parser.add_argument("--value", help="Configuration value to get.", default=None)
    args = parser.parse_args()

    print(get_gitlab_config(file=args.file, server=args.server, value=args.value))
