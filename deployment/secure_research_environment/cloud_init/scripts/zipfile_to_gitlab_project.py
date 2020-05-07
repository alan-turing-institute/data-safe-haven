#!/usr/bin/env python3

"""
Start from zipfile of a particular commit - should have filename
of the form <repo-name>_<commit-hash>_<desired_branch_name>.zip

We want to turn this into a merge request on a Gitlab project.

1) get useful gitlab stuff (url, api key, namespace_ids for our groups)
2) unzip zipfiles in specified directory
3) loop over unzipped repos. For each one:
  a) see if "unapproved" project with same name exists, if not, create it
  b) commit and push to "unapproved" project, branch=commit_hash
  c) see "approval" project with same name exists, if not, create it
  d) create branch=desired_branch_name on "approval" project
  e) create merge request from unapproved/repo_name/commit_hash to
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


def unzip_zipfiles(zipfile_dir, tmp_repo_dir):
    """
    Parameters
    ==========
    zipfile_dir: str, path to directory containing zipfiles
    tmp_repo_dir: str, path to directory where zipfiles will be unzipped

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
    shutil.rmtree(tmp_repo_dir, ignore_errors=True)
    os.makedirs(tmp_repo_dir)
    # look in a directory for zipfiles
    zipfiles = os.listdir(zipfile_dir)
    for zipfile in zipfiles:
        filename_match = repo_commit_regex.search(zipfile)
        if not filename_match:
            print("Badly named zipfile! {}".format(zipfile))
            continue
        repo_name, commit_hash, branch = filename_match.groups()

        # unzip
        try:
            zipfile_path = os.path.join(zipfile_dir, zipfile)
            with ZipFile(zipfile_path, 'r') as zip_obj:
                zip_obj.extractall(path=tmp_repo_dir)
            # we should have made a new directory - find its name
            unpacked_zips = os.listdir(tmp_repo_dir)
            # should be one and only one directory in here
            if len(unpacked_zips) != 1:
                raise RuntimeError("Unexpected number of items in unpacked zip directory {}: {}".format(tmp_repo_dir, unpacked_zips))
            unpacked_location = os.path.join(tmp_repo_dir, unpacked_zips[0])
            output_list.append((repo_name, commit_hash, branch, unpacked_location))
        except(BadZipFile):
            print("Bad zipfile: {}".format(zipfile))
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
    print("Created project {} in namespace {}, project_id {}".\
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


def check_if_merge_request_exists(repo_name,
                                  source_project_id,
                                  source_branch,
                                  target_project_id,
                                  target_branch,
                                  gitlab_url, gitlab_token):
    """
    See if there is an existing merge request between the source and target
    project/branch combinations.

    Parameters
    ==========
    repo_name: str, name of the repository
    source_project_id: int, project_id for the unapproved project, obtainable
                         as the "ID" field of the json returned from the
                         projects API endpoint.
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
    mr_url = "{}/projects/{}/merge_requests".format(gitlab_url, source_project_id)
    response = requests.get(mr_url,
                            headers = {"Authorization": "Bearer "+gitlab_token})
    if response.status_code != 200:
        raise RuntimeError("Request to check existence of MR failed: {} {}".\
                           format(response.status_code, response.content))
    for mr in response.json():
        if mr["source_branch"] == source_branch and \
           mr["target_branch"] == target_branch:
            print("Merge request {} -> {} already exists".\
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
                      be the commit_hash from the original repo.
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
        raise RuntimeError("Problem creating Merge Request {} {} {}: {}"\
                           .format(repo_name, source_branch,target_branch,
                                   response.content))
    mr_info = response.json()
    return mr_info





def push_to_remote(path_to_unzipped_repo, commit_hash, remote_url):
    """
    Run shell commands to convert the unzipped directory containing the
    repository contents into a git repo, then commit it to a branch named
    as the commit_hash.

    Parameters
    ==========
    path_to_unzipped_repo: str, the full directory path to the unzipped repo
    commit_hash: str, original commit hash from the external git repo, will
                  be used as the name of the branch to push to
    remote_url: str, the URL for this project on gitlab-external to be added
                  as a "remote".
    """
    subprocess.run(["git","init"], cwd=path_to_unzipped_repo, check=True)
    # Create a branch named after the original commit hash
    subprocess.run(["git","checkout","-b",commit_hash],
                   cwd=path_to_unzipped_repo, check=True)
    # Commit everything to this branch, also putting commit hash into message
    subprocess.run(["git","add","."], cwd=path_to_unzipped_repo, check=True)
    subprocess.run(["git","commit","-m",commit_hash],
                   cwd=path_to_unzipped_repo, check=True)
    # add the remote_url as a remote called 'gitlab-external'
    subprocess.run(["git","remote","add","gitlab-external",remote_url],
                    cwd=path_to_unzipped_repo, check=True)
    # Push to gitlab external
    subprocess.run(["git","push","--force","--all","gitlab-external"],
                   cwd=path_to_unzipped_repo, check=True)


def create_and_push_unapproved_project(repo_name,
                                       namespace_id,
                                       gitlab_url,
                                       gitlab_token,
                                       path_to_unzipped_repo,
                                       commit_hash):
    """
    We have unzipped a zipfile, and put the contents (i.e. the code we want
    to push) in path_to_unzipped_project.
    Now we create the project in the "unapproved" group on Gitlab, and push
    to it.

    Parameters
    ==========
    repo_name: str, name of our repository/project
    gitlab_url: str, the base URL of Gitlab API
    gitlab_token: str, API token for Gitlab API
    path_to_unzipped_repo: str, full directory path to code we want to commit
    commit_hash: str, the commit hash from the original repo, to be used as
                    the name of the branch we'll push to

    Returns
    =======
    project_id: int, ID of the project as returned by projects API endpoint
    """
    # Get project ID - project will be created if it didn't already exist
    project_id = get_project_id(repo_name, namespace_id, gitlab_url, gitlab_token)
    assert project_id
    # see if branch already exists with name=commit_hash
    branch_exists = check_if_branch_exists(commit_hash,
                                           project_id,
                                           gitlab_url,
                                           gitlab_token)
    if branch_exists:
        print("Branch {} already exists".format(commit_hash))
        # already exists - do nothing
        return project_id
    # otherwise we need to commit code to it and push
    remote_url = get_project_remote_url(repo_name, namespace_id,
                                        gitlab_url, gitlab_token)
    print("remote URL for {} is {}".format(repo_name, remote_url))

    push_to_remote(path_to_unzipped_repo, commit_hash, remote_url)
    # Return the project_id, to use in merge request
    return project_id


def create_approved_project_branch(repo_name,
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


def main():
    # create a directory to unpack the zipfiles into
    TMP_REPO_DIR = "/tmp/repos"
    os.makedirs(TMP_REPO_DIR, exist_ok=True)
    # get the gitlab config
    config = get_gitlab_config()
    ZIPFILE_DIR = "/zfiles"

    # unzip the zipfiles, and retrieve a list of tuples describing
    # (repo_name, commit_hash, desired_branch, unzipped_location)
    unzipped_repos = unzip_zipfiles(ZIPFILE_DIR, TMP_REPO_DIR)

    # get the namespace_ids of our "approval" and "unapproved" groups
    GROUPS = ["unapproved","approval"]
    namespace_ids = get_group_namespace_ids(config["api_url"],
                                            config["api_token"],
                                            GROUPS)

    # loop over all our newly unzipped repositories
    for repo in unzipped_repos:
        # unpack tuple
        repo_name, commit_hash, branch_name, location = repo
        print("Unpacked {} {} {}".format(repo_name, commit_hash, branch_name))
        src_project_id = create_and_push_unapproved_project(repo_name,
                                                            namespace_ids[GROUPS[0]],
                                                            config["api_url"],
                                                            config["api_token"],
                                                            location,
                                                            commit_hash)
        print("Created project {}/{} branch {}".\
              format(GROUPS[0],repo_name, commit_hash))

        # create project and branch on approved repo
        target_project_id = create_approved_project_branch(repo_name,
                                                           branch_name,
                                                           namespace_ids[GROUPS[1]],
                                                           config["api_url"],
                                                           config["api_token"])
        print("Created project {}/{} branch {}".\
              format(GROUPS[1],repo_name, branch_name))

        mr_exists = check_if_merge_request_exists(repo_name,
                                                  src_project_id,
                                                  commit_hash,
                                                  target_project_id,
                                                  branch_name,
                                                  config["api_url"],
                                                  config["api_token"])
        if mr_exists:
            print("Merge request {} -> {} already exists. skipping".\
                  format(commit_hash, branch_name))
        else:
            # create merge request
            create_merge_request(repo_name,
                                 src_project_id,
                                 commit_hash,
                                 target_project_id,
                                 branch_name,
                                 config["api_url"],
                             config["api_token"])
            print("Created merge request {} -> {}".\
                  format(commit_hash, branch_name))

if __name__ == "__main__":
    main()
