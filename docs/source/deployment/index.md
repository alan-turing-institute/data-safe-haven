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
- [Hatch](https://hatch.pypa.io/1.9/install/)
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

- Download or checkout the [latest supported version](https://github.com/alan-turing-institute/data-safe-haven/blob/develop/SECURITY.md) of this code from [GitHub](https://github.com/alan-turing-institute/data-safe-haven).
- Enter the base directory and install Python dependencies with `hatch` by doing the following:

:::{code} shell
$ hatch run true
:::
