import argparse

import requests
from requests.auth import HTTPBasicAuth

parser = argparse.ArgumentParser()
parser.add_argument("username")
parser.add_argument("password")
parser.add_argument("name")
parser.add_argument("address")
args = parser.parse_args()

# gitea_host = "http://gitea_mirror.local"
gitea_host = "http://localhost:3000"
api_root = "/api/v1"
migrate_path = "/repos/migrate"
repos_path = "/repos"
extra_data = {
    "description": f"Read-only mirror of {args.address}",
    "mirror": True,
    "mirror_interval": "10m",
}
timeout = 60

auth = HTTPBasicAuth(
    username=args.username,
    password=args.password,
)

response = requests.post(
    auth=auth,
    data={
        "clone_addr": args.address,
        "repo_name": args.name,
    }
    | extra_data,
    timeout=timeout,
    url=gitea_host + api_root + migrate_path,
)

print(response.json())  # noqa: T201
response.raise_for_status()

# Some arguments of the migrate endpoint seem to be ignored or overwritten
response = requests.patch(
    auth=auth,
    data={
        "has_actions": False,
        "has_issues": False,
        "has_packages": False,
        "has_projects": False,
        "has_pull_requests": False,
        "has_releases": False,
        "has_wiki": False,
    },
    timeout=timeout,
    url=gitea_host + api_root + repos_path + f"/{args.username}/{args.name}",
)

print(response.json())  # noqa: T201
response.raise_for_status()
