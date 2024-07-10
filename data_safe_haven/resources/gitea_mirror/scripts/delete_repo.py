import argparse

import requests
from requests.auth import HTTPBasicAuth

# gitea_host = "http://gitea_mirror.local"
gitea_host = "http://localhost:3000"
api_root = "/api/v1"
path = "/repos/"
extra_data = {}

parser = argparse.ArgumentParser()
parser.add_argument(
    'username'
)
parser.add_argument(
    'password'
)
parser.add_argument(
    'owner'
)
parser.add_argument(
    'name'
)
args = parser.parse_args()

auth = HTTPBasicAuth(
    username=args.username,
    password=args.password,
)

response = requests.delete(
    gitea_host + api_root + path + f"/{args.owner}/{args.name}",
    auth=auth,
    data={} | extra_data,
)

# print(response.json())
response.raise_for_status()
