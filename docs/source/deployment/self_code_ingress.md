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
