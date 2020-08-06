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
parser.add_argument(
    "--tier",
    type=int,
    required=True,
    choices=[2, 3],
    help="Data security tier of the repository"
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

if args.tier == 3:
    raise NotImplementedError("Currently only tier 2 is supported")


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
        }
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


def enable_anonymous_access():
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


def update_anonymous_user_roles(roles):
    # Get existing user data JSON
    r = requests.get(f"{NEXUS_API_ROOT}/beta/security/users", auth=auth)
    users = r.json()
    for user in users:
        if user["userId"] == "anonymous":
            anonymous_user = user
            break

    # Change roles
    anonymous_user["roles"] = roles

    # Push changes to Nexus
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

# Create content selectors and corresponding privileges
pypi_privilege_names = []
cran_privilege_names = []

# Content selector and privilege for PyPi 'simple' path, used to search for
# packages
create_content_selector(
    name="simple",
    description="Allow access to 'simple' directory in PyPi repository",
    expression="format == \"pypi\" and path=^\"/simple\""
)
create_content_selector_privilege(
    name="simple",
    description="Allow access to the pypi simple directory",
    repo_type="pypi",
    repo="pypi-proxy",
    content_selector="simple"
)
pypi_privilege_names.append("simple")

# Create content selectors and privileges for packages according to the tier
if args.tier == 2:
    # Allow all PyPi packages/versions
    create_content_selector(
        name="pypi",
        description="Allow access to all PyPi packages",
        expression="format == \"pypi\" and path=^\"/packages/\""
    )
    create_content_selector_privilege(
        name="pypi",
        description="Allow access to all PyPi packages",
        repo_type="pypi",
        repo="pypi-proxy",
        content_selector="pypi"
    )
    pypi_privilege_names.append("pypi")

    # Allow all CRAN packages/versions
    create_content_selector(
        name="cran",
        description="Allow access to all CRAN packages",
        expression="format == \"r\" and path=^\"/src/contrib\""
    )
    create_content_selector_privilege(
        name="cran",
        description="Allow access to all CRAN packages",
        repo_type="r",
        repo="cran-proxy",
        content_selector="cran"
    )
    cran_privilege_names.append("cran")
elif args.tier == 3:
    # Collect allowed PyPi package names and versions
    allowed_pypi_packages = []

    for package, version in allowed_pypi_packages:
        name = f"pypi-{package}-{version}"
        expression = (
            f"format == \"pypi\" and path=^\"/packages/{package}/{version}/\""
        )
        description = f"Allow access to {package} version {version}"
        create_content_selector(name, description, expression)

        create_content_selector_privilege(
            name=name,
            description=f"Allow access to {package} version {version}",
            repo_type="pypi",
            repo="pypi-proxy",
            content_selector=name
        )
        pypi_privilege_names.append(name)

    # Collect allowed PyPi package names and versions
    allowed_cran_packages = []

    for package, version in allowed_cran_packages:
        create_content_selector(
            name=f"cran-{package}-{version}",
            description="Allow access to all CRAN packages",
            expression=(
                "format == \"r\""
                " and path=^\"/src/contrib/{package}_{version}\""
            )
        )

        create_content_selector_privilege(
            name=name,
            description="Allow access to all CRAN packages",
            repo_type="r",
            repo="cran-proxy",
            content_selector=name
        )
        cran_privilege_names.append(name)

# Delete non-default roles
delete_all_custom_roles()

# Create a role with the PyPi privileges
pypi_role_name = f"tier {args.tier} pypi"
create_role(
    name=pypi_role_name,
    description=f"Allow access to tier {args.tier} PyPi packages",
    privileges=pypi_privilege_names
)

# Create a role with the CRAN privileges
cran_role_name = f"tier {args.tier} cran"
create_role(
    name=cran_role_name,
    description=f"Allow access to tier {args.tier} CRAN packages",
    privileges=cran_privilege_names
)

# Enable anonymous access
enable_anonymous_access()

# Update anonymous users roles
update_anonymous_user_roles([pypi_role_name, cran_role_name])
