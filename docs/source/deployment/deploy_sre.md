(deploy_sre)=

# Deploy a Secure Research Environment

These instructions will deploy a new  Secure Research Environment (SRE).

::::{admonition} Ensure you are using a `hatch` shell
:class: dropdown important

You must use a `hatch` shell to run any `dsh` commands.
From the project base directory run:

:::{code} shell
$ hatch shell
:::

This ensures that you are using the intended version of Data Safe Haven with the correct set of dependencies.
::::

## Configuration

Each project will have its own dedicated Secure Research Environment (SRE).

- Create a configuration file

```console
> dsh config template --file config.yaml
```

- Edit this file in your favourite text editor, replacing the placeholder text with appropriate values for your setup.

```yaml
azure:
  subscription_id: # ID of the Azure subscription that the TRE will be deployed to
  tenant_id: # Home tenant for the Azure account used to deploy infrastructure: `az account show`
description: # A free-text description of your SRE deployment
dockerhub:
  access_token: # The password or personal access token for your Docker Hub account. We strongly recommend using a Personal Access Token with permissions set to Public Repo Read-only
  username: # Your Docker Hub account name
name: # A name for your SRE deployment containing only letters, numbers, hyphens and underscores
sre:
  admin_email_address: # Email address shared by all administrators
  admin_ip_addresses: # List of IP addresses belonging to administrators
  data_provider_ip_addresses: # List of IP addresses belonging to data providers
  databases: # List of database systems to deploy
  remote_desktop:
    allow_copy: # True/False: whether to allow copying text out of the environment
    allow_paste: # True/False: whether to allow pasting text into the environment
  research_user_ip_addresses: # List of IP addresses belonging to users
  software_packages: # any/pre-approved/none: which packages from external repositories to allow
  timezone: # Timezone in pytz format (eg. Europe/London)
  workspace_skus: # List of Azure VM SKUs - see cloudprice.net for list of valid SKUs
```

## Upload the configuration file

- Upload the config to Azure. This will validate your file and report any problems.

```{code} shell
$ dsh config upload config.yaml
```

## Requirements

:::{important}
As private endpoints for flexible PostgreSQL are still in preview, the following command is currently needed:

```{code} shell
$ az feature register --name "enablePrivateEndpoint" --namespace "Microsoft.DBforPostgreSQL"
```

:::

## Deployment

- Deploy each SRE individually [approx 30 minutes]:

```{code} shell
$ dsh sre deploy _YOUR_SRE_NAME_
```
