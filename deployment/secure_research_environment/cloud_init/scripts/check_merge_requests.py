#!/usr/bin/env python3

"""
Check merge requests on gitlab review, approve them where appropriate,
and push the approved repos to gitlab .

1) Get open merge requests in the approved group on gitlab review.
2) Check whether any of them meet the approval conditions. By default: status
is can be merged, no unresolved discussions, at least two upvotes, and no downvotes.
3) Accept approved merge requests (merged unapproved repo into approved repo).
4) Push whole approved repo to gitlab, creating the repo if it doesn't
already exist.

This script creates two log files in the directory where it is run:
* check_merge_requests.log : A verbose log of the steps performed in each run
and any errors encountered
* accepted_merge_requests.log : A list of merge requests that have been accepted
in CSV format with columns merged time, source project, source branch, source
commit, target project, target branch and target commit
"""

import sys
import requests
import subprocess
from urllib.parse import quote as url_quote
from pathlib import Path
import logging
from logging.handlers import RotatingFileHandler
from gitlab_config import get_api_config

##
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

# Separate logfile for accepted merge requests, no file size limit
accepted_mr_logger = logging.getLogger("accepted_merge_requests_logger")
accepted_mr_logger.setLevel(logging.INFO)
accepted_mr_formatter = logging.Formatter("%(message)s")
accepted_mr_handler = logging.FileHandler("accepted_merge_requests.log")
accepted_mr_handler.setFormatter(accepted_mr_formatter)
accepted_mr_logger.addHandler(accepted_mr_handler)


def check_project_exists(repo_name, config):
    """Determine whether a repo exist in the ingress namespace on
    gitlab server defined by config.

    Parameters
    ----------
    repo_name : str
        The name of a repo (not a URL) to search for in the ingress namespace.
    config : dict
        Gitlab details and secrets as returned by get_api_config

    Returns
    -------
    tuple
        (exists, url) tuple where exists: boolean - does repo_name exist,
        and url: str - the ssh url to the repo (when 'exists' is true)

    Raises
    ------
    requests.HTTPError
        If API request returns an unexpected code (not 404 or 200)
    """

    # build url-encoded repo_name
    repo_path_encoded = url_quote("ingress/" + repo_name, safe="")

    # Does repo_name exist?
    response = requests.get(
        config["api_url"] + "/projects/" + repo_path_encoded,
        headers=config["headers"],
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
            "Unexpected response: "
            + response.reason
            + ", content: "
            + response.text
        )


def update_repo(git_url, repo_name, branch_name, config):
    """Takes a git URL, `git_url`, which should be the SSH URL to the
    "APPROVED" repo on GITLAB-REVIEW, clones it and pushes all branches to
    the repo `repo_name` owned by 'ingress' on the gitlab server defined in
    config, creating it there first if it doesn't exist.

    Parameters
    ----------
    git_url : str
        URL to the "APPROVED" repo on GITLAB-REVIEW
    repo_name : str
        Name of repo to create on.
    config : dict
        Details and secrets as returned by get_api_config
    """

    # clone the repo from git_url (on GITLAB-REVIEW), removing any of
    # the same name first (simpler than checking if it exists, has the
    # same remote and pulling)
    subprocess.run(["rm", "-rf", repo_name], check=True)
    subprocess.run(["git", "clone", git_url, repo_name], check=True)
    subprocess.run(["git", "checkout", branch_name], cwd=repo_name, check=True)

    project_exists, gl_update_repo_url = check_project_exists(repo_name, config)

    # create the project if it doesn't exist
    if not project_exists:
        print("Creating: " + repo_name)
        response = requests.post(
            config["api_url"] + "/projects",
            headers=config["headers"],
            data={"name": repo_name, "path": repo_name, "visibility": "public"},
        )
        response.raise_for_status()
        assert response.json()["path_with_namespace"] == "ingress/" + repo_name

        gl_update_repo_url = response.json()["ssh_url_to_repo"]

    # Set the remote
    subprocess.run(
        ["git", "remote", "add", "gitlab", gl_update_repo_url],
        cwd=repo_name,
        check=True,
    )

    # Force push current contents of all branches
    subprocess.run(
        ["git", "push", "--force", "gitlab"], cwd=repo_name, check=True
    )


def get_group_id(group_name, config):
    """Get the ID of a group on a gitlab server.

    Parameters
    ----------
    group_name : str
        Group name to find.
    config : dict
        Gitlab details and secrets as returned by get_api_config

    Returns
    -------
    int
        Group ID for group_name

    Raises
    ------
    ValueError
        If group_name not found in the groups returned from the gitlab server.
    """
    endpoint = config["api_url"] + "/groups"
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
        Gitlab details and secrets as returned by get_api_config

    Returns
    -------
    dict
        Project JSON as returned by the gitlab API.
    """
    endpoint = config["api_url"] + f"/projects/{project_id}"
    project = get_request(endpoint, headers=config["headers"])
    return project


def get_merge_requests_for_approval(config):
    """Get the details of all open merge requests into the approved group on
    a gitlab server.

    Parameters
    ----------
    config : dict
        Gitlab details and secrets as returned by get_api_config

    Returns
    -------
    list
        List of merge requests JSONs as returned by the gitlab API.
    """
    group = get_group_id("approved", config)
    endpoint = config["api_url"] + f"/groups/{group}/merge_requests"
    response = get_request(
        endpoint,
        headers=config["headers"],
        params={"state": "opened", "scope": "created_by_me"},
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
        Gitlab details and secrets as returned by get_api_config

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
        config["api_url"]
        + f"/projects/{project_id}/merge_requests/{mr_iid}/discussions"
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


def accept_merge_request(config, mr):
    """Accept a merge request

    Parameters
    ----------
    mr : dict
        For the merge request to approve: The merge request JSON as returned by
        the gitlab API.
    config : dict
        Gitlab details and secrets as returned by get_api_config

    Returns
    -------
    dict
        JSON response from gitlab API representing the status of the accepted
        merge request.
    """
    project_id = mr["project_id"]
    mr_iid = mr["iid"]
    endpoint = (
        config["api_url"]
        + f"/projects/{project_id}/merge_requests/{mr_iid}/merge"
    )

    response = requests.put(endpoint, headers=config["headers"])
    if response.status_code != 200:
        raise http_error("Accepting merge request", response)

    return response.json()


def merge_allowed(config_gitlabreview, mr):
    unresolved = count_unresolved_mr_discussions(mr, config_gitlabreview)
    checks = {
        "unresolved_check": unresolved == 0,
        "upvotes_check": mr["upvotes"] >= 2,
        "downvotes_check": mr["downvotes"] == 0,
    }
    return (all(checks.values()), checks)


def handle_all_merge_requests():
    """Main function to check merge requests in the approved group on gitlab review,
    approve them where appropriate, and then push the approved repos to the normal
    gitlab server for users.
    """
    logger.info(f"STARTING RUN")

    config_gitlabreview = get_api_config(server="GITLAB-REVIEW")
    config_gitlab = get_api_config(server="GITLAB")

    response = requests.get(
        config_gitlab["api_url"] + "/projects",
        headers=config_gitlab["headers"],
        timeout=10,
    )
    if response.status_code != 200:
        raise http_error("Getting project list", response)

    logger.info("Getting open merge requests for approval")

    ## TODO throw in get_merge_requests_for_approval
    merge_requests = get_merge_requests_for_approval(config_gitlabreview)

    logger.info(f"Found {len(merge_requests)} open merge requests")

    mr_errors_encountered = 0
    for i, mr in enumerate(merge_requests):
        logger.info("-" * 20)
        logger.info(f"Merge request {i+1} of {len(merge_requests)}")
        logger.info(f"Checking merge request {mr}")

        if mr["merge_status"] != "can_be_merged":
            logger.error(
                "This Merge Request's merge status indicates that "
                "it cannot be merged.  This should never happen. "
                "Skipping this MR."
            )
            mr_errors_encountered += 1
            continue

        try:
            can_merge, merge_checks = merge_allowed(config_gitlabreview, mr)
            if can_merge:
                logger.info("Merge request has been approved. Proceeding with merge.")
                source_project = get_project(config_gitlabreview, mr["source_project_id"])
                target_project = get_project(config_gitlabreview, mr["project_id"])
                merge_result = accept_merge_request(config_gitlabreview, mr)

                logger.info("Merge completed")
                accepted_mr_logger.info(
                    f"{merge_result['merged_at']}, "
                    f"{source_project['name_with_namespace']}, "
                    f"{mr['source_branch']}, "
                    f"{mr['sha']}, "
                    f"{target_project['name_with_namespace']}, "
                    f"{mr['target_branch']}, "
                    f"{merge_result['merge_commit_sha']}"
                )

                logger.info("Pushing project to gitlab user server.")
                update_repo(
                    config_gitlab
                    target_project["ssh_url_to_repo"],
                    target_project["name"],
                    target_branch,
                )
                logger.info("Done")

            else:
                logger.info(
                    f"Merge request has not been approved: skipping.  Reason: {merge_checks}"
                )

        ## Errors from GitLab requests and subprocess
        except requests.HTTPError, subprocess.CalledProcessError:
            logger.exception(
                f"Handling merge request failed for {mr}.  Attempting to continue with remaining merge requests."
            )
            mr_errors_encountered += 1
            continue

    logger.info("RUN FINISHED")
    logger.info("=" * 30)

    return mr_errors_encountered



if __name__ == "__main__":

    try:
        mr_errors_encountered = handle_all_merge_requests()
    except Exception as e:
        logger.exception("Error handling merge requests")
        raise

    return_code = 0 if mr_errors_encountered == 0 else 1

    sys.exit(return_code)
