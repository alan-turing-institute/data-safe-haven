from zipfile_to_gitlab_project import *

__doc__ = """
Start from zipfile of a particular commit - should have filename
of the form <repo-name>_<commit-hash>_<desired_branch_name>.zip

We want to turn this into a merge request on a Gitlab project.

1) get useful gitlab stuff (url, api key, namespace_ids for our groups)
2) unzip zipfiles in specified directory
3) loop over unzipped repos. For each one:
  a) see if "approved" project with same name exists, if not, create it
  b) check if merge request to "approved/<repo_name>" with source and target branches
     "commit-<commit-hash>" and "<desired_branch_name>" already exists.
      If so, skip to the next unzipped repo.
  b) see if "unapproved" project with same name exists, if not, fork "approved" one
  c) clone "unapproved" project, and create branch called "commit-<commit_hash>"
  d) copy in contents of unzipped repo.
  e) git add, commit and push to "unapproved" project
  f) create branch "<desired_branch_name>" on "approved" project
  g) create merge request from unapproved/repo_name/commit_hash to
     approved/repo_name/desired_branch_name
4) clean up - remove zipfiles and unpacked repos.
"""

unzip_zipfiles.__doc__ = """
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

get_gitlab_config.__doc__ = """
Return a dictionary containing the base URL for the gitlab API,
the API token, the IP address, and the headers to go in any request
"""

get_group_namespace_ids.__doc__ = """
Find the namespace_id corresponding to the groups we're interested in,
e.g. 'approved' and 'unapproved'.

Parameters
==========
gitlab_url: str, base URL for the API
gitlab_token: str, API token for Gitlab
groups: list of string, the group names to look for.

Returns
=======
namespace_id_dict: dict, format {<group_name:str>: <namespace_id:int>}
"""

get_gilab_project_list.__doc__ = """
Get the list of Projects.

Parameters
==========
namespace_id: int, ID of the group ("unapproved" or "approved")
gitlab_url: str, base URL for the API
gitlab_token: str, API token.

Returns
=======
gitlab_projects: list of dictionaries.
"""

check_if_project_exists.__doc__ = """
Get a list of projects from the API - check if namespace_id (i.e. group)
and name match.

Parameters
==========
repo_name: str, name of our repository/project
namespace_id: int, id of our group ("unapproved" or "approved")
gitlab_url: str, base URL of Gitlab API
gitlab_token: str, API key for Gitlab API.

Returns
=======
bool, True if project exists, False otherwise.
"""

get_project_info.__doc__ = """
Check if project exists, and if so get its ID.  Otherwise, create
it and return the ID.

Parameters
==========
repo_name: str, name of our repository/project
namespace_id: int, id of our group ("unapproved" or "approved")
gitlab_url: str, base URL of Gitlab API
gitlab_token: str, API key for Gitlab API.

Returns
=======
project_info: dict, containing info from the projects API endpoint
"""

get_project_id.__doc__ = """
Given the name of a repository and  namespace_id (i.e. group,
"unapproved" or "approved"), either return the remote URL for project
matching the repo name, or create it if it doesn't exist already,
and again return the remote URL.

Parameters
==========
repo_name: str, name of the repository/project we're looking for.
namespace_id: int, the ID of the group ("unapproved" or "approved")
gitlab_url: str, base URL of the API
gitlab_token: str, API key

Returns
=======
gitlab_project_url: str, the URL to be set as the "remote".
"""

create_project.__doc__ = """
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

check_if_branch_exists.__doc__ = """
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

create_branch.__doc__ = """
Create a new branch on an existing project.  By default, use
'_gitlab_ingress_review' (which is unlikely to exist in the source
repo) as the reference branch from which to create the new one.

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

check_if_merge_request_exists.__doc__ = """
See if there is an existing merge request between the source and target
project/branch combinations.

Parameters
==========
source_branch: str, name of the branch on source project, will typically
be the commit_hash from the original repo.
target_project_id: int, project_id for the "approved" group's project.
target_branch: str, name of branch on target project, will typically
be the desired branch name.
gitlab_url: str, base URL for the Gitlab API
gitlab_token: str, API token for the Gitlab API.

Returns
=======
bool, True if merge request already exists, False otherwise
"""

create_merge_request.__doc__ = """
Create a new MR, e.g. from the branch <commit_hash> in the "unapproved"
group's project, to the branch <desired_branch_name> in the "approved"
group's project.

Parameters
==========
repo_name: str, name of the repository
source_project_id: int, project_id for the unapproved project, obtainable
as the "ID" field of the json returned from the
projects API endpoint.
source_branch: str, name of the branch on source project, will typically
be the 'branch-<commit-hash-from-the-original-repo>'.
target_project_id: int, project_id for the "approved" group's project.
target_branch: str, name of branch on target project, will typically
be the desired branch name.
gitlab_url: str, base URL for the Gitlab API
gitlab_token: str, API token for the Gitlab API.

Returns
=======
mr_info: dict, the response from the API upon creating the Merge Request
"""


clone_commit_and_push.__doc__ = """ 
Run shell commands to convert the unzipped directory containing the
repository contents into a git repo, then commit it on the branch
with the requested name.

Parameters
==========
repo_name: str, name of the repository/project
path_to_unzipped_repo: str, the full directory path to the unzipped repo
tmp_repo_dir: str, path to a temporary dir where we will clone the project
branch_name: str, the name of the branch to push to
remote_url: str, the URL for this project on gitlab-review to be added
as a "remote".
"""

fork_project.__doc__ = """
Fork the project 'approved/<project-name>' to 'unapproved/<project-name>'
after first checking whether the latter exists.

Parameters
==========
repo_name: str, name of the repo/project
project_id: int, project id of the 'approved/<project-name>' project
namespace_id: int, id of the 'unapproved' namespace
gitlab_url: str, str, the base URL of Gitlab API
gitlab_token: str, API token for Gitlab API

Returns
=======
new_project_id: int, the id of the newly created 'unapproved/<project-name>' project
"""

unzipped_repo_to_merge_request = """
Go through all the steps for a single repo/project.

Parameters
==========
repo_details: tuple of strings, (repo_name, hash, desired_branch, location)
tmp_repo_dir: str, directory where we will clone the repo, then copy the contents in
gitlab_config: dict, contains api url and token
namespace_ids; dict, keys are the group names (e.g. "unapproved", "approved", values
are the ids of the corresponding namespaces in Gitlab
group_names: list of strings, typically ["unapproved", "approved"]
"""

cleanup.__doc__ = """
Remove directories and files after everything has been uploaded to gitlab

Parameters
==========
zipfile_dir: str, directory containing the original zipfiles.  Will not remove this
directory, but we will delete all the zipfiles in it.
tmp_unzipped_dir: str, directory where the unpacked zipfile contents are put. Remove.
tmp_repo_dir: str, directory where projects are cloned from Gitlab, then contents from
tmp_unzipped_dir are copied in.  Remove.
"""
