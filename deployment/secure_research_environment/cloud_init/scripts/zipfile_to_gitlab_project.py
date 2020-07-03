#!/usr/bin/env python3

import os
import subprocess
from zipfile import ZipFile, BadZipFile
from pathlib import Path
import logging
from logging.handlers import RotatingFileHandler
import requests
import gitlab_config as gl

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
    except FileNotFoundError:
        logger.info("Zipfile dir %s not found - assuming nothing to unzip", zipfile_dir)
        return []

    for d in zipfile_subdirs:
        zipfile_subdir = os.path.join(zipfile_dir, d)
        zipfile_path = os.path.join(zipfile_subdir, "repo.zip")
        unpacked_location = os.path.join(zipfile_subdir, "repo")
        # ensure "repo" does not already exist (from a previous failed attempt)
        subprocess.run(["rm", "-rf", unpacked_location], check=True)
        try:
            with ZipFile(zipfile_path, "r") as zip_obj:
                zip_obj.extractall(path=zipfile_subdir)

            repo_details = [
                Path(os.path.join(unpacked_location, fname)).read_text().rstrip()
                for fname in (
                    "targetRepoName",
                    "sourceCommitHash",
                    "targetBranchName",
                    "sourceGitURL",
                )
            ]
            output_list.append((*repo_details, zipfile_subdir))
        except (BadZipFile, FileNotFoundError, IsADirectoryError):
            logger.exception(
                "Error when processing zipfile at %s. Continuing with remaining zipfiles.",
                zipfile_subdir
            )
            continue
    return output_list


def create_project(gitlab_config, repo_name, namespace_id):
    """
    Create empty project on gitlab, and return the project info as returned by
    GitLab on creation

    Parameters
    ==========
    gitlab_config: dict, gitlab configuration information (same as used elsewhere)
    repo_name: str, name of the repository/project
    namespace_id: int, ID of the group ("unapproved" or "approved")

    Returns
    =======
    gitlab_project_info: dict, containing among other things, the name and
    the remote URL for the project.
    """
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
        raise gl.http_error("Creating project", response)

    project_info = response.json()
    logger.info(
        "Created project %s in namespace %s, project_id %s",
        repo_name,
        namespace_id,
        project_info["id"],
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
                {"action": "create", "file_path": "README.md", "content": README}
            ],
        },
    )

    if response_commit.status_code != 201:
        raise gl.http_error("Making first commit to project", response_commit)

    return project_info


def get_or_create_project(config, namespace_ids, namespace, repo_name):
    project = gl.get_project(config, namespace, repo_name)
    if project:
        return project
    return create_project(config, repo_name, namespace_ids[namespace])


def check_if_branch_exists(gitlab_config, branch_name, project_id):
    """
    See if a branch with name branch_name already exists on this Project

    Parameters
    ==========
    gitlab_config: dict, gitlab configuration (as used elsewhere)
    branch_name: str, name of branch to look for
    project_id: int, id of the project, obtained from projects API endpoint

    Returns
    =======
    branch_exists: bool, True if branch exists, False if not.
    """
    branches_url = "{}/projects/{}/repository/branches".format(
        gitlab_config["api_url"], project_id
    )
    response = requests.get(branches_url, headers=gitlab_config["headers"])
    if response.status_code != 200:
        raise gl.http_error(
            f"Checking for branch {branch_name} on project {project_id}", response,
        )

    branches = response.json()
    for branch_info in branches:
        if branch_info["name"] == branch_name:
            return branch_info
    return False


def create_branch_if_not_exists(
    gitlab_config, branch_name, project_id, reference_branch="_gitlab_ingress_review",
):
    """
    Create a new branch on an existing project if it does not exist already.
    By default, use '_gitlab_ingress_review' as the branch name (which is unlikely
    to exist in the source repo) as the reference branch from which to create the
    new one.

    Parameters
    ==========
    gitlab_config: dict, gitlab configuration information (as used elsewhere)
    branch_name: str, the desired name of the new branch
    project_id: int, the ID of the project, which is the "id" value in
    the dictionary of project information returned when
    creating a new project or listing existing ones.
    reference_branch: str, (default "_gitlab_ingress_review"), create the new
    branch based on this branch

    Returns
    =======
    dict, info about the branch (either existing or newly-created) from API endpoint
    """
    branch = check_if_branch_exists(gitlab_config, branch_name, project_id)
    if branch:
        logger.info("Branch %s exists for project %s", branch_name, project_id)
        return branch

    # Branch does not exist
    branch_url = "{}/projects/{}/repository/branches".format(
        gitlab_config["api_url"], project_id
    )
    response = requests.post(
        branch_url,
        headers=gitlab_config["headers"],
        data={"branch": branch_name, "ref": reference_branch},
    )
    if response.status_code != 201:
        raise gl.http_error(f"Creating branch {branch_name}", response)

    logger.info("Branch %s created for project %s", branch_name, project_id)

    branch_info = response.json()
    return branch_info


def check_if_merge_request_exists(
    gitlab_config, source_project_id, source_branch, target_project_id, target_branch,
):
    """See if there is an existing merge request between the source and target
    project/branch combinations.

    Returns
    =======
    Either: the merge request (if it exists), or False
    """

    mr_url = "{}/projects/{}/merge_requests".format(
        gitlab_config["api_url"], target_project_id
    )
    response = requests.get(mr_url, headers=gitlab_config["headers"])
    if response.status_code != 200:
        raise gl.http_error("Request to check existence of MR failed", response)

    merge_requests = response.json()

    # return the (known unique) merge request if found, otherwise False
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
    """
    Create a new merge request if one does not exist already.  Return
    the existing or newly created merge request information returned
    by the API.
    """
    # Check whether requested MR exists, return it if it does

    mr = check_if_merge_request_exists(
        gitlab_config,
        source_project_id,
        source_branch,
        target_project_id,
        target_branch,
    )
    if mr:
        logger.info("Merge Request for %s already exists", repo_name)
        return mr

    # Ensure fork relationship is established

    fork_url = "{}/projects/{}/fork/{}".format(
        gitlab_config["api_url"], source_project_id, target_project_id
    )
    response = requests.post(fork_url, headers=gitlab_config["headers"])

    # status code 201 if fork relationship created, or 409 if already there
    if (response.status_code != 201) and (response.status_code != 409):
        raise gl.http_error(
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

    # Check explicitly whether merge request exists, since sometimes
    # a 500 status is spuriously returned
    mr = check_if_merge_request_exists(
        gitlab_config,
        source_project_id,
        source_branch,
        target_project_id,
        target_branch,
    )

    if mr and response.status_code == 201:
        logger.info("Created merge request %s -> %s", source_branch, target_branch)
        return mr

    if mr and response.status_code == 500:
        logger.error(
            "Response 500 (%s) returned when creating merge request for %s -> %s, "
            "although the merge request was determined to have been created successfully "
            "so this may not signal a genuine problem.",
            response.reason,
            repo_name
        )
        return mr

    raise gl.http_error(f"Creating merge request for {repo_name}", response)


def clone_commit_and_push(
    path_to_unzipped_repo,
    tmp_repo_dir,
    branch_name,
    target_branch_name,
    remote_url,
    target_project_url,
    commit_hash,
):
    """
    Run shell commands to convert the unzipped directory containing the
    repository contents into a git repo, then commit it on the branch
    with the requested name.

    Parameters
    ==========
    path_to_unzipped_repo: str, the full directory path to the unzipped repo
    tmp_repo_dir: str, path to a temporary dir where we will clone the project
    branch_name: str, the name of the branch holding the snapshot
    target_branch_name: str, the name of the branch to push to
    remote_url: str, the URL for this project on gitlab-review to be added
    as a remote ("unapproved").
    target_project_url: str, the url of the original imported project on 
    gitlab-review ("approved")
    commit_hash: str, the commit hash of the snapshot of the upstream project
    """

    # Clone the repo
    subprocess.run(["git", "clone", remote_url, "cloned_repo"], cwd=tmp_repo_dir, check=True)
    working_dir = os.path.join(tmp_repo_dir, "cloned_repo")
    assert os.path.exists(working_dir)

    # Add upstream (target repo) to this repo
    subprocess.run(
        ["git", "remote", "add", "approved", target_project_url],
        cwd=working_dir,
        check=True,
    )
    subprocess.run(["git", "fetch", "approved"], cwd=working_dir, check=True)

    # Checkout the target branch if it exists
    git_checkout_result = subprocess.run(
        ["git", "checkout", target_branch_name], cwd=working_dir, check=False
    )
    if git_checkout_result.returncode == 0:
        subprocess.run(["git", "pull", "approved"], cwd=working_dir, check=True)

    # now checkout the branch holding the snapshot
    subprocess.run(["git", "checkout", "-b", branch_name], cwd=working_dir, check=True)

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
    commit_msg = "Import snapshot of {} at commit {}".format(remote_url, commit_hash)
    subprocess.run(["git", "commit", "-m", commit_msg], cwd=working_dir, check=True)
    # Push back to gitlab review (unapproved)
    subprocess.run(
        ["git", "push", "-f", "--set-upstream", "origin", branch_name],
        cwd=working_dir,
        check=True,
    )

    logger.info("Pushed to %s, branch %s", remote_url, branch_name)


def fork_project(
    gitlab_config,
    fork_namespace,
    repo_name,
    orig_project_id,
    fork_namespace_id,
):
    """
    Fork the project with id 'orig_project_id' to `fork_namespace`/`repo_name`
    after first checking whether the latter exists.

    Parameters
    ==========
    gitlab_config: dict, gitlab configuration information
    fork_namespace: str, name of the namespace to create the fork
    repo_name: str, name of the repo/project
    orig_project_id: int, project id of the original (forked-from) project
    fork_namespace_id: int, id of the namespace to fork into

    Returns
    =======
    fork_project_info: dict, info of the newly created project from the API
    """

    maybe_fork_project = gl.get_project(gitlab_config, fork_namespace, repo_name)
    if not maybe_fork_project:
        fork_url = "{}/projects/{}/fork".format(
            gitlab_config["api_url"], orig_project_id
        )
        response = requests.post(
            fork_url,
            headers=gitlab_config["headers"],
            data={"namespace_id": fork_namespace_id},
        )
        if response.status_code != 201:
            raise gl.http_error(f"Forking project {orig_project_id}", response)

        fork_project_info = response.json()
    else:
        # project already exists - ensure it is a fork of
        # 'approved/<project-name>'
        fork_project_info = maybe_fork_project
        fork_project_id = fork_project_info["id"]
        fork_url = "{}/projects/{}/fork/{}".format(
            gitlab_config["api_url"], fork_project_id, orig_project_id
        )
        response = requests.post(fork_url, headers=gitlab_config["headers"])
        # status code 201 if fork relationship created, or 409 if already there
        if (response.status_code != 201) and (response.status_code != 409):
            raise gl.http_error("Creating fork relationship", response)

    return fork_project_info


def unzipped_snapshot_to_merge_request(gitlab_config, snapshot_details, namespace_ids):
    """
    Go through all the steps for a single repo/project.

    Parameters
    ==========
    gitlab_config: dict, contains api url and token
    snapshot_details: tuple of strings, (repo_name, hash, desired_branch, location)
    namespace_ids; dict, keys are the group names (e.g. "unapproved", "approved", values
    are the ids of the corresponding namespaces in Gitlab
    """

    # unpack tuple
    (
        repo_name,
        commit_hash,
        target_branch_name,
        source_git_url,
        snapshot_path,
    ) = snapshot_details

    logger.info("Unpacked %s %s %s", repo_name, commit_hash, target_branch_name)

    unzipped_location = os.path.join(snapshot_path, "repo")

    target_project_info = get_or_create_project(
        gitlab_config, "approved", repo_name, namespace_ids,
    )
    target_project_id = target_project_info["id"]
    target_project_url = target_project_info["ssh_url_to_repo"]
    logger.info("Created project approved/%s ", repo_name)

    # Branch to create on the source (unapproved) repository of the
    # matches that of the target
    src_branch_name = f"commit-{commit_hash}"

    # Fork this project to "unapproved" group
    src_project_info = fork_project(
        gitlab_config,
        fork_namespace="unapproved",
        repo_name=repo_name,
        orig_project_id=target_project_id,
        fork_namespace_id=namespace_ids["unapproved"],
    )
    src_project_id = src_project_info["id"]
    remote_url = src_project_info["ssh_url_to_repo"]
    logger.info("Fork of project at unapproved/%s", repo_name)

    # Do the command-line git stuff to push to unapproved project
    clone_commit_and_push(
        unzipped_location,
        snapshot_path,
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
        "unapproved / {}".format(repo_name),  # for logging
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
    subprocess.run(["rm", "-rf", snapshot_path], check=True)


def main():
    zipfile_dir = "/tmp/zipfiles"
    # get the gitlab config
    gitlab_config = gl.get_api_config("GITLAB-REVIEW")

    # unzip the zipfiles, and retrieve a list of tuples describing
    # (repo_name, commit_hash, desired_branch, source_git_url, snapshot_path)
    unzipped_snapshots = unzip_zipfiles(zipfile_dir)

    group_ids = gl.get_group_ids(gitlab_config)

    # TODO check "approved" and "unapproved" key in namespace_ids

    for snapshot_details in unzipped_snapshots:
        unzipped_snapshot_to_merge_request(gitlab_config, snapshot_details, group_ids)


if __name__ == "__main__":
    main()
