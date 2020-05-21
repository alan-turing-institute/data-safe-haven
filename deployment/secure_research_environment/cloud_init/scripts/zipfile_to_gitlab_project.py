#!/usr/bin/env python3
import os
import shutil
import re
import requests
import subprocess
from zipfile import ZipFile, BadZipFile
from urllib.parse import quote as url_quote
from pathlib import Path
import logging
from logging.handlers import RotatingFileHandler

logger = logging.getLogger("project_upload_logger")
logger.setLevel(logging.INFO)
formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
f_handler = RotatingFileHandler(
    "upload_zipfiles_to_projects.log", maxBytes=5 * 1024 * 1024, backupCount=10
)
f_handler.setFormatter(formatter)
c_handler = logging.StreamHandler()
c_handler.setFormatter(formatter)
logger.addHandler(f_handler)
logger.addHandler(c_handler)


def unzip_zipfiles(zipfile_dir, tmp_unzipped_dir):
    output_list = []
    repo_commit_regex = re.compile("([-\w]+)_([a-f\d]+)_([\S]+).zip")
    # tear down and recreate the directory where we will put the unpacked zip
    shutil.rmtree(tmp_unzipped_dir, ignore_errors=True)
    os.makedirs(tmp_unzipped_dir)
    # look in a directory for zipfiles
    try:
        zipfiles = os.listdir(zipfile_dir)
    except (FileNotFoundError):
        logger.info(
            "Zipfile dir {} not found - assume nothing to unzip".format(zipfile_dir)
        )
        return []
    for zipfile in zipfiles:
        filename_match = repo_commit_regex.search(zipfile)
        if not filename_match:
            logger.info("Badly named zipfile! {}".format(zipfile))
            continue
        repo_name, commit_hash, branch = filename_match.groups()

        # unzip
        try:
            zipfile_path = os.path.join(zipfile_dir, zipfile)
            with ZipFile(zipfile_path, "r") as zip_obj:
                zip_obj.extractall(path=tmp_unzipped_dir)
            # we should have made a new directory - find its name
            unpacked_zips = os.listdir(tmp_unzipped_dir)
            unpacked_location = os.path.join(tmp_unzipped_dir, unpacked_zips[0])
            output_list.append((repo_name, commit_hash, branch, unpacked_location))
        except (BadZipFile):
            logger.info("Bad zipfile: {}".format(zipfile))
            continue
    return output_list


def get_gitlab_config():
    home = str(Path.home())

    with open(f"{home}/.secrets/gitlab-external-ip-address", "r") as f:
        ip = f.readlines()[0].strip()

    with open(f"{home}/.secrets/gitlab-external-api-token", "r") as f:
        token = f.readlines()[0].strip()
    api_url = f"http://{ip}/api/v4/"
    headers = {"Authorization": "Bearer " + token}

    return {"api_url": api_url, "api_token": token, "ip": ip, "headers": headers}


def get_group_namespace_ids(
    gitlab_url, gitlab_token, groups=["approval", "unapproved"]
):
    namespaces_url = "{}/namespaces/".format(gitlab_url)
    response = requests.get(
        namespaces_url, headers={"Authorization": "Bearer " + gitlab_token}
    )
    if response.status_code != 200:
        raise RuntimeError(
            "Bad request: {} {}".format(response.status_code, response.content)
        )
    gitlab_namespaces = response.json()
    namespace_id_dict = {}
    for namespace in gitlab_namespaces:
        if namespace["kind"] == "group" and namespace["name"] in groups:
            namespace_id_dict[namespace["name"]] = namespace["id"]
    return namespace_id_dict


def get_gitlab_project_list(gitlab_url, gitlab_token):
    # list currently existing projects on Gitlab
    projects_url = "{}/projects/".format(gitlab_url)
    response = requests.get(
        projects_url,
        headers={"Authorization": "Bearer " + gitlab_token},
        params={"owned": True, "simple": True},
    )

    if response.status_code != 200:
        raise RuntimeError(
            "Bad request: {} {}".format(response.status_code, response.content)
        )
    gitlab_projects = response.json()
    return gitlab_projects


def check_if_project_exists(repo_name, namespace_id, gitlab_url, gitlab_token):
    projects = get_gitlab_project_list(gitlab_url, gitlab_token)
    for project in projects:
        if project["name"] == repo_name and project["namespace"]["id"] == namespace_id:
            return True
    return False


def get_project_info(repo_name, namespace_id, gitlab_url, gitlab_token):
    already_exists = check_if_project_exists(
        repo_name, namespace_id, gitlab_url, gitlab_token
    )
    if already_exists:
        projects = get_gitlab_project_list(gitlab_url, gitlab_token)
        for project_info in projects:
            if (
                project_info["name"] == repo_name
                and project_info["namespace"]["id"] == namespace_id
            ):
                return project_info
    else:
        project_info = create_project(repo_name, namespace_id, gitlab_url, gitlab_token)
        return project_info


def get_project_remote_url(repo_name, namespace_id, gitlab_url, gitlab_token):
    project_info = get_project_info(repo_name, namespace_id, gitlab_url, gitlab_token)

    return project_info["ssh_url_to_repo"]


def get_project_id(repo_name, namespace_id, gitlab_url, gitlab_token):
    project_info = get_project_info(repo_name, namespace_id, gitlab_url, gitlab_token)

    return project_info["id"]


def create_project(repo_name, namespace_id, gitlab_url, gitlab_token):
    projects_url = "{}projects/".format(gitlab_url)
    response = requests.post(
        projects_url,
        headers={"Authorization": "Bearer " + gitlab_token},
        data={
            "name": repo_name,
            "path": repo_name,
            "visibility": "internal",
            "namespace_id": namespace_id,
            "default_branch": "_gitlab_ingress_review"
        },
    )
    assert response.json()["name"] == repo_name
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

There is a merge request into this repository (`approval/{repo_name}`)
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
- Any "unresolved threads" will prevent the merge so make sure that
  all comment threads in the discussion have been marked as resolved.

**Important**: Once the repository has had two approvals, the merge
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
    project_commit_url = f"{gitlab_url}/projects/{project_info['id']}/repository/commits"   
    response = requests.post(
        project_commit_url,
        headers={"Authorization": "Bearer " + gitlab_token},
        json={
            "branch": "_gitlab_ingress_review",
            "commit_message": "Initial commit",
            "actions": [
                {
                    "action": "create",
                    "file_path": "README.md",
                    "content": README
                }
            ]
        }
    )
    return project_info


def check_if_branch_exists(branch_name, project_id, gitlab_url, gitlab_token):
    branches_url = "{}/projects/{}/repository/branches".format(gitlab_url, project_id)
    response = requests.get(
        branches_url, headers={"Authorization": "Bearer " + gitlab_token}
    )
    if response.status_code != 200:
        raise RuntimeError(
            "Unable to check for branch {} on project {}: {}".format(
                branch_name, project_id, r.content
            )
        )
    branches = response.json()
    for branch_info in branches:
        if branch_info["name"] == branch_name:
            return True
    return False


def create_branch(
    branch_name, project_id, gitlab_url, gitlab_token,
        reference_branch="_gitlab_ingress_review"
):
    # assume branch doesn't already exist - create it!
    branch_url = "{}/projects/{}/repository/branches".format(gitlab_url, project_id)
    response = requests.post(
        branch_url,
        headers={"Authorization": "Bearer " + gitlab_token},
        data={"branch": branch_name, "ref": reference_branch},
    )
    if response.status_code != 201:
        raise RuntimeError(
            "Problem creating branch {}: {}".format(branch_name, response.content)
        )
    branch_info = response.json()
    assert branch_info["name"] == branch_name
    return branch_info


def check_if_merge_request_exists(
    source_branch, target_project_id, target_branch, gitlab_url, gitlab_token
):
    mr_url = "{}/projects/{}/merge_requests".format(gitlab_url, target_project_id)
    response = requests.get(mr_url, headers={"Authorization": "Bearer " + gitlab_token})
    if response.status_code != 200:
        raise RuntimeError(
            "Request to check existence of MR failed: {} {}".format(
                response.status_code, response.content
            )
        )
    for mr in response.json():
        if (
            mr["source_branch"] == source_branch
            and mr["target_branch"] == target_branch
        ):
            logger.info(
                "Merge request {} -> {} already exists".format(
                    source_branch, target_branch
                )
            )
            return True
    return False


def create_merge_request(
    repo_name,
    source_project_id,
    source_branch,
    target_project_id,
    target_branch,
    gitlab_url,
    gitlab_token,
):
    # first need to create a forked-from relationship between the projects
    fork_url = "{}/projects/{}/fork/{}".format(
        gitlab_url, source_project_id, target_project_id
    )
    response = requests.post(
        fork_url, headers={"Authorization": "Bearer " + gitlab_token}
    )
    # status code 201 if fork relationship created, or 409 if already there
    if (response.status_code != 201) and (response.status_code != 409):
        raise RuntimeError(
            "Unable to create fork relationship: {} {}".format(
                response.status_code, response.content
            )
        )

    mr_url = "{}/projects/{}/merge_requests".format(gitlab_url, source_project_id)
    title = "{}: {} to {}".format(repo_name, source_branch, target_branch)
    response = requests.post(
        mr_url,
        headers={"Authorization": "Bearer " + gitlab_token},
        data={
            "source_branch": source_branch,
            "target_branch": target_branch,
            "target_project_id": target_project_id,
            "title": title,
        },
    )
    if response.status_code != 201:
        #        raise RuntimeError("Problem creating Merge Request {} {} {}: {}"\
        #                           .format(repo_name, source_branch,target_branch,
        #                                   response.content))
        ##### TEMPORARY - don't raise an error here - we get 500 status code
        ##### even though MR is created it - under investigation.
        logger.info(
            "Problem creating Merge Request {} {} {}: {}".format(
                repo_name, source_branch, target_branch, response.content
            )
        )
        return {}
    mr_info = response.json()
    return mr_info


def clone_commit_and_push(
    repo_name, path_to_unzipped_repo, tmp_repo_dir, branch_name, remote_url, commit_hash
):
    # Clone the repo
    subprocess.run(["git", "clone", remote_url], cwd=tmp_repo_dir, check=True)
    working_dir = os.path.join(tmp_repo_dir, repo_name)
    assert os.path.exists(working_dir)
    # Copy the unzipped repo contents into our cloned (empty) repo
    for item in os.listdir(path_to_unzipped_repo):
        subprocess.run(
            ["cp", "-r", os.path.join(path_to_unzipped_repo, item), "."],
            cwd=working_dir,
            check=True,
        )
    # Create the branch with the requested name
    subprocess.run(["git", "checkout", "-b", branch_name], cwd=working_dir, check=True)
    # Commit everything to this branch, also putting commit hash into message
    subprocess.run(["git", "add", "."], cwd=working_dir, check=True)
    commit_msg = "Import snapshot of {} at commit {}".format(remote_url, commit_hash)
    subprocess.run(["git", "commit", "-m", commit_msg], cwd=working_dir, check=True)
    # Push back to gitlab external
    subprocess.run(
        ["git", "push", "--set-upstream", "origin", branch_name],
        cwd=working_dir,
        check=True,
    )


def fork_project(repo_name, project_id, namespace_id, gitlab_url, gitlab_token):
    already_exists = check_if_project_exists(
        repo_name, namespace_id, gitlab_url, gitlab_token
    )
    if not already_exists:
        fork_url = "{}/projects/{}/fork".format(gitlab_url, project_id)
        response = requests.post(
            fork_url,
            headers={"Authorization": "Bearer " + gitlab_token},
            data={"namespace_id": namespace_id},
        )
        if response.status_code != 201:
            raise RuntimeError("Problem creating fork: {}".format(response.content))
        new_project_id = response.json()["id"]
        return new_project_id
    else:
        # project already exists - ensure it is a fork of 'approval/<project-name>'
        new_project_id = get_project_id(
            repo_name, namespace_id, gitlab_url, gitlab_token
        )
        fork_url = "{}/projects/{}/fork/{}".format(
            gitlab_url, new_project_id, project_id
        )
        response = requests.post(
            fork_url, headers={"Authorization": "Bearer " + gitlab_token}
        )
        # status code 201 if fork relationship created, or 409 if already there
        if (response.status_code != 201) and (response.status_code != 409):
            raise RuntimeError(
                "Unable to create fork relationship: {} {}".format(
                    response.status_code, response.content
                )
            )

        return new_project_id


def unzipped_repo_to_merge_request(
    repo_details, tmp_repo_dir, gitlab_config, namespace_ids, group_names
):
    # unpack tuple
    repo_name, commit_hash, target_branch_name, unzipped_location = repo_details
    logger.info("Unpacked {} {} {}".format(repo_name, commit_hash, target_branch_name))
    # create project on approved repo if not already there - this func will do that
    target_project_id = get_project_id(
        repo_name,
        namespace_ids[group_names[1]],
        gitlab_config["api_url"],
        gitlab_config["api_token"],
    )
    logger.info("Created project {}/{} ".format(group_names[1], repo_name))

    # Branch to create on the source (unapproved) repository of the
    # matches that of the target
    src_branch_name = target_branch_name

    # Check if we already have a Merge Request - if so we can just skip to the end
    mr_exists = check_if_merge_request_exists(
        src_branch_name,
        target_project_id,
        target_branch_name,
        gitlab_config["api_url"],
        gitlab_config["api_token"],
    )
    if mr_exists:
        logger.info(
            "Merge Request for {} {} to {} already exists - skipping".format(
                repo_name, src_branch_name, target_branch_name
            )
        )
        return

    # If we got here, MR doesn't already exist - go through the rest of the steps.

    # Fork this project to "unapproved" group
    src_project_id = fork_project(
        repo_name,
        target_project_id,
        namespace_ids[group_names[0]],
        gitlab_config["api_url"],
        gitlab_config["api_token"],
    )

    logger.info("Forked to project {}/{}".format(group_names[0], repo_name))
    # Get the remote URL for the unapproved project
    remote_url = get_project_remote_url(
        repo_name,
        namespace_ids[group_names[0]],
        gitlab_config["api_url"],
        gitlab_config["api_token"],
    )

    # Do the command-line git stuff to push to unapproved project

    branch_exists = check_if_branch_exists(
        src_branch_name,
        src_project_id,
        gitlab_config["api_url"],
        gitlab_config["api_token"],
    )
    if not branch_exists:
        clone_commit_and_push(
            repo_name, unzipped_location, tmp_repo_dir, src_branch_name, remote_url, commit_hash
        )
        logger.info(
            "Pushed to {}/{} branch {}".format(
                group_names[0], repo_name, src_branch_name
            )
        )
    else:
        logger.info(
            "{}/{} branch {} already exists".format(
                group_names[0], repo_name, src_branch_name
            )
        )

    # Create the branch on the "approval" project if it doesn't already exist
    branch_exists = check_if_branch_exists(
        target_branch_name,
        target_project_id,
        gitlab_config["api_url"],
        gitlab_config["api_token"],
    )
    if not branch_exists:
        branch_info = create_branch(
            target_branch_name,
            target_project_id,
            gitlab_config["api_url"],
            gitlab_config["api_token"],
        )
        assert branch_info["name"] == target_branch_name
        logger.info(
            "{}/{} branch {} created".format(
                group_names[1], repo_name, target_branch_name
            )
        )
    else:
        logger.info(
            "{}/{} branch {} already exists".format(
                group_names[1], repo_name, target_branch_name
            )
        )

    # Create the merge request
    create_merge_request(
        repo_name,
        src_project_id,
        src_branch_name,
        target_project_id,
        target_branch_name,
        gitlab_config["api_url"],
        gitlab_config["api_token"],
    )
    logger.info(
        "Created merge request {} -> {}".format(commit_hash, target_branch_name)
    )

    return True


def cleanup(zipfile_dir, tmp_unzipped_dir, tmp_repo_dir):
    logger.info(" === cleaning up ======")
    shutil.rmtree(tmp_unzipped_dir, ignore_errors=True)
    logger.info("Removed directory {}".format(tmp_unzipped_dir))
    shutil.rmtree(tmp_repo_dir, ignore_errors=True)
    logger.info("Removed directory {}".format(tmp_repo_dir))
    try:
        for filename in os.listdir(zipfile_dir):
            filepath = os.path.join(zipfile_dir, filename)
            subprocess.run(["rm", "-f", filepath], check=True)
            logger.info("Removed file {}".format(filepath))
    except (FileNotFoundError):
        logger.info("Zipfile directory {} not found - skipping".format(zipfile_dir))
    return True


def main():
    ZIPFILE_DIR = "/tmp/zipfiles"
    os.makedirs(ZIPFILE_DIR, exist_ok=True)
    # create a directory to unpack the zipfiles into
    TMP_UNZIPPED_DIR = "/tmp/unzipped"
    shutil.rmtree(TMP_UNZIPPED_DIR, ignore_errors=True)
    os.makedirs(TMP_UNZIPPED_DIR)
    # and a directory where we will clone projects, then copy file contents in
    TMP_REPO_DIR = "/tmp/repos"
    shutil.rmtree(TMP_REPO_DIR, ignore_errors=True)
    os.makedirs(TMP_REPO_DIR)

    # get the gitlab config
    config = get_gitlab_config()

    # unzip the zipfiles, and retrieve a list of tuples describing
    # (repo_name, commit_hash, desired_branch, unzipped_location)
    unzipped_repos = unzip_zipfiles(ZIPFILE_DIR, TMP_UNZIPPED_DIR)

    # get the namespace_ids of our "approval" and "unapproved" groups
    GROUPS = ["unapproved", "approval"]
    namespace_ids = get_group_namespace_ids(
        config["api_url"], config["api_token"], GROUPS
    )

    # loop over all our newly unzipped repositories
    for repo_details in unzipped_repos:
        # call function to go through all the project/branch/mr creation etc.
        unzipped_repo_to_merge_request(
            repo_details, TMP_REPO_DIR, config, namespace_ids, GROUPS
        )

    # cleanup
    cleanup(ZIPFILE_DIR, TMP_UNZIPPED_DIR, TMP_REPO_DIR)


if __name__ == "__main__":
    main()
