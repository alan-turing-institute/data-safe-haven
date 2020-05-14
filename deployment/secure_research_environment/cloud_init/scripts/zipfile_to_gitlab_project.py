#!/usr/bin/env python3

"""
Start from zipfile of a particular commit - should have filename
of the form <repo-name>_<commit-hash>_<desired_branch_name>.zip

We want to turn this into a merge request on a Gitlab project.

1) get useful gitlab stuff (url, api key, namespace_ids for our groups)
2) unzip zipfiles in specified directory
3) loop over unzipped repos. For each one:
  a) see if "approval" project with same name exists, if not, create it, and branch "<desired_branch_name>"
  b) check if merge request to "approval/<repo_name>" with source and target branches
     "commit-<commit-hash>" and "<desired_branch_name>" already exists.
      If so, skip to the next unzipped repo.
  b) see if "unapproved" project with same name exists, if not, fork "approval" one
  c) clone "unapproved" project, and create branch called "commit-<commit_hash>"
  d) copy in contents of unzipped repo.
  e) git add, commit and push to "unapproved" project
  f) create merge request from unapproved/repo_name/commit_hash to
     approval/repo_name/desired_branch_name
4) clean up - remove zipfiles and unpacked repos.
"""


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
    """
    Parameters
    ==========
    zipfile_dir: str, path to directory containing zipfiles
    tmp_unzipped_dir: str, path to directory where zipfiles will be unzipped

    Returns
    =======
    output_list: list of tuples
           [(repo_name, commit_hash, desired_branch, unzipped-path),...]

    Note that the convention for the zipfile filenames is
    <repo-name>_<commit_hash>_<desired_branch_name>.zip
    """
    output_list = []
    repo_commit_regex = re.compile("([-\w]+)_([a-f\d]+)_([\S]+).zip")
    # tear down and recreate the directory where we will put the unpacked zip
    shutil.rmtree(tmp_unzipped_dir, ignore_errors=True)
    os.makedirs(tmp_unzipped_dir)
    # look in a directory for zipfiles
    zipfiles = os.listdir(zipfile_dir)
    for zipfile in zipfiles:
        filename_match = repo_commit_regex.search(zipfile)
        if not filename_match:
            logger.info("Badly named zipfile! {}".format(zipfile))
            continue
        repo_name, commit_hash, branch = filename_match.groups()

        # unzip
        try:
            zipfile_path = os.path.join(zipfile_dir, zipfile)
            with ZipFile(zipfile_path, 'r') as zip_obj:
                zip_obj.extractall(path=tmp_unzipped_dir)
            # we should have made a new directory - find its name
            unpacked_zips = os.listdir(tmp_unzipped_dir)
            unpacked_location = os.path.join(tmp_unzipped_dir, unpacked_zips[0])
            output_list.append((repo_name, commit_hash, branch, unpacked_location))
        except(BadZipFile):
            logger.info("Bad zipfile: {}".format(zipfile))
            continue
    return output_list


def get_gitlab_config():
    """
    Return a dictionary containing the base URL for the gitlab API,
    the API token, the IP address, and the headers to go in any request
    """
    home = str(Path.home())

    with open(f"{home}/.secrets/gitlab-external-ip-address", "r") as f:
        ip = f.readlines()[0].strip()

    with open(f"{home}/.secrets/gitlab-external-api-token", "r") as f:
        token = f.readlines()[0].strip()
    api_url = f"http://{ip}/api/v4/"
    headers = {"Authorization": "Bearer " + token}

    return {"api_url": api_url,
            "api_token": token,
            "ip": ip,
            "headers": headers}


def get_group_namespace_ids(gitlab_url, gitlab_token,
                            groups=["approval","unapproved"]):
    """
    Find the namespace_id corresponding to the groups we're interested in,
    e.g. 'approval' and 'unapproved'.

    Parameters
    ==========
    gitlab_url: str, base URL for the API
    gitlab_token: str, API token for Gitlab
    groups: list of string, the group names to look for.

    Returns
    =======
    namespace_id_dict: dict, format {<group_name:str>: <namespace_id:int>}

    """
    namespaces_url = "{}/namespaces/".format(gitlab_url)
    response = requests.get(namespaces_url,
                            headers = {"Authorization": "Bearer "+gitlab_token})
    if response.status_code != 200:
        raise RuntimeError("Bad request: {} {}"\
                           .format(response.status_code, response.content))
    gitlab_namespaces = response.json()
    namespace_id_dict = {}
    for namespace in gitlab_namespaces:
        if namespace["kind"] == "group" and namespace["name"] in groups:
            namespace_id_dict[namespace["name"]] = namespace["id"]
    return namespace_id_dict


def get_gitlab_project_list(gitlab_url, gitlab_token):
    """
    Get the list of Projects.

    Parameters
    ==========
    namespace_id: int, ID of the group ("unapproved" or "approval")
    gitlab_url: str, base URL for the API
    gitlab_token: str, API token.

    Returns
    =======
    gitlab_projects: list of dictionaries.
    """

    # list currently existing projects on Gitlab
    projects_url = "{}/projects/".format(gitlab_url)
    response = requests.get(projects_url,
                            headers = {"Authorization": "Bearer "+gitlab_token},
                            params = {"owned": True, "simple": True})

    if response.status_code != 200:
        raise RuntimeError("Bad request: {} {}"\
                           .format(response.status_code, response.content))
    gitlab_projects = response.json()
    return gitlab_projects


def check_if_project_exists(repo_name, namespace_id, gitlab_url, gitlab_token):
    """
    Get a list of projects from the API - check if namespace_id (i.e. group)
    and name match.

    Parameters
    ==========
    repo_name: str, name of our repository/project
    namespace_id: int, id of our group ("unapproved" or "approval")
    gitlab_url: str, base URL of Gitlab API
    gitlab_token: str, API key for Gitlab API.

    Returns
    =======
    bool, True if project exists, False otherwise.
    """
    projects = get_gitlab_project_list(gitlab_url, gitlab_token)
    for project in projects:
        if project["name"] == repo_name and \
           project["namespace"]["id"] == namespace_id:
            return True
    return False


def get_project_info(repo_name, namespace_id, gitlab_url, gitlab_token):
    """
    Check if project exists, and if so get its ID.  Otherwise, create
    it and return the ID.

    Parameters
    ==========
    repo_name: str, name of our repository/project
    namespace_id: int, id of our group ("unapproved" or "approval")
    gitlab_url: str, base URL of Gitlab API
    gitlab_token: str, API key for Gitlab API.

    Returns
    =======
    project_info: dict, containing info from the projects API endpoint
    """
    already_exists = check_if_project_exists(repo_name,
                                             namespace_id,
                                             gitlab_url,
                                             gitlab_token)
    if already_exists:
        projects = get_gitlab_project_list(gitlab_url, gitlab_token)
        for project_info in projects:
            if project_info["name"] == repo_name and \
               project_info["namespace"]["id"] == namespace_id:
                return project_info
    else:
        project_info = create_project(repo_name,
                                      namespace_id,
                                      gitlab_url,
                                      gitlab_token)
        return project_info


def get_project_remote_url(repo_name, namespace_id,
                          gitlab_url, gitlab_token):
    """
    Given the name of a repository and  namespace_id (i.e. group,
    "unapproved" or "approval"), either return the remote URL for project
    matching the repo name, or create it if it doesn't exist already,
    and again return the remote URL.

    Parameters
    ==========
    repo_name: str, name of the repository/project we're looking for.
    namespace_id: int, the ID of the group ("unapproved" or "approval")
    gitlab_url: str, base URL of the API
    gitlab_token: str, API key

    Returns
    =======
    gitlab_project_url: str, the URL to be set as the "remote".
    """
    project_info = get_project_info(repo_name, namespace_id,
                                    gitlab_url, gitlab_token)

    return project_info["ssh_url_to_repo"]


def get_project_id(repo_name, namespace_id,
                          gitlab_url, gitlab_token):
    """
    Given the name of a repository and  namespace_id (i.e. group,
    "unapproved" or "approval"), either return the id of project
    matching the repo name, or create it if it doesn't exist already,
    and again return the id.

    Parameters
    ==========
    repo_name: str, name of the repository/project we're looking for.
    namespace_id: int, the ID of the group ("unapproved" or "approval")
    gitlab_url: str, base URL of the API
    gitlab_token: str, API key

    Returns
    =======
    gitlab_project_url: str, the URL to be set as the "remote".
    """
    project_info = get_project_info(repo_name, namespace_id,
                                    gitlab_url, gitlab_token)

    return project_info["id"]


def create_project(repo_name, namespace_id, gitlab_url, gitlab_token):
    """
    Create empty project on gitlab, and return the corresponding remote URL.

    Parameters
    ==========
    repo_name: str, name of the repository/project
    namespace_id: int, ID of the group ("unapproved" or "approved")
    gitlab_url: str, base URL of the API
    gitlab_token: str, API token.

    Returns
    =======
    gitlab_project_info: dict, containing among other things, the name and
                        the remote URL for the project.
    """
    projects_url = "{}projects/".format(gitlab_url)
    response = requests.post(projects_url,
                             headers = {"Authorization": "Bearer "+gitlab_token},
                             data = {"name": repo_name,
                                     "visibility": "public",
                                     "namespace_id": namespace_id}
    )
    assert(response.json()["name"] == repo_name)
    project_info = response.json()
    logger.info("Created project {} in namespace {}, project_id {}".\
          format(repo_name, namespace_id, project_info["id"]))
    return project_info


def check_if_branch_exists(branch_name,
                           project_id,
                           gitlab_url,
                           gitlab_token):
    """
    See if a branch with name branch_name already exists on this Project

    Parameters
    ==========
    branch_name: str, name of branch to look for
    project_id: int, id of the project, obtained from projects API endpoint
    gitlab_url: base URL of the Gitlab API
    gitlab_token: API token for the Gitlab API

    Returns
    =======
    branch_exists: bool, True if branch exists, False if not.
    """
    branches_url = "{}/projects/{}/repository/branches".\
        format(gitlab_url, project_id)
    response = requests.get(branches_url,
                            headers={"Authorization": "Bearer "+gitlab_token})
    if response.status_code != 200:
        raise RuntimeError("Unable to check for branch {} on project {}: {}".\
                           format(branch_name, project_id, r.content))
    branches = response.json()
    for branch_info in branches:
        if branch_info["name"] == branch_name:
            return True
    return False



def create_branch(branch_name,
                  project_id,
                  gitlab_url,
                  gitlab_token,
                  reference_branch="master"):
    """
    Create a new branch on an existing project.  By default, use 'master'
    as the reference branch from which to create the new one.

    Parameters
    ==========
    branch_name: str, the desired name of the new branch
    project_id: int, the ID of the project, which is the "id" value in
                 the dictionary of project information returned when
                 creating a new project or listing existing ones.
    gitlab_url: str, the base URL for the Gitlab API
    gitlab_token: str, the Gitlab API token

    Returns
    =======
    branch_info: dict, info about the branch from API endpoint
    """
    # assume branch doesn't already exist - create it!
    branch_url = "{}/projects/{}/repository/branches".format(gitlab_url, project_id)
    response = requests.post(branch_url,
                             headers = {"Authorization": "Bearer "+gitlab_token},
                             data = {"branch": branch_name, "ref": reference_branch})
    if response.status_code != 201:
        raise RuntimeError("Problem creating branch {}: {}".format(branch_name,
                                                                   response.content))
    branch_info = response.json()
    assert branch_info["name"] == branch_name
    return branch_info


def check_if_merge_request_exists(source_branch,
                                  target_project_id,
                                  target_branch,
                                  gitlab_url, gitlab_token):
    """
    See if there is an existing merge request between the source and target
    project/branch combinations.

    Parameters
    ==========
    source_branch: str, name of the branch on source project, will typically
                      be the commit_hash from the original repo.
    target_project_id: int, project_id for the "approval" group's project.
    target_branch: str, name of branch on target project, will typically
                      be the desired branch name.
    gitlab_url: str, base URL for the Gitlab API
    gitlab_token: str, API token for the Gitlab API.

    Returns
    =======
    bool, True if merge request already exists, False otherwise
    """
    mr_url = "{}/projects/{}/merge_requests".format(gitlab_url, target_project_id)
    response = requests.get(mr_url,
                            headers = {"Authorization": "Bearer "+gitlab_token})
    if response.status_code != 200:
        raise RuntimeError("Request to check existence of MR failed: {} {}".\
                           format(response.status_code, response.content))
    for mr in response.json():
        if mr["source_branch"] == source_branch and \
           mr["target_branch"] == target_branch:
            logger.info("Merge request {} -> {} already exists".\
                  format(source_branch, target_branch))
            return True
    return False


def create_merge_request(repo_name,
                         source_project_id,
                         source_branch,
                         target_project_id,
                         target_branch,
                         gitlab_url, gitlab_token):

    """
    Create a new MR, e.g. from the branch <commit_hash> in the "unapproved"
    group's project, to the branch <desired_branch_name> in the "approval"
    group's project.

    Parameters
    ==========
    repo_name: str, name of the repository
    source_project_id: int, project_id for the unapproved project, obtainable
                         as the "ID" field of the json returned from the
                         projects API endpoint.
    source_branch: str, name of the branch on source project, will typically
                      be the 'branch-<commit-hash-from-the-original-repo>'.
    target_project_id: int, project_id for the "approval" group's project.
    target_branch: str, name of branch on target project, will typically
                      be the desired branch name.
    gitlab_url: str, base URL for the Gitlab API
    gitlab_token: str, API token for the Gitlab API.

    Returns
    =======
    mr_info: dict, the response from the API upon creating the Merge Request
    """
    # first need to create a forked-from relationship between the projects
    fork_url = "{}/projects/{}/fork/{}".format(gitlab_url,
                                               source_project_id,
                                               target_project_id)
    response = requests.post(fork_url,
                             headers = {"Authorization": "Bearer "+gitlab_token})
    # status code 201 if fork relationship created, or 409 if already there
    if (response.status_code != 201) and (response.status_code != 409):
        raise RuntimeError("Unable to create fork relationship: {} {}".\
                           format(response.status_code, response.content))

    mr_url = "{}/projects/{}/merge_requests".format(gitlab_url, source_project_id)
    title = "{}: {} to {}".format(repo_name, source_branch, target_branch)
    response = requests.post(mr_url,
                             headers = {"Authorization": "Bearer "+gitlab_token},
                             data = {"source_branch": source_branch,
                                     "target_branch": target_branch,
                                     "target_project_id": target_project_id,
                                     "title": title})
    if response.status_code != 201:
#        raise RuntimeError("Problem creating Merge Request {} {} {}: {}"\
#                           .format(repo_name, source_branch,target_branch,
#                                   response.content))
##### TEMPORARY - don't raise an error here - we get 500 status code
##### even though MR is created it - under investigation.
        logger.info("Problem creating Merge Request {} {} {}: {}"\
              .format(repo_name, source_branch,target_branch,
                      response.content))
        return {}
    mr_info = response.json()
    return mr_info


def clone_commit_and_push(repo_name, path_to_unzipped_repo, tmp_repo_dir, branch_name, remote_url):
    """
    Run shell commands to convert the unzipped directory containing the
    repository contents into a git repo, then commit it to a branch named
    as the commit_hash.

    Parameters
    ==========
    repo_name: str, name of the repository/project
    path_to_unzipped_repo: str, the full directory path to the unzipped repo
    tmp_repo_dir: str, path to a temporary dir where we will clone the project
    branch_name: str, original commit hash from the external git repo, will
                  be used as the name of the branch to push to
    remote_url: str, the URL for this project on gitlab-external to be added
                  as a "remote".
    """
    # Clone the repo
    subprocess.run(["git","clone",remote_url],cwd=tmp_repo_dir, check=True)
    working_dir = os.path.join(tmp_repo_dir, repo_name)
    assert os.path.exists(working_dir)
    # Copy the unzipped repo contents into our cloned (empty) repo
    for item in os.listdir(path_to_unzipped_repo):
        subprocess.run(["cp","-r",os.path.join(path_to_unzipped_repo,item),"."],
                       cwd=working_dir, check=True)
    # Create a branch named after the original commit hash
    subprocess.run(["git","checkout","-b",branch_name],
                   cwd=working_dir, check=True)
    # Commit everything to this branch, also putting commit hash into message
    subprocess.run(["git","add","."], cwd=working_dir, check=True)
    commit_msg = "Committing to branch {}".format(branch_name)
    subprocess.run(["git","commit","-m", commit_msg],
                   cwd=working_dir, check=True)
    # Push back to gitlab external
    subprocess.run(["git","push","--set-upstream","origin",branch_name],
                   cwd=working_dir, check=True)


def fork_project(repo_name, project_id, namespace_id,
                               gitlab_url, gitlab_token):
    """
    Fork the project 'approval/<project-name>' to 'unapproved/<project-name>'
    after first checking whether the latter exists.

    Parameters
    ==========
    repo_name: str, name of the repo/project
    project_id: int, project id of the 'approval/<project-name>' project
    namespace_id: int, id of the 'unapproved' namespace
    gitlab_url: str, str, the base URL of Gitlab API
    gitlab_token: str, API token for Gitlab API

    Returns
    =======
    new_project_id: int, the id of the newly created 'unapproved/<project-name>' project
    """
    already_exists = check_if_project_exists(repo_name, namespace_id, gitlab_url, gitlab_token)
    if not already_exists:
        fork_url = "{}/projects/{}/fork".format(gitlab_url, project_id)
        response = requests.post(fork_url,
                             headers = {"Authorization": "Bearer "+gitlab_token},
                             data = {"namespace_id": namespace_id})
        if response.status_code != 201:
            raise RuntimeError("Problem creating fork: {}".format(response.content))
        new_project_id = response.json()["id"]
        return new_project_id
    else:
        # project already exists - ensure it is a fork of 'approval/<project-name>'
        new_project_id = get_project_id(repo_name, namespace_id,
                                        gitlab_url, gitlab_token)
        fork_url = "{}/projects/{}/fork/{}".format(gitlab_url,
                                                   new_project_id,
                                                   project_id)
        response = requests.post(fork_url,
                                 headers = {"Authorization": "Bearer "+gitlab_token})
        # status code 201 if fork relationship created, or 409 if already there
        if (response.status_code != 201) and (response.status_code != 409):
            raise RuntimeError("Unable to create fork relationship: {} {}".\
                               format(response.status_code, response.content))

        return new_project_id



def create_project_and_branch(repo_name,
                              branch_name,
                              namespace_id,
                              gitlab_url,
                              gitlab_token):

    """
    Create a new branch (and a new project if it doesn't already exist)
    owned by the "approval" group.  This will be the target for the merge
    request.

    Parameters
    ==========
    repo_name: str, repository name
    gitlab_url: str, base URL for Gitlab API
    gitlab_token: str, API token for Gitlab API
    branch_name: str, the desired branch name.

    Returns
    =======
    project_id: int, the "ID" field in the info from projects API endpoint
    """
    # get the project ID - project will be created if it doesn't already exist
    project_id = get_project_id(repo_name, namespace_id, gitlab_url, gitlab_token)
    assert project_id

    # create the branch if it doesn't already exist
    branch_exists = check_if_branch_exists(branch_name,
                                           project_id,
                                           gitlab_url,
                                           gitlab_token)
    if not branch_exists:
        branch_info = create_branch(branch_name,
                                    project_id,
                                    gitlab_url,
                                    gitlab_token)
        assert branch_info["name"] == branch_name
    # return the ID of this project so we can use it in merge request
    return project_id


def unzipped_repo_to_merge_request(repo_details,
                                   tmp_repo_dir,
                                   gitlab_config,
                                   namespace_ids,
                                   group_names):
    """
    Go through all the steps for a single repo/project.

    Parameters
    ==========
    repo_details: tuple of strings, (repo_name, hash, desired_branch, location)
    tmp_repo_dir: str, directory where we will clone the repo, then copy the contents in
    gitlab_config: dict, contains api url and token
    namespace_ids; dict, keys are the group names (e.g. "unapproved", "approval", values
                        are the ids of the corresponding namespaces in Gitlab
    group_names: list of strings, typically ["unapproved", "approval"]
    """

    # unpack tuple
    repo_name, commit_hash, branch_name, unzipped_location = repo_details
    logger.info("Unpacked {} {} {}".format(repo_name, commit_hash, branch_name))
    # create project and branch on approved repo
    target_project_id = create_project_and_branch(repo_name,
                                                  branch_name,
                                                  namespace_ids[group_names[1]],
                                                  gitlab_config["api_url"],
                                                  gitlab_config["api_token"])
    logger.info("Created project {}/{} branch {}".\
          format(group_names[1],repo_name, branch_name))

    # Check if we already have a Merge Request - if so we can just skip to the end
    unapproved_branch_name = "branch-{}".format(commit_hash)
    mr_exists = check_if_merge_request_exists(unapproved_branch_name,
                                              target_project_id,
                                              branch_name,
                                              gitlab_config["api_url"],
                                              gitlab_config["api_token"])
    if mr_exists:
        logger.info("Merge Request for {} {} to {} already exists - skipping".\
                    format(repo_name,
                           unapproved_branch_name,
                           target_branch))
        return

    # If we got here, MR doesn't already exist - go through the rest of the steps.

    # Fork this project to "unapproved" group
    src_project_id = fork_project(repo_name,
                                  target_project_id,
                                  namespace_ids[group_names[0]],
                                  gitlab_config["api_url"],
                                  gitlab_config["api_token"])

    logger.info("Forked to project {}/{}".\
          format(group_names[0],repo_name))
    # Get the remote URL for the unapproved project
    remote_url = get_project_remote_url(repo_name,
                                        namespace_ids[group_names[0]],
                                        gitlab_config["api_url"],
                                        gitlab_config["api_token"])

    # Do the command-line git stuff to push to unapproved project
    clone_commit_and_push(repo_name,
                          unzipped_location,
                          tmp_repo_dir,
                          unapproved_branch_name,
                          remote_url)
    logger.info("Pushed to {}/{} branch {}".format(group_names[0],repo_name, unapproved_branch_name))

    # Create the merge request

    create_merge_request(repo_name,
                         src_project_id,
                         unapproved_branch_name,
                         target_project_id,
                         branch_name,
                         gitlab_config["api_url"],
                         gitlab_config["api_token"])
    logger.info("Created merge request {} -> {}".\
          format(commit_hash, branch_name))

    return True


def cleanup(zipfile_dir, tmp_unzipped_dir, tmp_repo_dir):
    """
    Remove directories and files after everything has been uploaded to gitlab

    Parameters
    ==========
    zipfile_dir: str, directory containing the original zipfiles.  Will not remove this
                      directory, but we will delete all the zipfiles in it.
    tmp_unzipped_dir: str, directory where the unpacked zipfile contents are put. Remove.
    tmp_repo_dir: str, directory where projects are cloned from Gitlab, then contents from
                       tmp_unzipped_dir are copied in.  Remove.
    """
    logger.info(" === cleaning up ======")
    shutil.rmtree(tmp_unzipped_dir)
    logger.info("Removed directory {}".format(tmp_unzipped_dir))
    shutil.rmtree(tmp_repo_dir)
    logger.info("Removed directory {}".format(tmp_repo_dir))
    for filename in os.listdir(zipfile_dir):
        filepath = os.path.join(zipfile_dir, filename)
        subprocess.run(["rm",filepath], check=True)
        logger.info("Removed file {}".format(filepath))
    return True


def main():

    ZIPFILE_DIR = "/zfiles"
    # create a directory to unpack the zipfiles into
    TMP_UNZIPPED_DIR = "/tmp/unzipped"
    os.makedirs(TMP_UNZIPPED_DIR, exist_ok=True)
    # and a directory where we will clone projects, then copy file contents in
    TMP_REPO_DIR = "/tmp/repos"
    os.makedirs(TMP_REPO_DIR, exist_ok=True)
    # get the gitlab config
    config = get_gitlab_config()

    # unzip the zipfiles, and retrieve a list of tuples describing
    # (repo_name, commit_hash, desired_branch, unzipped_location)
    unzipped_repos = unzip_zipfiles(ZIPFILE_DIR, TMP_UNZIPPED_DIR)

    # get the namespace_ids of our "approval" and "unapproved" groups
    GROUPS = ["unapproved","approval"]
    namespace_ids = get_group_namespace_ids(config["api_url"],
                                            config["api_token"],
                                            GROUPS)

    # loop over all our newly unzipped repositories
    for repo_details in unzipped_repos:
        # call function to go through all the project/branch/mr creation etc.
        unzipped_repo_to_merge_request(repo_details,
                                       TMP_REPO_DIR,
                                       config,
                                       namespace_ids,
                                       GROUPS)

    # cleanup
    cleanup(ZIPFILE_DIR, TMP_UNZIPPED_DIR, TMP_REPO_DIR)


if __name__ == "__main__":
    main()
