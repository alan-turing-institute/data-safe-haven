#! /usr/bin/env python3
from argparse import ArgumentParser
from pathlib import Path
import requests

_NEXUS_PATH = "http://localhost"
_NEXUS_PORT = 80
_NEXUS_ADMIN_USERNAME = "admin"

_NEXUS_REPOSITORIES = {
    "pypi_proxy": dict(
        repo_type="pypi",
        name="pypi-proxy",
        remote_url="https://pypi.org/"
    ),
    "cran_proxy": dict(
        repo_type="r",
        name="cran-proxy",
        remote_url="https://cran.r-project.org/"
    )
}

_ROLE_NAME = "safe haven user"


class NexusAPI:
    """Interface to the Nexus REST API"""

    def __init__(self, nexus_path, nexus_port, username, password):
        self.nexus_api_root = f"{nexus_path}:{nexus_port}/service/rest"
        self.username = username
        self.password = password

    @property
    def auth(self):
        return requests.auth.HTTPBasicAuth(self.username, self.password)

    def change_admin_password(self, new_password):
        # Change admin password
        print(f"Old password: {self.password}")
        print(f"New password: {new_password}")
        response = requests.put(
            f"{self.nexus_api_root}/beta/security/users/admin/change-password",
            auth=self.auth,
            headers={"content-type": "text/plain"},
            data=new_password,
        )
        if response.status_code == 204:
            print("Changed admin password")
            self.password = new_password
        else:
            print("Changing password failed")
            print(response.content)

    def delete_all_repositories(self):
        response = requests.get(
            f"{self.nexus_api_root}/beta/repositories", auth=self.auth
        )
        repositories = response.json()

        for repo in repositories:
            name = repo["name"]
            print(f"Deleting repository: {name}")
            response = requests.delete(
                f"{self.nexus_api_root}/beta/repositories/{name}", auth=self.auth
            )
            code = response.status_code
            if code == 204:
                print("Repository successfully deleted")
            else:
                print(f"Repository deletion failed.\nStatus code:{code}")
                print(response.content)

    def create_proxy_repository(self, repo_type, name, remote_url):
        assert repo_type in ["pypi", "r"]

        payload = {
            "name": "",
            "online": True,
            "storage": {
                "blobStoreName": "default",
                "strictContentTypeValidation": True,
            },
            "proxy": {"remoteUrl": "", "contentMaxAge": 1440, "metadataMaxAge": 1440},
            "negativeCache": {"enabled": True, "timeToLive": 1440},
            "httpClient": {
                "blocked": False,
                "autoBlock": True,
            },
        }
        payload["name"] = name
        payload["proxy"]["remoteUrl"] = remote_url

        print(f"Creating {repo_type} repository: {name}")
        response = requests.post(
            f"{self.nexus_api_root}/beta/repositories/{repo_type}/proxy",
            auth=self.auth,
            json=payload,
        )
        code = response.status_code
        if code == 201:
            print(f"{repo_type} proxy successfully created")
        else:
            print(f"{repo_type} proxy creation failed.\nStatus code: {code}")
            print(response.content)

    def delete_all_content_selectors(self):
        response = requests.get(
            f"{self.nexus_api_root}/beta/security/content-selectors", auth=self.auth
        )
        content_selectors = response.json()

        for content_selector in content_selectors:
            name = content_selector["name"]
            print(f"Deleting content selector: {name}")
            response = requests.delete(
                f"{self.nexus_api_root}/beta/security/content-selectors/{name}",
                auth=self.auth,
            )
            code = response.status_code
            if code == 204:
                print("Content selector successfully deleted")
            else:
                print(f"Content selector deletion failed.\nStatus code:{code}")
                print(response.content)

    def create_content_selector(self, name, description, expression):
        payload = {
            "name": f"{name}",
            "description": f"{description}",
            "expression": f"{expression}",
        }

        print(f"Creating content selector: {name}")
        response = requests.post(
            f"{self.nexus_api_root}/beta/security/content-selectors",
            auth=self.auth,
            json=payload,
        )
        code = response.status_code
        if code == 204:
            print("content selector successfully created")
        elif code == 500:
            print("content selector already exists")
        else:
            print(f"content selector creation failed.\nStatus code: {code}")
            print(response.content)

    def delete_all_content_selector_privileges(self):
        response = requests.get(
            f"{self.nexus_api_root}/beta/security/privileges", auth=self.auth
        )
        privileges = response.json()

        for privilege in privileges:
            if privilege["type"] != "repository-content-selector":
                continue

            name = privilege["name"]
            print(f"Deleting content selector privilege: {name}")
            response = requests.delete(
                f"{self.nexus_api_root}/beta/security/privileges/{name}", auth=self.auth
            )
            code = response.status_code
            if code == 204:
                print(f"Content selector privilege: {name} successfully deleted")
            else:
                print(
                    "Content selector privilege deletion failed." f"Status code:{code}"
                )
                print(response.content)

    def create_content_selector_privilege(
        self, name, description, repo_type, repo, content_selector
    ):
        payload = {
            "name": f"{name}",
            "description": f"{description}",
            "actions": ["READ"],
            "format": f"{repo_type}",
            "repository": f"{repo}",
            "contentSelector": f"{content_selector}",
        }

        print(f"Creating content selector privilege: {name}")
        response = requests.post(
            (
                f"{self.nexus_api_root}/beta/security/privileges"
                "/repository-content-selector"
            ),
            auth=self.auth,
            json=payload,
        )
        code = response.status_code
        if code == 201:
            print(f"content selector privilege {name} successfully created")
        elif code == 400:
            print(f"content selector privilege {name} already exists")
        else:
            print(
                f"content selector privilege {name} creation failed.\n"
                f"Status code: {code}"
            )
            print(response.content)

    def delete_all_custom_roles(self):
        response = requests.get(
            f"{self.nexus_api_root}/beta/security/roles", auth=self.auth
        )
        roles = response.json()

        for role in roles:
            name = role["name"]
            if name in ["nx-admin", "nx-anonymous"]:
                continue

            print(f"Deleting role: {name}")
            response = requests.delete(
                f"{self.nexus_api_root}/beta/security/roles/{name}", auth=self.auth
            )
            code = response.status_code
            if code == 204:
                print("Role successfully deleted")
            else:
                print(f"Role deletion failed.\nStatus code:{code}")
                print(response.content)

    def create_role(self, name, description, privileges, roles=[]):
        payload = {
            "id": f"{name}",
            "name": f"{name}",
            "description": f"{description}",
            "privileges": privileges,
            "roles": roles,
        }

        print(f"Creating role: {name}")
        response = requests.post(
            (f"{self.nexus_api_root}/beta/security/roles"), auth=self.auth, json=payload
        )
        code = response.status_code
        if code == 200:
            print(f"role {name} successfully created")
        elif code == 400:
            print(f"role {name} already exists")
        else:
            print(f"role {name} creation failed.\nStatus code: {code}")
            print(response.content)

    def update_role(self, name, description, privileges, roles=[]):
        payload = {
            "id": f"{name}",
            "name": f"{name}",
            "description": f"{description}",
            "privileges": privileges,
            "roles": roles,
        }

        print(f"updating role: {name}")
        response = requests.put(
            (f"{self.nexus_api_root}/v1/security/roles/{name}"), auth=self.auth, json=payload
        )
        code = response.status_code
        if code == 204:
            print(f"role {name} successfully created")
        elif code == 404:
            print(f"role {name} does not exist")
        else:
            print(f"role {name} update failed.\nStatus code: {code}")
            print(response.content)

    def enable_anonymous_access(self):
        response = requests.put(
            f"{self.nexus_api_root}/beta/security/anonymous",
            auth=self.auth,
            json={
                "enabled": True,
                "userId": "anonymous",
                "realName": "Local Authorizing Realm",
            },
        )
        code = response.status_code
        if code == 200:
            print("Anonymous access enabled")
        else:
            print(f"Enabling anonymous access failed.\nStatus code: {code}")
            print(response.content)

    def update_anonymous_user_roles(self, roles):
        # Get existing user data JSON
        response = requests.get(
            f"{self.nexus_api_root}/beta/security/users", auth=self.auth
        )
        users = response.json()
        for user in users:
            if user["userId"] == "anonymous":
                anonymous_user = user
                break

        # Change roles
        anonymous_user["roles"] = roles

        # Push changes to Nexus
        response = requests.put(
            f"{self.nexus_api_root}/beta/security/users/{anonymous_user['userId']}",
            auth=self.auth,
            json=anonymous_user,
        )
        code = response.status_code
        if code == 204:
            print(f"User {anonymous_user['userId']} roles updated")
        else:
            print(
                f"User {anonymous_user['userId']} role update failed.\n"
                f"Status code: {code}"
            )
            print(response.content)


def main():
    parser = ArgumentParser(description="Configure Nexus3")
    parser.add_argument(
        "--admin-password",
        type=str,
        required=True,
        help="Password for the Nexus 'admin' account",
    )

    # Group of arguments for tiers and package files
    tier_parser = ArgumentParser(add_help=False)
    tier_parser.add_argument(
        "--tier",
        type=int,
        required=True,
        choices=[2, 3],
        help="Data security tier of the repository",
    )
    tier_parser.add_argument(
        "--pypi-package-file",
        type=Path,
        help="Path of the file of allowed PyPI packages, only when TIER=3"
    )
    tier_parser.add_argument(
        "--cran-package-file",
        type=Path,
        help="Path of the file of allowed CRAN packages, only when TIER=3"
    )

    subparsers = parser.add_subparsers(
        title="subcommands",
        required=True
    )

    # sub-command for changing initial password
    parser_password = subparsers.add_parser(
        "change-initial-password",
        help="Change the initial admin password"
    )
    parser_password.add_argument(
        "--path",
        type=Path,
        default=Path("./nexus-data"),
        help="Path of the nexus-data directory [./nexus-data]"
    )
    parser_password.set_defaults(func=change_initial_password)

    # sub-command for initial configuration
    parser_configure = subparsers.add_parser(
        "initial-configuration",
        help="Configure the Nexus repository",
        parents=[tier_parser]
    )
    parser_configure.set_defaults(func=initial_configuration)

    # sub-command for updating package allow lists
    parser_update = subparsers.add_parser(
        "update-allowlists",
        help="Update the Nexus package allowlists",
        parents=[tier_parser]
    )
    parser_update.set_defaults(func=update_allow_lists)

    args = parser.parse_args()

    # if args.tier == 3:
    #     raise NotImplementedError("Currently only tier 2 is supported")

    for package_file in [args.pypi_package_file, args.cran_package_file]:
        if package_file and not package_file.is_file():
            raise Exception(
                f"Package allowlist file {package_file} does not exist"
            )

    args.func(args)


def change_initial_password(args):
    password_file_path = Path(f"{args.path}/admin.password")

    try:
        with password_file_path.open() as password_file:
            initial_password = password_file.read()
    except FileNotFoundError:
        raise Exception(
            "Initial password appears to have been already changed"
        )

    nexus_api = NexusAPI(
        nexus_path=_NEXUS_PATH,
        nexus_port=_NEXUS_PORT,
        username=_NEXUS_ADMIN_USERNAME,
        password=initial_password,
    )

    nexus_api.change_admin_password(args.admin_password)


def initial_configuration(args):
    nexus_api = NexusAPI(
        nexus_path=_NEXUS_PATH,
        nexus_port=_NEXUS_PORT,
        username=_NEXUS_ADMIN_USERNAME,
        password=args.admin_password,
    )

    # Ensure only desired repositories exist
    recreate_repositories(nexus_api)

    privileges = recreate_privileges(args.tier, nexus_api)
    if args.tier == 3:
        pypi_allowlist, cran_allowlist = get_allowlists(args.pypi_package_file,
                                                        args.cran_package_file)
        privileges = recreate_privileges(args.tier, nexus_api, pypi_allowlist, cran_allowlist)
    else:
        privileges = recreate_privileges(args.tier, nexus_api)

    # Delete non-default roles
    nexus_api.delete_all_custom_roles()

    # Create a role for safe haven users
    nexus_api.create_role(
        name=_ROLE_NAME,
        description="allows access to selected packages",
        privileges=privileges
    )

    # Enable anonymous access
    nexus_api.enable_anonymous_access()

    # Update anonymous users roles
    nexus_api.update_anonymous_user_roles([_ROLE_NAME])


def update_allow_lists(args):
    nexus_api = NexusAPI(
        nexus_path=_NEXUS_PATH,
        nexus_port=_NEXUS_PORT,
        username=_NEXUS_ADMIN_USERNAME,
        password=args.admin_password,
    )

    if args.tier == 3:
        pypi_allowlist, cran_allowlist = get_allowlists(args.pypi_package_file,
                                                        args.cran_package_file)
        privileges = recreate_privileges(args.tier, nexus_api, pypi_allowlist, cran_allowlist)
    else:
        privileges = recreate_privileges(args.tier, nexus_api)

    # Update role for safe haven users
    nexus_api.update_role(
        name=_ROLE_NAME,
        description="allows access to selected packages",
        privileges=privileges
    )


def get_allowlists(pypi_package_file, cran_package_file):
    pypi_allowlist = []
    cran_allowlist = []

    if pypi_package_file:
        pypi_allowlist = get_allowlist(pypi_package_file)

    if cran_package_file:
        cran_allowlist = get_allowlist(cran_package_file)

    return (pypi_allowlist, cran_allowlist)


def get_allowlist(allowlist_path):
    with open(allowlist_path, "r") as allowlist_file:
        allowlist = allowlist_file.read().splitlines()

    allowlist = [i.lower() for i in allowlist]

    return allowlist


def recreate_repositories(nexus_api):
    # Delete all existing repositories
    nexus_api.delete_all_repositories()

    for repository in _NEXUS_REPOSITORIES.values():
        nexus_api.create_proxy_repository(**repository)


def recreate_privileges(tier, nexus_api, pypi_allowlist=[],
                        cran_allowlist=[]):
    # Delete all existing content selector privileges
    # These must be deleted before the content selectors as the content selectors
    # as the privileges depend on the content selectors
    nexus_api.delete_all_content_selector_privileges()

    # Delete all existing content selectors
    nexus_api.delete_all_content_selectors()

    # Create content selectors and corresponding privileges
    pypi_privilege_names = []
    cran_privilege_names = []

    # Content selector and privilege for PyPI 'simple' path, used to search for
    # packages
    privilege_name = create_content_selector_privilege(
        nexus_api,
        name="simple",
        description="Allow access to 'simple' directory in PyPI repository",
        expression='format == "pypi" and path=^"/simple"',
        repo_type=_NEXUS_REPOSITORIES["pypi_proxy"]["repo_type"],
        repo=_NEXUS_REPOSITORIES["pypi_proxy"]["name"]
    )
    pypi_privilege_names.append(privilege_name)

    # Create content selectors and privileges for packages according to the tier
    if tier == 2:
        # Allow all PyPI packages
        privilege_name = create_content_selector_privilege(
            nexus_api,
            name="pypi-all",
            description="Allow access to all PyPI packages",
            expression='format == "pypi" and path=^"/packages/"',
            repo_type=_NEXUS_REPOSITORIES["pypi_proxy"]["repo_type"],
            repo=_NEXUS_REPOSITORIES["pypi_proxy"]["name"]
        )
        pypi_privilege_names.append(privilege_name)

        # Allow all CRAN packages
        privilege_name = create_content_selector_privilege(
            nexus_api,
            name="cran-all",
            description="Allow access to all CRAN packages",
            expression='format == "r" and path=^"/src/contrib"',
            repo_type=_NEXUS_REPOSITORIES["cran_proxy"]["repo_type"],
            repo=_NEXUS_REPOSITORIES["cran_proxy"]["name"]
        )
        cran_privilege_names.append(privilege_name)
    elif tier == 3:
        # Allow selected PyPI packages
        for package in pypi_allowlist:
            privilege_name = create_content_selector_privilege(
                nexus_api,
                name=f"pypi-{package}",
                description=f"Allow access to {package} on PyPI",
                expression=f'format == "pypi" and path=^"/packages/{package}/"',
                repo_type=_NEXUS_REPOSITORIES["pypi_proxy"]["repo_type"],
                repo=_NEXUS_REPOSITORIES["pypi_proxy"]["name"]
            )
            pypi_privilege_names.append(privilege_name)

        # Allow selected CRAN packages
        for package in cran_allowlist:
            privilege_name = create_content_selector_privilege(
                nexus_api,
                name=f"cran-{package}",
                description=f"allow access to {package} on CRAN",
                expression='format == "r" and path=^"/src/contrib/{package}"',
                repo_type=_NEXUS_REPOSITORIES["cran_proxy"]["repo_type"],
                repo=_NEXUS_REPOSITORIES["cran_proxy"]["name"]
            )
            cran_privilege_names.append(privilege_name)

    return (pypi_privilege_names + cran_privilege_names)


def create_content_selector_privilege(nexus_api, name, description, expression,
                                      repo_type, repo):
    nexus_api.create_content_selector(
        name=name,
        description=description,
        expression=expression
    )

    nexus_api.create_content_selector_privilege(
        name=name,
        description=description,
        repo_type=repo_type,
        repo=repo,
        content_selector=name,
    )

    return name


if __name__ == "__main__":
    main()
