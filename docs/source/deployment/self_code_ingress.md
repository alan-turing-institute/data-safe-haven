(self_code_ingress)=

# Ingress pre-approved code repositories

For SREs where workspace internet access is disabled, administrators can make selected GitHub repositories available inside the environment without enabling general internet access.
The Data Safe Haven mirrors the configured repositories into the internal Gitea service, where researchers can access them through the `workspaceuser` account.

The mirror service will be deployed only when workspace internet access is disabled and at least one repository is configured.

## Configure repositories

Add repositories under `user_services.gitea_mirror.repositories` in the SRE configuration file:

:::{code} yaml
user_services:
  gitea_mirror:
    repositories:
      - repository_name: data-safe-haven
        repository_url: https://github.com/alan-turing-institute/data-safe-haven
        repository_auth_token: YOUR_READ_ONLY_GITHUB_TOKEN
:::

Add one list entry for each repository to mirror; multiple repositories can be configured.

Each repository entry requires:

- `repository_name`: the name used to identify the repository in the mirror service. This is typically the upstream repository name, but it does not have to match it.
- `repository_url`: the HTTP(S) URL of the GitHub repository. The configuration schema does not accept `git://` URLs; use HTTPS.
- `repository_auth_token`: a read-only GitHub personal access token with access to the repository.

The current mirror manager uses Gitea's GitHub migration service, so repositories hosted by other Git services are not supported by this configuration.
Use a token with only the permissions required to read the repository. If no repositories should be mirrored, leave `repositories` empty.

After the SRE is deployed, the configured repositories are available from the internal Gitea service and are refreshed automatically by the mirror manager.

## Request a repository mirror

If you are a researcher, ask your SRE administrator to approve and configure
a mirror before you need it. Provide:

- The upstream GitHub **HTTPS repository URL** and its name.
- Why the code is needed for your analysis, including any licensing or
  provenance requirements.
- Whether the repository is private, so an appropriately scoped **read-only**
  GitHub access token can be arranged.

Do **not** include access tokens or passwords in the request. The
administrator adds approved repositories and credentials to the SRE
configuration through its secure configuration workflow, then deploys the
updated SRE. Only explicitly configured repositories are mirrored. If a
mirror does not appear or stops updating, ask the administrator to review
the mirror-manager container logs and configuration.

## Use a mirror from inside your workspace

The approved repository is available in the **internal Gitea** service.
From an SRE workspace:

1. Open Gitea using the desktop shortcut and sign in with your normal
   short-form SRE username and password.
2. Select **Explore**, find the mirrored repository, and copy its HTTP(S)
   clone URL from the repository page.
3. Clone it from a workspace terminal:

   :::{code} shell
   $ git clone URL_COPIED_FROM_GITEA
   $ cd REPOSITORY_NAME
   $ git rev-parse HEAD
   :::

   Record the resulting commit ID in your research records for
   reproducibility. When an approved upstream update becomes available, use
   `git pull --ff-only` in a clean clone to update it.

Mirrors are **read-only copies** of upstream GitHub repositories. You cannot
push local changes back to the external source through a mirror. To modify
code or collaborate with other SRE researchers, create a **separate, writable
repository in the internal Gitea**, push a copy there and use branches
and pull requests. Do not include sensitive SRE data in any repository
that might later be transferred outside the environment.

Updates follow the configured mirror schedule, so new upstream commits
may not appear immediately. Mirroring code does not automatically
mirror external dependencies, provide a CI runner, or enable workspace
internet access. Use available packages, run tests within the SRE, and
request any additional approved software from the administrator.

For more Gitea usage instructions, see the
[researcher Gitea guide](../roles/researcher/using_the_sre.md).
