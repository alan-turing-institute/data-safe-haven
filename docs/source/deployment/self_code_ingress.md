(self_code_ingress)=

# Ingress pre-approved code repositories

For Tier 2 and Tier 3 SREs, administrators can make selected GitHub repositories available inside the environment without enabling general workspace internet access.
Data Safe Haven mirrors the configured repositories into the internal Gitea service, where researchers can access them through the `workspaceuser` account.

The mirror service is not deployed for Tier 0 and Tier 1 SREs, which already have direct internet access.

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

Each repository entry requires:

- `repository_name`: the name used to identify the repository in the mirror service.
- `repository_url`: the GitHub repository URL.
- `repository_auth_token`: a read-only GitHub personal access token with access to the repository.

Use a token with only the permissions required to read the repository. If no repositories should be mirrored, leave `repositories` empty.

After the SRE is deployed, the configured repositories are available from the internal Gitea service and are refreshed automatically by the mirror manager.
