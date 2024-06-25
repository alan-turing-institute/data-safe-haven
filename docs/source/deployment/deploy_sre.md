(deploy_sre)=

# Deploy a Secure Research Environment (SRE)

## Configuration

Each project will have its own dedicated Secure Research Environment (SRE).

- Create a configuration file

```console
> dsh config template-sre --file config.yaml
```

- Edit this file in your favourite text editor, replacing the placeholder text with appropriate values for your setup.

```yaml
azure:
  subscription_id: # ID of the Azure subscription that the TRE will be deployed to
  tenant_id: # Home tenant for the Azure account used to deploy infrastructure: `az account show`
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
$ dsh config upload-sre config.yaml
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
$ dsh sre deploy <name of your SRE>
```
