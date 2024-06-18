(deploy_shm)=

# Deploy a Safe Haven Management Environment (SHM)

These instructions will deploy a new Safe Haven Management Environment (SHM).
This is required to manage your Secure Research Environments (SREs) and **must be** deployed before you create any SREs.

:::{note}
A single SHM can manage all your SREs.
However, you may choose to use multiple SHMs if, for example, you want to separate production and development environments.
:::

## Configuration

- Create a configuration file

```console
> dsh config template --file config.yaml
```

- Edit this file in your favourite text editor, replacing the placeholder text with appropriate values for your setup.

```yaml
azure:
  subscription_id: # ID of the Azure subscription that the TRE will be deployed to
  tenant_id: # Home tenant for the Azure account used to deploy infrastructure: `az account show`
shm:
  entra_tenant_id: # Tenant ID for the Entra ID used to manage TRE users
  fqdn: # Domain you want your users to belong to and where your TRE will be deployed
```

## Upload the configuration file

- Upload the config to Azure. This will validate your file and report any problems.

```{code} shell
$ dsh config upload config.yaml
```

## Deployment

- Next deploy the Safe Haven Management (SHM) infrastructure [approx 30 minutes]:

```{code} shell
$ dsh shm deploy
```

:::{important}
You may be asked to delegate your domain name to Azure. To do this, you'll need to know details about the parent domain. For example, if you are deploying to `dsh.example.com` then the parent name is `example.com`.

- Follow [this tutorial](https://learn.microsoft.com/en-us/azure/dns/dns-delegate-domain-azure-dns#delegate-the-domain) if the parent domain is hosted outside Azure
- Follow [this tutorial](https://learn.microsoft.com/en-us/azure/dns/tutorial-public-dns-zones-child#verify-the-child-dns-zone) if the parent domain is hosted in Azure

:::
