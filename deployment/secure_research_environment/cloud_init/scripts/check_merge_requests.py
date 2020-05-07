import requests
import subprocess
from urllib.parse import quote as url_quote
from pathlib import Path
import logging
from logging.handlers import RotatingFileHandler

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

global HOME
global GL_INTERNAL_IP
global GL_INTERNAL_TOKEN
global GL_INTERNAL_AUTH_HEADER

HOME = str(Path.home())

with open(f"{HOME}/.secrets/gitlab-internal-ip-address", "r") as f:
    GL_INTERNAL_IP = f.readlines()[0].strip()

GL_INTERNAL_URL = "http://" + GL_INTERNAL_IP + "/api/v4"

with open(f"{HOME}/.secrets/gitlab-internal-api-token", "r") as f:
    GL_INTERNAL_TOKEN = f.readlines()[0].strip()

GL_INTERNAL_AUTH_HEADER = {"Authorization": "Bearer " + GL_INTERNAL_TOKEN}


def internal_project_exists(repo_name):
    """Given a string (the name of a repo - not a URL), returns a pair
    (exists, url):
    - exists: boolean - does repo_name exist on GITLAB-INTERNAL?
    - url: str - the ssh url to the repo (when 'exists' is true)
    """

    # build url-encoded repo_name
    repo_path_encoded = url_quote("ingress/" + repo_name, safe='')

    # Does repo_name exist on GITLAB-INTERNAL?
    response = requests.get(GL_INTERNAL_URL + '/projects/' + repo_path_encoded,
                            headers=GL_INTERNAL_AUTH_HEADER)

    if response.status_code == 404:
        return (False, "")
    elif response.status_code == 200:
        return (True, response.json()["ssh_url_to_repo"])
    else:
        # Not using `response.raise_for_status()`, since we also want
        # to raise an exception on unexpected "successful" responses
        # (not 200)
        raise requests.HTTPError("Unexpected response: " + response.reason
                                 + ", content: " + response.text)


def internal_update_repo(gh_url, repo_name):
    """Takes a GitHub URL, `gh_url`, which should be the URL to the
    "APPROVED" repo, clones it and pushes all branches to the repo
    `repo_name` owned by 'ingress' on GITLAB-INTERNAL, creating it
    there first if it doesn't exist.
    """
    # clone the repo from gh_url (on GITLAB-EXTERNAL), removing any of
    # the same name first (simpler than checking if it exists, has the
    # same remote and pulling)
    subprocess.run(["rm", "-rf", repo_name], check=True)
    subprocess.run(["git", "clone", gh_url, repo_name], check=True)

    project_exists, gl_internal_repo_url = internal_project_exists(repo_name)

    # create the project if it doesn't exist
    if not project_exists:
        print("Creating: " + repo_name)
        response = requests.post(GL_INTERNAL_URL + '/projects',
                                 headers=GL_INTERNAL_AUTH_HEADER,
                                 data={"name": repo_name,
                                       "visibility": "public"})
        response.raise_for_status()
        assert(response.json()["path_with_namespace"] == "ingress/" + repo_name)

        gl_internal_repo_url = response.json()["ssh_url_to_repo"]

    # Set the remote
    subprocess.run(["git", "remote", "add", "gitlab-internal",
                    gl_internal_repo_url], cwd=repo_name, check=True)

    # Force push current contents of all branches
    subprocess.run(["git", "push", "--force", "--all",
                    "gitlab-internal"], cwd=repo_name, check=True)


def get_request(endpoint, headers, params=None):
    r = requests.get(endpoint, headers=headers, params=params)
    if r.ok:
        return r.json()
    else:
        raise ValueError(
            f"Request failed: URL {endpoint}, CODE {r.status_code}, CONTENT {r.content}"
        )


def put_request(endpoint, headers, params=None):
    r = requests.put(endpoint, headers=headers, params=params)
    if r.ok:
        return r.json()
    else:
        raise ValueError(
            f"Request failed: URL {endpoint}, CODE {r.status_code}, CONTENT {r.content}"
        )


def get_gitlab_config(server="external"):
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
    endpoint = config["api_url"] + "groups"
    response = get_request(endpoint, headers=config["headers"])
    for group in response:
        if group["name"] == group_name:
            return group["id"]
    raise ValueError(f"{group_name} not found in groups.")


def get_project(project_id, config):
    endpoint = config["api_url"] + f"projects/{project_id}"
    project = get_request(endpoint, headers=config["headers"])
    return project


def get_merge_requests_for_approval(config):
    group = get_group_id("approval", config)
    endpoint = config["api_url"] + f"/groups/{group}/merge_requests"
    response = get_request(
        endpoint, headers=config["headers"], params={"state": "opened"}
    )
    return response


def count_unresolved_mr_discussions(mr, config):
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
    project_id = mr["project_id"]
    mr_iid = mr["iid"]
    endpoint = (
        config["api_url"] + f"projects/{project_id}/merge_requests/{mr_iid}/merge"
    )
    return put_request(endpoint, headers=config["headers"])


def check_merge_requests():
    logger.info(f"STARTING RUN")

    try:
        config = get_gitlab_config(server="external")
    except Exception as e:
        logger.critical(f"Failed to load gitlab secrets: {e}")
        return

    logger.info("Getting open merge requests for approval")
    try:
        merge_requests = get_merge_requests_for_approval(config)
    except Exception as e:
        logger.critical(f"Failed to get merge requests: {e}")
        return
    logger.info(f"Found {len(merge_requests)} open merge requests")

    for i, mr in enumerate(merge_requests):
        logger.info("-" * 20)
        logger.info(f"Merge request {i+1} out of {len(merge_requests)}")
        try:
            source_project = get_project(mr["source_project_id"], config)
            logger.info(f"Source Project: {source_project['name_with_namespace']}")
            logger.info(f"Source Branch: {mr['source_branch']}")
            target_project = get_project(mr["project_id"], config)
            logger.info(f"Target Project: {target_project['name_with_namespace']}")
            logger.info(f"Target Branch: {mr['target_branch']}")
            logger.info(f"Commit SHA: {mr['sha']}")
            logger.info(f"Created At: {mr['created_at']}")
            status = mr["merge_status"]
            logger.info(f"Merge Status: {status}")
            wip = mr["work_in_progress"]
            logger.info(f"Work in Progress: {wip}")
            unresolved = count_unresolved_mr_discussions(mr, config)
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
                result = accept_merge_request(mr, config)
            except Exception as e:
                logger.error(f"Merge failed! {e}")
                continue
            if result["state"] == "merged":
                logger.info(f"Merge successful! Merge SHA {result['merge_commit_sha']}")
                try:
                    with open("accepted_merge_requests.log", "a") as f:
                        f.write(
                            f"{result['merged_at']}, {source_project['name_with_namespace']}, {mr['source_branch']}, {mr['sha']}, {target_project['name_with_namespace']}, {mr['target_branch']}, {result['merge_commit_sha']}\n"
                        )
                except Exception as e:
                    logger.error(f"Failed to log accepted merge request: {e}")
                try:
                    internal_update_repo(
                        target_project["ssh_url_to_repo"],
                        target_project["name"]
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
