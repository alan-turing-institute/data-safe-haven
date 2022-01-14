#! /usr/bin/env python3
from argparse import ArgumentParser
from pathlib import Path
import requests

__NEXUS_PATH = "http://localhost"
__NEXUS_PORT = 80
__NEXUS_ADMIN_USERNAME = "admin"


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
        nexus_path=__NEXUS_PATH,
        nexus_port=__NEXUS_PORT,
        username=__NEXUS_ADMIN_USERNAME,
        password=initial_password,
    )

    nexus_api.change_admin_password(args.admin_password)


def configure(args):
    if args.tier == 3:
        raise NotImplementedError("Currently only tier 2 is supported")

    nexus_api = NexusAPI(
        nexus_path=__NEXUS_PATH,
        nexus_port=__NEXUS_PORT,
        username=__NEXUS_ADMIN_USERNAME,
        password=args.admin_password,
    )

    # Delete all existing repositories
    nexus_api.delete_all_repositories()

    # Add PyPI proxy
    nexus_api.create_proxy_repository("pypi", "pypi-proxy", "https://pypi.org/")
    # Add CRAN proxy
    nexus_api.create_proxy_repository("r", "cran-proxy", "https://cran.r-project.org/")

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
    nexus_api.create_content_selector(
        name="simple",
        description="Allow access to 'simple' directory in PyPI repository",
        expression='format == "pypi" and path=^"/simple"',
    )
    nexus_api.create_content_selector_privilege(
        name="simple",
        description="Allow access to the pypi simple directory",
        repo_type="pypi",
        repo="pypi-proxy",
        content_selector="simple",
    )
    pypi_privilege_names.append("simple")

    # Create content selectors and privileges for packages according to the tier
    if args.tier == 2:
        # Allow all PyPI packages/versions
        nexus_api.create_content_selector(
            name="pypi",
            description="Allow access to all PyPI packages",
            expression='format == "pypi" and path=^"/packages/"',
        )
        nexus_api.create_content_selector_privilege(
            name="pypi",
            description="Allow access to all PyPI packages",
            repo_type="pypi",
            repo="pypi-proxy",
            content_selector="pypi",
        )
        pypi_privilege_names.append("pypi")

        # Allow all CRAN packages/versions
        nexus_api.create_content_selector(
            name="cran",
            description="Allow access to all CRAN packages",
            expression='format == "r" and path=^"/src/contrib"',
        )
        nexus_api.create_content_selector_privilege(
            name="cran",
            description="Allow access to all CRAN packages",
            repo_type="r",
            repo="cran-proxy",
            content_selector="cran",
        )
        cran_privilege_names.append("cran")
    elif args.tier == 3:
        # Collect allowed PyPI package names and versions
        allowed_pypi_packages = []

        for package, version in allowed_pypi_packages:
            name = f"pypi-{package}-{version}"
            expression = f'format == "pypi" and path=^"/packages/{package}/{version}/"'
            description = f"Allow access to {package} version {version}"
            nexus_api.create_content_selector(name, description, expression)

            nexus_api.create_content_selector_privilege(
                name=name,
                description=f"Allow access to {package} version {version}",
                repo_type="pypi",
                repo="pypi-proxy",
                content_selector=name,
            )
            pypi_privilege_names.append(name)

        # Collect allowed PyPI package names and versions
        allowed_cran_packages = []

        for package, version in allowed_cran_packages:
            nexus_api.create_content_selector(
                name=f"cran-{package}-{version}",
                description="Allow access to all CRAN packages",
                expression=(
                    'format == "r"' ' and path=^"/src/contrib/{package}_{version}"'
                ),
            )

            nexus_api.create_content_selector_privilege(
                name=name,
                description="Allow access to all CRAN packages",
                repo_type="r",
                repo="cran-proxy",
                content_selector=name,
            )
            cran_privilege_names.append(name)

    # Delete non-default roles
    nexus_api.delete_all_custom_roles()

    # Create a role with the PyPI privileges
    pypi_role_name = f"tier {args.tier} pypi"
    nexus_api.create_role(
        name=pypi_role_name,
        description=f"Allow access to tier {args.tier} PyPI packages",
        privileges=pypi_privilege_names,
    )

    # Create a role with the CRAN privileges
    cran_role_name = f"tier {args.tier} cran"
    nexus_api.create_role(
        name=cran_role_name,
        description=f"Allow access to tier {args.tier} CRAN packages",
        privileges=cran_privilege_names,
    )

    # Enable anonymous access
    nexus_api.enable_anonymous_access()

    # Update anonymous users roles
    nexus_api.update_anonymous_user_roles([pypi_role_name, cran_role_name])


def main():
    parser = ArgumentParser(description="Configure Nexus3")
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
        "--admin-password",
        type=str,
        required=True,
        help="New password for the Nexus 'admin' account",
    )
    parser_password.add_argument(
        "--path",
        type=Path,
        default=Path("./nexus-data"),
        help="Path of the nexus-data directory [./nexus-data]"
    )
    parser_password.set_defaults(func=change_initial_password)

    # sub-command to configure Nexus
    parser_configure = subparsers.add_parser(
        "configure",
        help="Configure the Nexus repository"
    )
    parser_configure.add_argument(
        "--admin-password",
        type=str,
        required=True,
        help="Password for the Nexus 'admin' account",
    )
    parser_configure.add_argument(
        "--tier",
        type=int,
        required=True,
        choices=[2, 3],
        help="Data security tier of the repository",
    )
    parser_configure.set_defaults(func=configure)

    args = parser.parse_args()

    args.func(args)


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

    def create_role(self, name, description, privileges, roles=None):
        if roles is None:
            roles = []

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


if __name__ == "__main__":
    main()
