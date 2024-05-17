# Deployment

```{toctree}
:hidden:

deploy_context.md
deploy_shm.md
deploy_sre.md
```

Deploying an instance of the Data Safe Haven involves the following steps:

- Deploying the context used to host the Pulumi backend infrastructure
- Deploying the Safe Haven management component
- Deploying a Secure Research Environment for each project

## Requirements

Install the following requirements before starting

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Hatch](https://hatch.pypa.io/1.9/install/)
- [Pulumi](https://www.pulumi.com/docs/get-started/install/)

:::{important}
You will also need an account with `Global Administrator` privileges on a Microsoft Entra tenant.
:::

:::{hint}
We suggest creating a new Entra tenant for your DSH deployment, but this is not a requirement.
If you want to do so, follow the instructions [here](https://learn.microsoft.com/en-us/entra/fundamentals/create-new-tenant).
:::

## Install the project

Download or checkout this code from GitHub.

:::{important}
**{sub-ref}`today`**: you should use the `develop` branch as no stable v5 release has been tagged.
Please contact the development team in case of any problems.
:::

Enter the base directory and run:

```{code} shell
$ hatch shell
```

:::{hint}
Using a hatch environment this way ensures that you are using the intended version of Data Safe Haven with the correct set of dependencies.
:::