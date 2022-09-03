import git as _git

# Set development branch and earliest supported release tag
development_branch = "develop"
earliest_supported_release = "v3.4.0"

repo = _git.Repo(search_parent_directories=True)
repo_name = repo.remotes.origin.url.split(".git")[0].split("/")[-1]
_all_releases = sorted((t.name for t in repo.tags), reverse=True)
_earliest_supported_release_idx = _all_releases.index(earliest_supported_release)
_all_supported_releases = _all_releases[:_earliest_supported_release_idx+1]
supported_versions = [development_branch] + _all_supported_releases
_latest_supported_release = _all_supported_releases[0]

# Set default version to disply documentation for latest version
# default_version = latest_supported_release # Latest supported stable release
default_version = development_branch # Latest commit from development branch
