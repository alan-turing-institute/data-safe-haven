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
import subprocess
import logging
from logging.handlers import RotatingFileHandler
import requests
import gitlab_config as gl

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

    maybe_project = gl.get_project(config, "ingress", repo_name)

    # create the project if it doesn't exist
    if maybe_project:
        update_repo_url = maybe_project["ssh_url_to_repo"]
    else:
        logger.info("Creating: %s", repo_name)

        response = requests.post(
            config["api_url"] + "/projects",
            headers=config["headers"],
            data={"name": repo_name, "path": repo_name, "visibility": "public"},
        )

        update_repo_url = response.json()["ssh_url_to_repo"]

    # Set the remote
    subprocess.run(
        ["git", "remote", "add", "gitlab", update_repo_url],
        cwd=repo_name,
        check=True,
    )

    # Force push current contents of all branches
    subprocess.run(["git", "push", "--force", "gitlab"], cwd=repo_name, check=True)


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
    all_groups = gl.get_group_ids(config)
    group = all_groups["approved"]
    endpoint = config["api_url"] + f"/groups/{group}/merge_requests"
    response = requests.get(
        endpoint,
        headers=config["headers"],
        data={"state": "opened", "scope": "created_by_me"},
    )
    if response.status_code != 200:
        raise gl.http_error("Getting merge requests for approval", response)

    return response.json()


def unresolved_mr_discussions(config, mr):
    """Does merge request `mr` have any unresolved discussions?  Requires
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
    bool : does mr have any unresolved discussions?
    """
    if mr["user_notes_count"] == 0:
        return 0
    project_id = mr["project_id"]
    mr_iid = mr["iid"]
    endpoint = (
        config["api_url"] + f"/projects/{project_id}/merge_requests/{mr_iid}/discussions"
    )
    response = requests.get(endpoint, headers=config["headers"])
    if response.status_code != 200:
        raise gl.http_error("Getting unresolved merge request discussions", response)

    discussions = response.json()

    for d in discussions:
        for n in d["notes"]:
            if n["resolvable"] is True and n["resolved"] is False:
                return True
    return False


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
        config["api_url"] + f"/projects/{project_id}/merge_requests/{mr_iid}/merge"
    )

    response = requests.put(endpoint, headers=config["headers"])
    if response.status_code != 200:
        raise gl.http_error("Accepting merge request", response)

    return response.json()


def merge_allowed(config_gitlabreview, mr):
    unresolved = unresolved_mr_discussions(config_gitlabreview, mr)
    checks = {
        "unresolved_check": not unresolved,
        "upvotes_check": mr["upvotes"] >= 2,
        "downvotes_check": mr["downvotes"] == 0,
    }
    return (all(checks.values()), checks)


def handle_all_merge_requests():
    """Main function to check merge requests in the approved group on gitlab review,
    approve them where appropriate, and then push the approved repos to the normal
    gitlab server for users.
    """
    logger.info("STARTING RUN")

    config_gitlabreview = gl.get_api_config(server="GITLAB-REVIEW")
    config_gitlab = gl.get_api_config(server="GITLAB")

    response = requests.get(
        config_gitlab["api_url"] + "/projects",
        headers=config_gitlab["headers"],
        timeout=10,
    )
    if response.status_code != 200:
        raise gl.http_error("Getting project list", response)

    logger.info("Getting open merge requests for approval")

    # TODO throw in get_merge_requests_for_approval
    merge_requests = get_merge_requests_for_approval(config_gitlabreview)

    logger.info("Found %s open merge requests", len(merge_requests))

    mr_errors_encountered = 0
    for i, mr in enumerate(merge_requests):
        logger.info("-" * 20)
        logger.info("Merge request %s of %s", i + 1, len(merge_requests))
        logger.info("Checking merge request %s", mr)

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
                source_project = gl.get_project_by_id(config_gitlabreview, mr["source_project_id"])
                target_project = gl.get_project_by_id(config_gitlabreview, mr["project_id"])
                merge_result = accept_merge_request(config_gitlabreview, mr)

                logger.info("Merge completed")
                accepted_mr_logger.info(
                    "%s, %s, %s, %s, %s, %s, %s",
                    merge_result['merged_at'],
                    source_project['name_with_namespace'],
                    mr['source_branch'],
                    mr['sha'],
                    target_project['name_with_namespace'],
                    mr['target_branch'],
                    merge_result['merge_commit_sha'],
                )

                logger.info("Pushing project to gitlab user server.")
                update_repo(
                    config_gitlab,
                    target_project["ssh_url_to_repo"],
                    target_project["name"],
                    mr['target_branch'],
                )
                logger.info("Done")

            else:
                logger.info(
                    "Merge request has not been approved: skipping.  Reason: %s", merge_checks
                )

        # Errors from GitLab requests and subprocess
        except (requests.HTTPError, subprocess.CalledProcessError):
            logger.exception(
                "Handling merge request failed for %s.  Attempting to continue "
                "with remaining merge requests.",
                mr
            )
            mr_errors_encountered += 1
            continue

    logger.info("RUN FINISHED")
    logger.info("=" * 30)

    return mr_errors_encountered


def main():
    try:
        mr_errors = handle_all_merge_requests()
    except Exception:
        logger.exception("Error handling merge requests")
        raise

    return_code = 0 if mr_errors == 0 else 1

    return return_code


if __name__ == "__main__":
    exit_status = main()
    sys.exit(exit_status)
