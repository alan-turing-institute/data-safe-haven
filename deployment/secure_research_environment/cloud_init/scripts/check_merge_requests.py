#!/usr/bin/env python3

"""
Check merge requests on gitlab external, approve them where appropriate,
and push the approved repos to gitlab internal.

1) Get open merge requests in the approval group on gitlab external.
2) Check whether any of them meet the approval conditions. By default: status
is can be merged, not flagged as work in progress, no unresolved discussions,
at least two upvotes, and no downvotes.
3) Accept approved merge requests (merged unapproved repo into approval repo).
4) Push whole approval repo to gitlab internal, creating the repo if it doesn't
already exist.

This script creates two log files in the same directory that it is run from:
* check_merge_requests.log : A verbose log of the steps performed in each run
and any errors encountered.
* accepted_merge_requests.log : A list of merge requests that have been accepted
in CSV format with columns merged time, source project, source branch, source
commit, target project, target branch and target commit.
"""

import requests
import subprocess
from urllib.parse import quote as url_quote
from pathlib import Path
import logging
from logging.handlers import RotatingFileHandler

# Setup logging to console and file. File uses RotatingFileHandler to create
# logs over a rolling window, 10 files each max 5 MB in size.
logger = logging.getLogger("merge_requests_logger")
logger.setLevel(logging.INFO)
formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
f_handler = RotatingFileHandler(
    "check_merge_requests.log", maxBytes=5 * 1024 * 1024, backupCount=10
)
f_handler.setFormatter(formatter)
c_handler = logging.StreamHandler()
c_handler.setFormatter(formatter)
logger.addHandler(f_handler)
logger.addHandler(c_handler)


def internal_project_exists(repo_name, config):
    """Determine whether a repo exist in the ingress namespace on
    GITLAB-INTERNAL.

    Parameters
    ----------
    repo_name : str
        The name of a repo (not a URL) to search for in the ingress namespace
        on GITLAB-INTERNAL.
    config : dict
        GITLAB-INTERNAL details and secrets as returned by get_gitlab_config

    Returns
    -------
    tuple
        (exists, url) tuple where exists: boolean - does repo_name exist on
        GITLAB-INTERNAL?, and url: str - the ssh url to the repo (when 'exists'
        is true)

    Raises
    ------
    requests.HTTPError
        If API request returns an unexpected code (not 404 or 200)
    """

    # build url-encoded repo_name
    repo_path_encoded = url_quote("ingress/" + repo_name, safe="")

    # Does repo_name exist on GITLAB-INTERNAL?
    response = requests.get(
        config["api_url"] + "projects/" + repo_path_encoded, headers=config["headers"]
    )

    if response.status_code == 404:
        return (False, "")
    elif response.status_code == 200:
        return (True, response.json()["ssh_url_to_repo"])
    else:
        # Not using `response.raise_for_status()`, since we also want
        # to raise an exception on unexpected "successful" responses
        # (not 200)
        raise requests.HTTPError(
            "Unexpected response: " + response.reason + ", content: " + response.text
        )


def internal_update_repo(git_url, repo_name, config):
    """Takes a git URL, `git_url`, which should be the URL to the
    "APPROVED" repo on GITLAB-EXTERNAL, clones it and pushes all branches to
    the repo `repo_name` owned by 'ingress' on GITLAB-INTERNAL, creating it
    there first if it doesn't exist.

    Parameters
    ----------
    git_url : str
        URL to the "APPROVED" repo on GITLAB-EXTERNAL
    repo_name : str
        Name of repo to create on GITLAB-INTERNAL.
    config : dict
        GITLAB-INTERNAL details and secrets as returned by get_gitlab_config
    """

    # clone the repo from git_url (on GITLAB-EXTERNAL), removing any of
    # the same name first (simpler than checking if it exists, has the
    # same remote and pulling)
    subprocess.run(["rm", "-rf", repo_name], check=True)
    subprocess.run(["git", "clone", git_url, repo_name], check=True)

    project_exists, gl_internal_repo_url = internal_project_exists(repo_name, config)

    # create the project if it doesn't exist
    if not project_exists:
        print("Creating: " + repo_name)
        response = requests.post(
            config["api_url"] + "projects",
            headers=config["headers"],
            data={"name": repo_name, "visibility": "public"},
        )
        response.raise_for_status()
        assert response.json()["path_with_namespace"] == "ingress/" + repo_name

        gl_internal_repo_url = response.json()["ssh_url_to_repo"]

    # Set the remote
    subprocess.run(
        ["git", "remote", "add", "gitlab-internal", gl_internal_repo_url],
        cwd=repo_name,
        check=True,
    )

    # Force push current contents of all branches
    subprocess.run(
        ["git", "push", "--force", "--all", "gitlab-internal"],
        cwd=repo_name,
        check=True,
    )


def get_request(endpoint, headers, params=None):
    """Wrapper around requests.get that returns a JSON if request was successful
    or raises a HTTPError otherwise.

    Parameters
    ----------
    endpoint : str
        URL of API endpoint to call
    headers : dict
        Request headers
    params : dict, optional
        Request parameters

    Returns
    -------
    dict
        JSON of request result

    Raises
    ------
    requests.HTTPError
        If not r.ok, raise HTTPError with details of failure
    """
    r = requests.get(endpoint, headers=headers, params=params)
    if r.ok:
        return r.json()
    else:
        raise requests.HTTPError(
            f"Request failed: URL {endpoint}, CODE {r.status_code}, CONTENT {r.content}"
        )


def put_request(endpoint, headers, params=None):
    """Wrapper around requests.put that returns a JSON if request was successful
    or raises a HTTPError otherwise.

    Parameters
    ----------
    endpoint : str
        URL of API endpoint to call
    headers : dict
        Request headers
    params : dict, optional
        Request parameters

    Returns
    -------
    dict
        JSON of request result

    Raises
    ------
    requests.HTTPError
        If not r.ok, raise HTTPError with details of failure
    """
    r = requests.put(endpoint, headers=headers, params=params)
    if r.ok:
        return r.json()
    else:
        raise requests.HTTPError(
            f"Request failed: URL {endpoint}, CODE {r.status_code}, CONTENT {r.content}"
        )


def get_gitlab_config(server="external"):
    """Get gitlab server details and user account secrets

    Parameters
    ----------
    server : str, optional
        Which server to get secrets for either "internal" or, by default "external"

    Returns
    -------
    dict
        Secrets api_url, api_token, ip and headers.

    Raises
    ------
    ValueError
        If server is not a supported value
    """
    home = str(Path.home())

    if server == "external":
        with open(f"{home}/.secrets/gitlab-external-ip-address", "r") as f:
            ip = f.readlines()[0].strip()
        with open(f"{home}/.secrets/gitlab-external-api-token", "r") as f:
            token = f.readlines()[0].strip()
    elif server == "internal":
        with open(f"{home}/.secrets/gitlab-internal-ip-address", "r") as f:
            ip = f.readlines()[0].strip()
        with open(f"{home}/.secrets/gitlab-internal-api-token", "r") as f:
            token = f.readlines()[0].strip()
    else:
        raise ValueError("Server must be external or internal")

    api_url = f"http://{ip}/api/v4/"
    headers = {"Authorization": "Bearer " + token}

    return {"api_url": api_url, "api_token": token, "ip": ip, "headers": headers}


def get_group_id(group_name, config):
    """Get the ID of a group on a gitlab server.

    Parameters
    ----------
    group_name : str
        Group name to find.
    config : dict
        Gitlab details and secrets as returned by get_gitlab_config

    Returns
    -------
    int
        Group ID for group_name

    Raises
    ------
    ValueError
        If group_name not found in the groups returned from the gitlab server.
    """
    endpoint = config["api_url"] + "groups"
    response = get_request(endpoint, headers=config["headers"])
    for group in response:
        if group["name"] == group_name:
            return group["id"]
    raise ValueError(f"{group_name} not found in groups.")


def get_project(project_id, config):
    """Get the details of a project from its ID.

    Parameters
    ----------
    project_id : int
        ID of the project on the gitlab server.
    config : dict
        Gitlab details and secrets as returned by get_gitlab_config

    Returns
    -------
    dict
        Project JSON as returned by the gitlab API.
    """
    endpoint = config["api_url"] + f"projects/{project_id}"
    project = get_request(endpoint, headers=config["headers"])
    return project


def get_merge_requests_for_approval(config):
    """Get the details of all open merge requests into the approval group on
    a gitlab server.

    Parameters
    ----------
    config : dict
        Gitlab details and secrets as returned by get_gitlab_config

    Returns
    -------
    list
        List of merge requests JSONs as returned by the gitlab API.
    """
    group = get_group_id("approval", config)
    endpoint = config["api_url"] + f"/groups/{group}/merge_requests"
    response = get_request(
        endpoint, headers=config["headers"], params={"state": "opened"}
    )
    return response


def count_unresolved_mr_discussions(mr, config):
    """Count the number of unresolved discussions a merge request has. Requires
    calling the discussions API endpoint for the merge request to determine
    each comment's resolved status.

    Parameters
    ----------
    mr : dict
        A merge request JSON as returned by the gitlab API
    config : dict
        Gitlab details and secrets as returned by get_gitlab_config

    Returns
    -------
    int
        Number of unresolved discussions.
    """
    if mr["user_notes_count"] == 0:
        return 0
    project_id = mr["project_id"]
    mr_iid = mr["iid"]
    endpoint = (
        config["api_url"] + f"projects/{project_id}/merge_requests/{mr_iid}/discussions"
    )
    discussions = get_request(endpoint, headers=config["headers"])
    if len(discussions) == 0:
        return 0
    else:
        n_unresolved = 0
        for d in discussions:
            for n in d["notes"]:
                if n["resolvable"] is True and n["resolved"] is False:
                    n_unresolved += 1
        return n_unresolved


def accept_merge_request(mr, config):
    """Accept a merge request

    Parameters
    ----------
    mr : dict
        For the merge request to approve: The merge request JSON as returned by
        the gitlab API.
    config : dict
        Gitlab details and secrets as returned by get_gitlab_config

    Returns
    -------
    dict
        JSON response from gitlab API representing the status of the accepted
        merge request.
    """
    project_id = mr["project_id"]
    mr_iid = mr["iid"]
    endpoint = (
        config["api_url"] + f"projects/{project_id}/merge_requests/{mr_iid}/merge"
    )
    return put_request(endpoint, headers=config["headers"])


def check_merge_requests():
    """Main function to check merge requests in the approval group on gitlab external,
    approve them where appropriate, and then push the approved repos to gitlab
    internal.
    """
    logger.info(f"STARTING RUN")

    try:
        config_external = get_gitlab_config(server="external")
        config_internal = get_gitlab_config(server="internal")
    except Exception as e:
        logger.critical(f"Failed to load gitlab secrets: {e}")
        return

    logger.info("Getting open merge requests for approval")
    try:
        merge_requests = get_merge_requests_for_approval(config_external)
    except Exception as e:
        logger.critical(f"Failed to get merge requests: {e}")
        return
    logger.info(f"Found {len(merge_requests)} open merge requests")

    for i, mr in enumerate(merge_requests):
        logger.info("-" * 20)
        logger.info(f"Merge request {i+1} out of {len(merge_requests)}")
        try:
            # Extract merge request details
            source_project = get_project(mr["source_project_id"], config_external)
            logger.info(f"Source Project: {source_project['name_with_namespace']}")
            logger.info(f"Source Branch: {mr['source_branch']}")
            target_project = get_project(mr["project_id"], config_external)
            logger.info(f"Target Project: {target_project['name_with_namespace']}")
            logger.info(f"Target Branch: {mr['target_branch']}")
            logger.info(f"Commit SHA: {mr['sha']}")
            logger.info(f"Created At: {mr['created_at']}")
            status = mr["merge_status"]
            if status != "can_be_merged":
                # Should never get merge conflicts so if we do something has
                # gone wrong - log an error
                logger.error(f"Merge Status: {status}")
            else:
                logger.info(f"Merge Status: {status}")
            wip = mr["work_in_progress"]
            logger.info(f"Work in Progress: {wip}")
            unresolved = count_unresolved_mr_discussions(mr, config_external)
            logger.info(f"Unresolved Discussions: {unresolved}")
            upvotes = mr["upvotes"]
            logger.info(f"Upvotes: {upvotes}")
            downvotes = mr["downvotes"]
            logger.info(f"Downvotes: {downvotes}")
        except Exception as e:
            logger.error(f"Failed to extract merge request details: {e}")
            continue
        if (
            status == "can_be_merged"
            and wip is False
            and unresolved == 0
            and upvotes >= 2
            and downvotes == 0
        ):
            logger.info("Merge request has been approved. Proceeding with merge.")
            try:
                result = accept_merge_request(mr, config_external)
            except Exception as e:
                logger.error(f"Merge failed! {e}")
                continue
            if result["state"] == "merged":
                logger.info(f"Merge successful! Merge SHA {result['merge_commit_sha']}")
                try:
                    # Save details of accepted merge request to separate log file
                    with open("accepted_merge_requests.log", "a") as f:
                        f.write(
                            f"{result['merged_at']}, {source_project['name_with_namespace']}, {mr['source_branch']}, {mr['sha']}, {target_project['name_with_namespace']}, {mr['target_branch']}, {result['merge_commit_sha']}\n"
                        )
                except Exception as e:
                    logger.error(f"Failed to log accepted merge request: {e}")
                try:
                    logger.info("Pushing project to gitlab internal.")
                    internal_update_repo(
                        target_project["ssh_url_to_repo"],
                        target_project["name"],
                        config_internal,
                    )
                except Exception as e:
                    logger.error(f"Failed to push to internal: {e}")
            else:
                logger.error(f"Merge failed! Merge status is {result['state']}")
        else:
            logger.info("Merge request has not been approved. Skipping.")
    logger.info(f"RUN FINISHED")
    logger.info("=" * 30)


if __name__ == "__main__":
    check_merge_requests()
