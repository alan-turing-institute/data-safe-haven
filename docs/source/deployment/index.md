# Deployment

:::{toctree}
:hidden:

setup_context.md
configure_entra_id.md
deploy_shm.md
deploy_sre.md
security_checklist.md
:::

Deploying an instance of the Data Safe Haven involves the following steps:

- Configuring the context used to host the Pulumi backend infrastructure
- Configuring the Microsoft Entra directory where you will manage users
- Deploying the Safe Haven management component
- Deploying a Secure Research Environment for each project

## Requirements

Install the following requirements before starting

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [pipx](https://pipx.pypa.io/stable/installation/)
- [Pulumi](https://www.pulumi.com/docs/get-started/install/)

### Docker Hub

The Data Safe Haven uses several public Docker images.
As Docker Hub now imposes [rate limits](https://docs.docker.com/docker-hub/download-rate-limit/) on anonymous downloads, you will need to use a Docker Hub account to deploy the Data Safe Haven.
You can create one following [the instructions here](https://hub.docker.com/) if you do not already have one.

:::{important}
We recommend using a personal access token (PAT) with **Public Repo Read-Only** permissions rather than your Docker account password.
See [the instructions here](https://docs.docker.com/security/for-developers/access-tokens/) for details of how to create a PAT.
:::

## Install the project

- Look up the [latest supported version](https://github.com/alan-turing-institute/data-safe-haven/blob/develop/SECURITY.md) of this code from [GitHub](https://github.com/alan-turing-institute/data-safe-haven).
- Install the executable with `pipx` by running:

:::{code} shell
$ pipx install data-safe-haven
:::

- Or install a specific version with

:::{code} shell
$ pipx install data-safe-haven==5.0.0
:::

::::{admonition} [Advanced] install into a virtual environment
:class: dropdown caution

If you prefer, you can install this package into a virtual environment:

:::{code} shell
$ python -m venv /path/to/new/virtual/environment
$ source /path/to/new/virtual/environment/bin/activate
$ pip install data-safe-haven
:::
::::

- Test that this has worked by checking the version

:::{code} shell
$ dsh --version
:::
