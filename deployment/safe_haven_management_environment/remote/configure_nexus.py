#!/usr/bin/env python3
import requests
from requests.auth import HTTPBasicAuth
from argparse import ArgumentParser

parser = ArgumentParser(description="Configure Nexus3")
parser.add_argument(
    "--admin_password",
    type=str,
    required=True,
    help="Password for the Nexus 'admin' account"
)
parser.add_argument(
    "--path",
    type=str,
    help="Path of the nexus-data directory"
)
args = parser.parse_args()


USERNAME = "admin"
PASSWORD = args.admin_password
auth = HTTPBasicAuth(USERNAME, PASSWORD)

if args.path is None:
    NEXUS_DATA_DIR = "./nexus-data"
else:
    NEXUS_DATA_DIR = args.path

NEXUS_PATH = "http://localhost"
NEXUS_PORT = "8081"
NEXUS_ROOT = f"{NEXUS_PATH}:{NEXUS_PORT}"
NEXUS_API_ROOT = f"{NEXUS_PATH}:{NEXUS_PORT}/service/rest"


def delete_all_repositories():
    r = requests.get(f"{NEXUS_API_ROOT}/beta/repositories", auth=auth)
    repositories = r.json()

    for repo in repositories:
        name = repo["name"]
        print(f"Deleting repository: {name}")
        r = requests.delete(
            f"{NEXUS_API_ROOT}/beta/repositories/{name}",
            auth=auth
        )
        code = r.status_code
        if code == 204:
            print("Repository successfully deleted")
        else:
            print(f"Repository deletion failed.\nStatus code:{code}")
            print(r.content)


def create_proxy_repository(repo_type, name, remote_url):
    assert repo_type in ["pypi", "r"]

    payload = {
        "name": "",
        "online": True,
        "storage": {
            "blobStoreName": "default",
            "strictContentTypeValidation": True
        },
        # "cleanup": {
        #     "policyNames": ["string"]
        #     },
        "proxy": {
            "remoteUrl": "",
            "contentMaxAge": 1440,
            "metadataMaxAge": 1440
        },
        "negativeCache": {
            "enabled": True,
            "timeToLive": 1440
        },
        "httpClient": {
            "blocked": False,
            "autoBlock": True,
            # "connection": {
            #     "retries": 0,
            #     "userAgentSuffix": "string",
            #     "timeout": 60,
            #     "enableCircularRedirects": False,
            #     "enableCookies": False
            #     },
            # "authentication": {
            #     "type": "username",
            #     "username": "username",
            #     "password": "password"
            #     },
        },
        # "routingRule": "string"
    }
    payload["name"] = name
    payload["proxy"]["remoteUrl"] = remote_url

    print(f"Creating {repo_type} repository: {name}")
    r = requests.post(
        f"{NEXUS_API_ROOT}/beta/repositories/{repo_type}/proxy",
        auth=auth,
        json=payload
    )
    code = r.status_code
    if code == 201:
        print(f"{repo_type} proxy successfully created")
    else:
        print(f"{repo_type} proxy creation failed.\nStatus code: {code}")
        print(r.content)


def delete_all_content_selectors():
    r = requests.get(
        f"{NEXUS_API_ROOT}/beta/security/content-selectors",
        auth=auth
    )
    content_selectors = r.json()

    for content_selector in content_selectors:
        name = content_selector["name"]
        print(f"Deleting content selector: {name}")
        r = requests.delete(
            f"{NEXUS_API_ROOT}/beta/security/content-selectors/{name}",
            auth=auth
        )
        code = r.status_code
        if code == 204:
            print("Content selector successfully deleted")
        else:
            print(f"Content selector deletion failed.\nStatus code:{code}")
            print(r.content)


def create_content_selector(name, description, expression):
    payload = {
        "name": f"{name}",
        "description": f"{description}",
        "expression": f"{expression}"
    }

    print(f"Creating content selector: {name}")
    r = requests.post(
        f"{NEXUS_API_ROOT}/beta/security/content-selectors",
        auth=auth,
        json=payload
    )
    code = r.status_code
    if code == 204:
        print("content selector successfully created")
    elif code == 500:
        print("content selector already exists")
    else:
        print(f"content selector creation failed.\nStatus code: {code}")
        print(r.content)


def delete_all_content_selector_privileges():
    r = requests.get(
        f"{NEXUS_API_ROOT}/beta/security/privileges",
        auth=auth
    )
    privileges = r.json()

    for privilege in privileges:
        if privilege["type"] != "repository-content-selector":
            continue

        name = privilege["name"]
        print(f"Deleting content selector privilege: {name}")
        r = requests.delete(
            f"{NEXUS_API_ROOT}/beta/security/privileges/{name}",
            auth=auth
        )
        code = r.status_code
        if code == 204:
            print(f"Content selector privilege: {name} successfully deleted")
        else:
            print("Content selector privilege deletion failed."
                  f"Status code:{code}")
            print(r.content)


def create_content_selector_privilege(name, description, repo_type, repo,
                                      content_selector):
    payload = {
        "name": f"{name}",
        "description": f"{description}",
        "actions": [
            "READ"
        ],
        "format": f"{repo_type}",
        "repository": f"{repo}",
        "contentSelector": f"{content_selector}"
    }

    print(f"Creating content selector privilege: {name}")
    r = requests.post(
        (f"{NEXUS_API_ROOT}/beta/security/privileges"
         "/repository-content-selector"),
        auth=auth,
        json=payload
    )
    code = r.status_code
    if code == 201:
        print(f"content selector privilege {name} successfully created")
    elif code == 400:
        print(f"content selector privilege {name} already exists")
    else:
        print(f"content selector privilege {name} creation failed.\n"
              f"Status code: {code}")
        print(r.content)


def delete_all_custom_roles():
    r = requests.get(f"{NEXUS_API_ROOT}/beta/security/roles", auth=auth)
    roles = r.json()

    for role in roles:
        name = role["name"]
        if name in ["nx-admin", "nx-anonymous"]:
            continue

        print(f"Deleting role: {name}")
        r = requests.delete(
            f"{NEXUS_API_ROOT}/beta/security/roles/{name}",
            auth=auth
        )
        code = r.status_code
        if code == 204:
            print("Role successfully deleted")
        else:
            print(f"Role deletion failed.\nStatus code:{code}")
            print(r.content)


def create_role(name, description, privileges, roles=None):
    if roles is None:
        roles = []

    payload = {
        "id": f"{name}",
        "name": f"{name}",
        "description": f"{description}",
        "privileges": privileges,
        "roles": roles
    }

    print(f"Creating role: {name}")
    r = requests.post(
        (f"{NEXUS_API_ROOT}/beta/security/roles"),
        auth=auth,
        json=payload
    )
    code = r.status_code
    if code == 200:
        print(f"role {name} successfully created")
    elif code == 400:
        print(f"role {name} already exists")
    else:
        print(f"role {name} creation failed.\nStatus code: {code}")
        print(r.content)


# Change admin password
try:
    with open(f"{NEXUS_DATA_DIR}/admin.password") as password_file:
        old_password = password_file.read()

    print(f"Old password: {old_password}")
    print(f"New password: {PASSWORD}")

    r = requests.put(
        f"{NEXUS_API_ROOT}/beta/security/users/admin/change-password",
        auth=HTTPBasicAuth(USERNAME, old_password),
        headers={'content-type': 'text/plain'},
        data=PASSWORD
    )
    if r.status_code == 204:
        print("admin password changed")
    else:
        print("Chaning password failed")
        print(r.content)
except FileNotFoundError:
    print("Password already changed")
    print("Attempting to use provided password")

# Delete all existing repositories
delete_all_repositories()

# Add PyPi proxy
create_proxy_repository("pypi", "pypi-proxy", "https://pypi.org/")
# Add CRAN proxy
create_proxy_repository("r", "cran-proxy", "https://cran.r-project.org/")

# Delete all existing content selector privileges
# These must be deleted before the content selectors as the content selectors
# as the privileges depend on the content selectors
delete_all_content_selector_privileges()

# Delete all existing content selectors
delete_all_content_selectors()

# Create content selectors
create_content_selector(
    name="simple",
    description="Allow access to 'simple' directory in PyPi repository",
    expression="format == \"pypi\" and path=^\"/simple\""
)
allowed_pypi_packages = [
    ("attrs", "19.3.0"),
    ("more-itertools", "8.4.0"),
    ("packaging", "20.4"),
    ("pluggy", "0.13.1"),
    ("py", "1.9.0"),
    ("pyparsing", "2.4.7"),
    ("pytest", "5.4.3"),
    ("six", "1.15.0"),
    ("wcwidth", "0.2.5"),
]
for package, version in allowed_pypi_packages:
    name = f"{package}-{version}"
    expression = (
        f"format == \"pypi\" and path=^\"/packages/{package}/{version}/\""
    )
    description = f"Allow access to {package} version {version}"
    create_content_selector(name, description, expression)

# Create privileges
privilege_names = []
for package, version in allowed_pypi_packages:
    create_content_selector_privilege(
        name=package,
        description=f"Allow access to {package} version {version}",
        repo_type="pypi",
        repo="pypi-proxy",
        content_selector=f"{package}-{version}"
    )
    privilege_names.append(package)
    create_content_selector_privilege(
        name="simple",
        description="Allow access to the pypi simple directory",
        repo_type="pypi",
        repo="pypi-proxy",
        content_selector="simple"
    )
    privilege_names.append("simple")

# Delete non-default roles
delete_all_custom_roles()

# Create a role with the privileges
create_role(
    name="tier 2 pypi",
    description="Allow access to tier 2 PyPi packages",
    privileges=privilege_names
)

# Enable anonymous access
r = requests.put(
    f"{NEXUS_API_ROOT}/beta/security/anonymous",
    auth=auth,
    json={
        "enabled": True,
        "userId": "anonymous",
        "realName": "Local Authorizing Realm"
    }
)
code = r.status_code
if code == 200:
    print("Anonymous access enabled")
else:
    print(f"Enabling anonymous access failed.\nStatus code: {code}")
    print(r.content)

# Update anonymous users roles
r = requests.get(f"{NEXUS_API_ROOT}/beta/security/users", auth=auth)
users = r.json()
for user in users:
    if user["userId"] == "anonymous":
        anonymous_user = user
        break
anonymous_user["roles"] = ["tier 2 pypi"]
r = requests.put(
    f"{NEXUS_API_ROOT}/beta/security/users/{anonymous_user['userId']}",
    auth=auth,
    json=anonymous_user
)
code = r.status_code
if code == 204:
    print(f"User {anonymous_user['userId']} roles updated")
else:
    print(f"User {anonymous_user['userId']} role update failed.\n"
          f"Status code: {code}")
    print(r.content)
