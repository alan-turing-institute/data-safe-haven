#!/usr/bin/env python3
import os
import shutil
import re
import requests
import subprocess
import tempfile
from zipfile import ZipFile, BadZipFile
from urllib.parse import quote as url_quote
from pathlib import Path
import logging
from logging.handlers import RotatingFileHandler
from gitlab_config import get_api_config
from requests_util import http_error

logger = logging.getLogger("project_upload_logger")
logger.setLevel(logging.INFO)
formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
f_handler = RotatingFileHandler(
    "zipfile_to_gitlab_project.log", maxBytes=5 * 1024 * 1024, backupCount=10
)
f_handler.setFormatter(formatter)
c_handler = logging.StreamHandler()
c_handler.setFormatter(formatter)
logger.addHandler(f_handler)
logger.addHandler(c_handler)


def unzip_zipfiles(zipfile_dir):
    output_list = []
    try:
        zipfile_subdirs = os.listdir(zipfile_dir)
    except (FileNotFoundError):
        logger.info(
            f"Zipfile dir {zipfile_dir} not found - assuming nothing to unzip"
        )
        return []

    for d in zipfile_subdirs:
        zipfile_subdir = os.path.join(zipfile_dir, d)
        zipfile_path = os.path.join(zipfile_subdir, "repo.zip")
        unpacked_location = os.path.join(zipfile_subdir, "repo")
        ## ensure "repo" does not already exist (from a previous failed attempt)
        subprocess.run("rm", "-rf", unpacked_location, check=True)
        try:
            with ZipFile(zipfile_path, "r") as zip_obj:
                zip_obj.extractall(path=zipfile_subdir)

            repo_details = [
                Path(os.path.join(unpacked_location, fname))
                .read_text()
                .rstrip()
                for fname in (
                    "targetRepoName",
                    "sourceCommitHash",
                    "targetBranchName",
                    "sourceGitURL",
                )
            ]
            output_list.append((*repo_details, zipfile_subdir))
        except (BadZipFile, FileNotFoundError, IsADirectoryError) as e:
            logger.exception(
                f"Error when processing zipfile at {zipfile_subdir}. Continuing with remaining zipfiles."
            )
            continue
    return output_list


def get_group_namespace_ids(gitlab_config, groups=["approved", "unapproved"]):
    namespaces_url = "{}/namespaces/".format(gitlab_config["api_url"])
    response = requests.get(namespaces_url, headers=gitlab_config["headers"])
    if response.status_code != 200:
        raise http_error("Geting group namespace ids", response)

    gitlab_namespaces = response.json()

    return {
        namespace["name"]: namespace["id"]
        for namespace in gitlab_namespaces
        if namespace["kind"] == "group" and namespace["name"] in groups
    }


def get_gitlab_project_list(gitlab_config):
    projects_url = "{}/projects/".format(gitlab_config["api_url"])
    response = requests.get(
        projects_url,
        headers=gitlab_config["headers"],
        params={"owned": True, "simple": True},
    )
    if response.status_code != 200:
        raise http_error("Getting project list", response)

    gitlab_projects = response.json()
    return gitlab_projects


def check_if_project_exists(gitlab_config, repo_name, namespace_id):
    projects = get_gitlab_project_list(gitlab_config)
    for project in projects:
        if (
            project["name"] == repo_name
            and project["namespace"]["id"] == namespace_id
        ):
            return project
    return False


def create_project(gitlab_config, repo_name, namespace_id):
    projects_url = "{}/projects/".format(gitlab_config["api_url"])
    response = requests.post(
        projects_url,
        headers=gitlab_config["headers"],
        data={
            "name": repo_name,
            "path": repo_name,
            "visibility": "internal",
            "namespace_id": namespace_id,
            "default_branch": "_gitlab_ingress_review",
        },
    )

    if response.status_code != 200:
        raise http_error("Creating project", response)

    project_info = response.json()
    logger.info(
        "Created project {} in namespace {}, project_id {}".format(
            repo_name, namespace_id, project_info["id"]
        )
    )
    # make the initial commit of README initialized with some instructions
    README = f"""
# {repo_name}

This is the root commit of the repository holding snapshots of the
reqested Git repository, at the commits that have been requested for
review.

For guidance on the Safe Haven review process, see the Safe Haven
documentation, or contact ....

## For Reviewers

There is a merge request into this repository (`approved/{repo_name}`)
for each ingress request.

Please look at each merge request in turn, and review it using the
usual GitLab review facilities to determine whether it can be brought
into the user-visible GitLab within the Safe Haven.

- If you approve of making this snapshot available to the environment,
  indicate your approval by leaving a "thumbs up" reaction to the top
  comment of the Merge Request.
- Two such approvals are **required** before the merge request will be
  **automatically merged** and brought into the user-visible GitLab in
  the Research Environment.
- Any "thumbs down" reactions to the top comment of the Merge Request
  will prevent the automated merge. This applies even if there are two
  "thumbs up" reactions.
- Any "unresolved threads" will also prevent the merge so make sure
  that all comment threads in the discussion have been marked as
  resolved once they have been addressed.

**Important**: Once the conditions above have been met, the merge
will be made automatically.  This could take up to 10 minutes.  There
is no need (and you will not have the capability) to merge manually.

## For Safe Haven Users

The branches of this repository contain snapshots at the individual
commits that have been requested and approved by the Safe Haven Git
Ingress process.  The commit history is not kept.  For more on this
process, see the Safe Haven documentation.  This commit will be the
root of each of these branches, and the contents of this file will be
overwritten (or removed) by the contents of the requested repository,
so if you are reading this, it is likely that you are browsing the
commit history.
"""
    # Make the first commit to the project with the README
    project_commit_url = "{}/projects/{}/repository/commits".format(
        gitlab_config["api_url"], project_info["id"]
    )
    response_commit = requests.post(
        project_commit_url,
        headers=gitlab_config["headers"],
        json={
            "branch": "_gitlab_ingress_review",
            "commit_message": "Initial commit",
            "actions": [
                {
                    "action": "create",
                    "file_path": "README.md",
                    "content": README,
                }
            ],
        },
    )

    if response_commit.status_code != 201:
        raise http_error("Making first commit to project", response_commit)

    return project_info


def get_or_create_project(gitlab_config, repo_name, namespace_id):
    project = check_if_project_exists(gitlab_config, repo_name, namespace_id)
    if project:
        return project
    else:
        return create_project(gitlab_config, repo_name, namespace_id)


def check_if_branch_exists(gitlab_config, branch_name, project_id):
    branches_url = "{}/projects/{}/repository/branches".format(
        gitlab_config["api_url"], project_id
    )
    response = requests.get(branches_url, headers=gitlab_config["headers"])
    if response.status_code != 200:
        raise http_error(
            f"Checking for branch {branch_name} on project {project_id}",
            response,
        )

    branches = response.json()
    for branch_info in branches:
        if branch_info["name"] == branch_name:
            return branch_info
    return False


def create_branch_if_not_exists(
    gitlab_config,
    branch_name,
    project_id,
    reference_branch="_gitlab_ingress_review",
):
    branch = check_if_branch_exists(gitlab_config, branch_name, project_id)
    if branch:
        logger.info(f"Branch {branch_name} exists for project {project_id}")
        return branch

    ## Branch does not exist
    branch_url = "{}/projects/{}/repository/branches".format(
        gitlab_config["api_url"], project_id
    )
    response = requests.post(
        branch_url,
        headers=gitlab_config["headers"],
        data={"branch": branch_name, "ref": reference_branch},
    )
    if response.status_code != 201:
        raise http_error(f"Creating branch {branch_name}", response)

    logger.info(f"Branch {branch_name} created for project {project_id}")

    branch_info = response.json()
    return branch_info


def check_if_merge_request_exists(
    gitlab_config,
    source_project_id,
    source_branch,
    target_project_id,
    target_branch,
):
    mr_url = "{}/projects/{}/merge_requests".format(
        gitlab_config["api_url"], target_project_id
    )
    response = requests.get(mr_url, headers=gitlab_config["headers"])
    if response.status_code != 200:
        raise http_error("Request to check existence of MR failed", response)

    merge_requests = response.json()

    ## return the (known unique) merge request if found, otherwise False
    for mr in merge_requests:
        if (
            mr["source_branch"] == source_branch
            and mr["target_branch"] == target_branch
            and mr["source_project_id"] == source_project_id
        ):
            return mr
    return False


def create_merge_request_if_not_exists(
    gitlab_config,
    repo_name,
    source_project_id,
    source_branch,
    target_project_id,
    target_branch,
):
    ## Check whether requested MR exists, return it if it does

    mr = check_if_merge_request_exists(
        gitlab_config,
        source_project_id,
        source_branch,
        target_project_id,
        target_branch,
    )
    if mr:
        logger.info(f"Merge Request for {repo_name} already exists")
        return mr

    ## Ensure fork relationship is established

    fork_url = "{}/projects/{}/fork/{}".format(
        gitlab_config["api_url"], source_project_id, target_project_id
    )
    response = requests.post(fork_url, headers=gitlab_config["headers"])

    # status code 201 if fork relationship created, or 409 if already there
    if (response.status_code != 201) and (response.status_code != 409):
        raise http_error(
            f"Creating fork request between projects {source_project_id} and {target_project_id}",
            response,
        )

    mr_url = "{}/projects/{}/merge_requests".format(
        gitlab_config["api_url"], source_project_id,
    )
    response = requests.post(
        mr_url,
        headers=gitlab_config["headers"],
        data={
            "source_branch": source_branch,
            "target_branch": target_branch,
            "target_project_id": target_project_id,
            "title": f"{repo_name}: {source_branch} to {target_branch}",
        },
    )

    ## Check explicitly whether merge request exists, since sometimes
    ## a 500 status is spuriously returned
    mr = check_if_merge_request_exists(
        gitlab_config,
        source_project_id,
        source_branch,
        target_project_id,
        target_branch,
    )

    if mr and response.status_code == 500:
        logger.error(
            f"Response 500 ({response.reason}) returned when creating merge request for {repo_name}, although the merge request was created.  This may not signal a genuine problem."
        )
        return mr

    elif response.status_code != 201:
        raise http_error(f"Creating merge request for {repo_name}", response)

    logger.info(f"Created merge request {source_branch} -> {target_branch}")
    mr_info = response.json()
    return mr_info


def clone_commit_and_push(
    repo_name,
    path_to_unzipped_repo,
    tmp_repo_dir,
    branch_name,
    target_branch_name,
    remote_url,
    target_project_url,
    commit_hash,
):
    # Clone the repo
    subprocess.run(["git", "clone", remote_url], cwd=tmp_repo_dir, check=True)
    working_dir = os.path.join(tmp_repo_dir, repo_name)
    assert os.path.exists(working_dir)

    # Add upstream (target repo) to this repo
    subprocess.run(
        ["git", "remote", "add", "approved", target_project_url],
        cwd=working_dir,
        check=True,
    )
    subprocess.run(["git", "fetch", "approved"], cwd=working_dir, check=True)

    # Checkout the branch with the requested name (creating it at the
    # current commit of the default branch if it doesn't exist)
    git_checkout_result = subprocess.run(
        ["git", "checkout", target_branch_name], cwd=working_dir
    )
    if git_checkout_result.returncode == 0:
        subprocess.run(["git", "pull", "approved"], cwd=working_dir, check=True)

    # now checkout the branch holding the snapshot
    subprocess.run(
        ["git", "checkout", "-b", branch_name], cwd=working_dir, check=True
    )

    # Remove the contents of the cloned repo (everything except .git)
    for item in os.listdir(working_dir):
        if item != ".git":
            subprocess.run(["rm", "-rf", item], cwd=working_dir, check=True)

    # Copy the unzipped repo contents into our cloned (empty) repo
    for item in os.listdir(path_to_unzipped_repo):
        subprocess.run(
            ["cp", "-r", os.path.join(path_to_unzipped_repo, item), "."],
            cwd=working_dir,
            check=True,
        )

    # Commit everything to this branch, also putting commit hash into message
    subprocess.run(["git", "add", "."], cwd=working_dir, check=True)
    commit_msg = "Import snapshot of {} at commit {}".format(
        remote_url, commit_hash
    )
    subprocess.run(
        ["git", "commit", "-m", commit_msg], cwd=working_dir, check=True
    )
    # Push back to gitlab review (unapproved)
    subprocess.run(
        ["git", "push", "-f", "--set-upstream", "origin", branch_name],
        cwd=working_dir,
        check=True,
    )

    logger.info("Pushed to {} branch {}".format(remote_url, branch_name))


def fork_project(gitlab_config, repo_name, project_id, namespace_id):
    already_exists = check_if_project_exists(
        gitlab_config,
        repo_name,
        namespace_id,
        gitlab_config["api_url"],
        gitlab_config["api_token"],
    )
    if not already_exists:
        fork_url = "{}/projects/{}/fork".format(
            gitlab_config["api_url"], project_id
        )
        response = requests.post(
            fork_url,
            headers=gitlab_config["headers"],
            data={"namespace_id": namespace_id},
        )
        if response.status_code != 201:
            raise http_error("Forking project {project_id}", response)

        new_project_info = response.json()
    else:
        # project already exists - ensure it is a fork of
        # 'approved/<project-name>'
        new_project_info = get_or_create_project(
            gitlab_config,
            repo_name,
            namespace_id,
            gitlab_config["api_url"],
            gitlab_config["api_token"],
        )
        new_project_id = new_project_info["id"]
        fork_url = "{}/projects/{}/fork/{}".format(
            gitlab_config["api_url"], new_project_id, project_id
        )
        response = requests.post(fork_url, headers=gitlab_config["headers"],)
        # status code 201 if fork relationship created, or 409 if already there
        if (response.status_code != 201) and (response.status_code != 409):
            raise http_error("Creating fork relationship", response)

    return new_project_info


def unzipped_snapshot_to_merge_request(
    gitlab_config, snapshot_details, namespace_ids
):
    # unpack tuple
    (
        repo_name,
        commit_hash,
        target_branch_name,
        source_git_url,
        snapshot_path,
    ) = snapshot_details
    logger.info(
        "Unpacked {} {} {}".format(repo_name, commit_hash, target_branch_name)
    )

    unzipped_location = os.path.join(snapshot_path, "repo")

    target_project_info = get_or_create_project(
        gitlab_config, repo_name, namespace_ids["approved"],
    )
    target_project_id = target_project_info["id"]
    target_project_url = target_project_info["ssh_url_to_repo"]
    logger.info("Created project {}/{} ".format(group_names[1], repo_name))

    # Branch to create on the source (unapproved) repository of the
    # matches that of the target
    src_branch_name = f"commit-{commit_hash}"

    # Fork this project to "unapproved" group
    src_project_info = fork_project(
        gitlab_config,
        repo_name,
        target_project_id,
        namespace_ids["unapproved"],
    )
    src_project_id = src_project_info["id"]
    remote_url = src_project_info["ssh_url_to_repo"]
    logger.info("Fork of project at {}/{}".format(group_names[0], repo_name))

    # Do the command-line git stuff to push to unapproved project
    clone_commit_and_push(
        repo_name,
        unzipped_location,
        tmp_repo_dir,
        src_branch_name,
        target_branch_name,
        remote_url,
        target_project_url,
        commit_hash,
    )

    # Create the branch on the "approved" project if it doesn't already exist
    create_branch_if_not_exists(
        gitlab_config,
        target_branch_name,
        target_project_id,
        "{} / {}".format(group_names[1], repo_name),  ## for logging
    )

    # Create the merge request
    create_merge_request_if_not_exists(
        gitlab_config,
        repo_name,
        src_project_id,
        src_branch_name,
        target_project_id,
        target_branch_name,
    )

    # cleanup this zipfile and its extracted contents
    subprocess.run("rm", "-rf", snapshot_path, check=True)


def main():
    zipfile_dir = "/tmp/zipfiles"
    # get the gitlab config
    gitlab_config = get_api_config("GITLAB-REVIEW")

    # unzip the zipfiles, and retrieve a list of tuples describing
    # (repo_name, commit_hash, desired_branch, source_git_url, snapshot_path)
    unzipped_snapshots = unzip_zipfiles(zipfile_dir)

    gitlab_ingress_groups = ["unapproved", "approved"]
    namespace_ids = get_group_namespace_ids(
        gitlab_config, gitlab_ingress_groups
    )

    for snapshot_details in unzipped_snapshots:
        unzipped_snapshot_to_merge_request(
            gitlab_config, snapshot_details, namespace_ids
        )


if __name__ == "__main__":
    main()
