import argparse

import requests
from requests.auth import HTTPBasicAuth

# gitea_host = "http://gitea_mirror.local"
gitea_host = "http://localhost:3000"
api_root = "/api/v1"
migrate_path = "/repos/migrate"
extra_data = {
    "issues": False,
    "mirror": False,
    "mirror_interval": "600",
    "pull_requests": False,
    "releases": False,
    "wiki": False,
}

parser = argparse.ArgumentParser()
parser.add_argument(
    'username'
)
parser.add_argument(
    'password'
)
parser.add_argument(
    'name'
)
parser.add_argument(
    'address'
)
args = parser.parse_args()

auth = HTTPBasicAuth(
    username=args.username,
    password=args.password,
)

response = requests.post(
    gitea_host + api_root + migrate_path,
    auth=auth,
    data={
        "clone_addr": args.address,
        "repo_name": args.name,
    } | extra_data,
)

print(response.json())
response.raise_for_status()
